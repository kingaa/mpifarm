#! /usr/local/bin/Rscript --vanilla

## a script for running multiple MIFs using Rmpi and mpifarm

## set some default values
nreps <- 1         # number of replicate MIFs to run per parameter set
nmifs <- 20                       # total number of MIFs per replicate
unweighted <- 0                  # number of unweighted MIF iterations
max.fail <- 100 # maximum number of filtering failures before an error is triggered
gran <- 5                               # granularity (MIFs per chunk)

nparticles <- 10000                     # pfilter's Np
cooling <- 0.99                         # cooling factor
ic.lag <- 60                            # fixed lag for IVP estimation
var.factor <- 4                         # MIF's variance factor
init.disp <- 0           # initial displacement of starting conditions

filter.q <- TRUE   # estimate the loglikelihood after all the MIFfing?
nfilters <- 10 # number of independent particle filter runs used to estimate the log likelihood

jobname <- NULL           # this must be set by a commandline argument
modelStem <- NULL

scratchdir <- paste("/scratch/",system("whoami",intern=T),"/",sep="") # scratch directory

## get, parse, and evaluate the command-line arguments
eval(parse(text=commandArgs(trailingOnly=TRUE)))

if (is.null(modelStem)) 
  stop("you must supply a ",sQuote("modelStem"))

modelRfile <- paste(modelStem,"R",sep=".") # file where 'transform.fn' and 'make.pomp' are defined
modelCfile <- paste(modelStem,"c",sep=".") # file where 'transform.fn' and 'make.pomp' are defined
solib <- paste(modelStem,"so",sep=".") # if this is set to the stem-name of the SO library, the library will be loaded

if (is.null(jobname))
  stop("you must supply a ",sQuote("jobname"))

if (!file.exists(modelRfile))
  stop("file ",sQuote(modelRfile)," not found")

rexe <- paste(R.home(),"bin/R",sep="/")
pomp.inc <- system.file("include/pomp.h",package="pomp")
pomp.lib <- system.file("libs/pomp.so",package="pomp")
system(paste("cp",pomp.inc,".",sep=" "))
system(paste(rexe,"CMD SHLIB -o",solib,modelCfile,pomp.lib,sep=" "))
system("rm pomp.h")

if (!is.null(solib) && !file.exists(solib))
  stop("file ",sQuote(solib)," not found")

## the following cannot be changed by commandline arguments
id <- paste(basename(getwd()),jobname,sep='_') # an identifier for the files to be saved
imagefile <- paste('image_',jobname,'.rda',sep='') # binary file for saving the workspace
mpfile <- paste('modelparams_',jobname,'.csv',sep='') # input parameter file
bestfile <- paste('best_',jobname,'.csv',sep='') # CSV file to store MLEs
mlefile <- paste('mle_',jobname,'.rda',sep='') # binary file to store MLEs
checkpointfile <- file.path(scratchdir,paste(id,".rda",sep=""))

require(Rmpi)
require(mpifarm)
require(pomp)

if (!exists("checkpoint")) checkpoint <- mpi.universe.size()  # checkpoint granularity

source(modelRfile)         # model-specific codes, loading data, etc.
if (!(exists("par.trans")&&exists("par.untrans")&&exists("make.pomp")))
  stop("file ",sQuote(modelRfile)," does not define ",sQuote("transform.fn")," and ",sQuote("make.pomp")," as it should")

if (file.exists(imagefile)) {   # we are continuing where we left off?

  load(imagefile)

} else {                                # we are starting from scratch

  ## read the input parameter file
  parameters <- read.csv(file=mpfile)   

  ## fetch out the random-walk SDs
  sigma <- parameters[parameters$dataset=='sd',]
  sigma$dataset <- NULL
  sigma$model <- NULL
  sigma <- unlist(sigma) 
  sigma <- log(1+sigma)

  ## fetch out the dataset and model names
  parameters <- parameters[parameters$dataset!='sd',]
  datasets <- as.character(parameters$dataset)
  parameters$dataset <- NULL
  models <- as.character(parameters$model)
  parameters$model <- NULL

  ndsets <- length(datasets)            # number of datasets
  njobs <- nreps*ndsets                 # total number of jobs

  ## each job will have its own RNG seed
  seeds <- as.integer(ceiling(runif(n=njobs,min=0,max=2^31)))

  ## 'joblist' will be a list of lists, each of which will be used
  ## as an environment for execution of a distinct parallel job
  joblist <- vector(mode='list',length=njobs)
  count <- 0
  for (d in seq(length=ndsets)) {
    po <- make.pomp(dataset=datasets[d],model=models[d])               
    guess.params <- unlist(parameters[d,])
    theta.x <- matrix(
                      data=rnorm(
                        n=nreps*length(guess.params),
                        mean=par.trans(po,guess.params),
                        sd=init.disp*sigma
                        ),
                      ncol=nreps,
                      nrow=length(guess.params),
                      dimnames=list(names(guess.params),NULL)
                      )
    sigma <- sigma[sigma>0] # the random-walk SDs
    parnames <- names(sigma)
    ivpnames <- grep(glob2rx("*.0"),parnames,val=T)
    parnames <- parnames[!(parnames%in%ivpnames)]

    for (r in seq(length=nreps)) {
      count <- count+1
      joblist[[count]] <- list(
                               mle=mif(
                                 po,
                                 Nmif=0,
                                 start=theta.x[,r],
                                 ivps=ivpnames,
                                 pars=parnames,
                                 rw.sd=sigma,
                                 Np=nparticles,
                                 cooling.factor=cooling,
                                 ic.lag=ic.lag,
                                 var.factor=var.factor
                                 ),
                               seed=seeds[count],
                               model=models[d],
                               dataset=datasets[d],
                               done=0
                               )
    }
  }

  save(list='joblist',file=imagefile)
}

mpi.spawn.Rslaves(needlog=F)

tic <- Sys.time()

results <- mpi.farm(
                    { # this is the expression to be evaluated on each slave
                      require(pomp)
                      ## name of a file in which to save checkpoints
                      ckptfile <- file.path(scratchdir,paste(dataset,'_',id,'_',done,'_',seed,'.rda',sep=''))
                      if (!is.null(solib)) dyn.load(solib) # load the SO library
                      if (done == 0) {  # first MIF runs
                        save.seed <- .Random.seed
                        set.seed(seed)
                        rngstate <- .Random.seed
                        .Random.seed <<- save.seed
                      }
                      if (done < nmifs) { # continue MIFfing
                        save.seed <- .Random.seed
                        .Random.seed <<- rngstate
                        mle <- continue(
                                        mle,
                                        Nmif=min(gran,nmifs-done),
                                        weighted=(done>unweighted),
                                        warn=FALSE,
                                        max.fail=max.fail
                                        )
                        done <- done+gran
                        nfail <- conv.rec(mle,'nfail')
                        nfail <- nfail[length(nfail)-1]
                        loglik <- logLik(mle)
                        rngstate <- .Random.seed
                        .Random.seed <<- save.seed
                        all.done <- FALSE
                      } else if (filter.q) { # final particle filtering
                        save.seed <- .Random.seed
                        .Random.seed <<- rngstate
                        ff <- lapply(
                                     seq(length=nfilters),
                                     function(n)pfilter(
                                                        mle,
                                                        max.fail=max.fail
                                                        )
                                     )
                        nfail <- sapply(ff,function(x)x$nfail)
                        loglik <- sapply(ff,function(x)x$loglik)
                        rngstate <- .Random.seed
                        .Random.seed <<- save.seed
                        all.done <- TRUE
                      } else {          # nothing to do
                        all.done <- TRUE
                      }
                      if (!is.null(solib)) dyn.unload(solib) # unload the SO library
                      result <- list(
                                     mle=mle,
                                     model=model,
                                     dataset=dataset,
                                     done=done,
                                     seed=seed,
                                     rngstate=.Random.seed,
                                     nfail=nfail,
                                     loglik=loglik,
                                     all.done=all.done
                                     )
                      save('result',file=ckptfile)
                      result
                    },
                    joblist=joblist,    # the list of jobs
                    common=list( # variables that have the same value across jobs
                      scratchdir=scratchdir,
                      id=id,
                      unweighted=unweighted,
                      max.fail=max.fail,
                      nfilters=nfilters,
                      filter.q=filter.q,
                      gran=gran,
                      nmifs=nmifs,
                      solib=solib
                      ),
                    stop.condition=(all.done),
                    checkpoint=checkpoint,
                    checkpoint.file=checkpointfile,
                    info=TRUE
                    )

toc <- Sys.time()
print(toc-tic)

mpi.close.Rslaves()
mpi.exit()

noerr <- !sapply(results,inherits,"try-error")
joblist <- results[noerr]
err <- results[!noerr]
if (length(err)>0) print(err)

save(list=c('joblist','err'),file=imagefile)

## collate the results for storage in a CSV file
if (filter.q) {
  x <- Reduce(
              function(x,y)merge(x,y,all=T),
              lapply(
                     joblist,
                     function (x) {
                       cbind(
                             data.frame(
                                        dataset=x$dataset,
                                        model=x$model,
                                        loglik=mean(x$loglik),
                                        loglik.sd=sd(x$loglik),
                                        nfail.max=max(x$nfail),
                                        nfail.min=min(x$nfail)
                                        ),
                             as.list(par.untrans(x$mle,coef(x$mle)))
                             )
                     }
                     )
              )

  x <- x[order(x$dataset,x$model,-x$loglik),]
  write.csv(x,file=bestfile,row.names=FALSE,na="")

}

q(save='no',status=0)
