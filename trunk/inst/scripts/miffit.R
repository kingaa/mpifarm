#! /usr/local/bin/Rscript --vanilla

## a script for running multiple MIFs using Rmpi and mpifarm

## set some default values
nreps <- 2         # number of replicate MIFs to run per parameter set
nmifs <- 80                       # total number of MIFs per replicate
unweighted <- 0                  # number of unweighted MIF iterations
max.fail <- 100 # maximum number of filtering failures before an error is triggered
gran <- 4                               # granularity (MIFs per chunk)

nparticles <- 10000                     # pfilter's Np
cooling <- 0.95                         # cooling factor
ic.lag <- 60                            # fixed lag for IVP estimation
var.factor <- 4                         # MIF's variance factor
init.disp <- 0           # initial displacement of starting conditions

filter.q <- TRUE   # estimate the loglikelihood after all the MIFfing?
nfilters <- 10 # number of independent particle filter runs used to estimate the log likelihood

jobname <- NULL           # this must be set by a commandline argument
scratchdir <- paste("/state/partition1/",system("whoami",intern=T),"/",sep="") # scratch directory

modelRfile <- NULL # file where 'transform.fn' and 'make.pomp' are defined
solib <- NULL # if this is set to the stem-name of the SO library, the library will be loaded

## get, parse, and evaluate the command-line arguments
eval(parse(text=commandArgs(trailingOnly=TRUE)))

if (is.null(jobname))
  stop("you must supply a ",sQuote("jobname"))

if (!is.null(solib) && !file.exists(solib))
  stop("file ",sQuote(solib)," not found")

if (!file.exists(modelRfile))
  stop("file ",sQuote(modelRfile)," not found")

## the following cannot be changed by commandline arguments
id <- paste(basename(getwd()),jobname,sep='_') # an identifier for the files to be saved
imagefile <- paste('image_',jobname,'.rda',sep='') # binary file for saving the workspace
mpfile <- paste('modelparams_',jobname,'.csv',sep='') # input parameter file
bestfile <- paste('best_',jobname,'.csv',sep='') # CSV file to store MLEs
mlefile <- paste('mle_',jobname,'.rda',sep='') # binary file to store MLEs

require(Rmpi)
mpi.spawn.Rslaves(needlog=F)
require(mpifarm)

require(pomp)

if (!file.exists(modelRfile))
  stop("file ",sQuote(modelRfile)," not found")
source(modelRfile)         # model-specific codes, loading data, etc.
if (!(exists("transform.fn")&&exists("make.pomp")))
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
    theta.guess <- unlist(parameters[d,]) # extract the starting (guess) parameters
    sig <- sigma[is.finite(theta.guess)&(sigma>0)] # the random-walk SDs
    theta.guess <- theta.guess[is.finite(theta.guess)] # only finite guesses play any role
    par.trans <- transform.fn(model=models[d],dir='transform') # transform parameters
    theta.guess <- par.trans(theta.guess)
    theta.x <- matrix(
                      data=theta.guess,
                      ncol=nreps,
                      nrow=length(theta.guess),
                      dimnames=list(names(theta.guess),NULL)
                      )
    ## add some random variability to explore the parameter space
    theta.x[names(sig),] <- rnorm(
                                    n=nreps*length(sig),
                                    mean=theta.guess[names(sig)],
                                    sd=init.disp*sig
                                    )
    po <- make.pomp(dataset=datasets[d],model=models[d])               

    for (r in seq(length=nreps)) {
      count <- count+1
      ivpnames <- grep('\\.0$',names(sig),value=T,perl=T)
      estnames <- names(sig)[!(names(sig)%in%ivpnames)]
      set.seed(seeds[count])
      rngstate <- .Random.seed
      joblist[[count]] <- list(
                               mle=mif(
                                 po,
                                 Nmif=0,
                                 start=theta.x[,r],
                                 ivps=ivpnames,
                                 pars=estnames,
                                 rw.sd=sig,
                                 alg.pars=list(
                                   Np=nparticles,
                                   cooling.factor=cooling,
                                   ic.lag=ic.lag,
                                   var.factor=var.factor
                                   )
                                 ),
                               rngstate=rngstate,
                               seed=seeds[count],
                               model=models[d],
                               dataset=datasets[d],
                               done=0
                               )
    }
  }

  save(list='joblist',file=imagefile)
}

tic <- Sys.time()

joblist <- mpi.farm(
                    { # this is the expression to be evaluated on each slave
                      require(pomp)
                      ## name of a file in which to save checkpoints
                      ckptfile <- file.path(scratchdir,paste(dataset,'_',id,'_',done,'_',seed,'.rda',sep=''))
                      if (!is.null(solib)) dyn.load(solib) # load the SO library
                      if (done < nmifs) { # continue MIFfing
                        save.seed <- .Random.seed
                        .Random.seed <<- rngstate
                        mle <- continue(
                                        mle,
                                        Nmif=gran,
                                        weighted=(done>unweighted),
                                        warn=FALSE,
                                        max.fail=max.fail
                                        )
                        done <- done+gran
                        nfail <- conv.rec(mle,'nfail')
                        nfail <- nfail[length(nfail)-1]
                        loglik <- logLik(mle)
                        .Random.seed <<- save.seed
                        all.done <- FALSE
                      } else if (filter.q) { # final particle filtering
                        save.seed <- .Random.seed
                        .Random.seed <<- rngstate
                        ff <- lapply(
                                     1:nfilters,
                                     function(n)pfilter(mle,max.fail=1000)
                                     )
                        nfail <- sapply(ff,function(x)x$nfail)
                        loglik <- sapply(ff,function(x)x$loglik)
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
                    info=TRUE
                    )

toc <- Sys.time()
print(toc-tic)
save(list='joblist',file=imagefile)

## collate the results for storage in a CSV file
x <- Reduce(
            function(x,y)merge(x,y,all=T),
            lapply(
                   joblist,
                   function (x) {
                     par.untrans <- transform.fn(model=x$model,dir='untransform')
                     cbind(
                           data.frame(
                                      model=x$model,
                                      dataset=x$dataset
                                      loglik=mean(x$loglik),
                                      loglik.sd=sd(x$loglik),
                                      nfail.max=max(x$nfail),
                                      nfail.min=min(x$nfail)
                                      ),
                           as.list(par.untrans(coef(x$mle)))
                           )
                   }
                   )
            )

## extract the best likelihood for each dataset/model combination
best.ind <- tapply(1:nrow(x),list(x$dataset,x$model),function(k)k[which.max(x$loglik[k])])
best <- x[best.ind,]
best <- best[order(as.character(best$dataset)),]
write.csv(best,file=bestfile,row.names=FALSE,na="")

## also save the MIF objects in a binary file
mle <- lapply(
              joblist[best.ind],
              function(x)x$mle
              )
names(mle) <- sapply(joblist[best.ind],function(x)x$dataset)
mle <- mle[order(names(mle))]
save(list='mle',file=mlefile)

mpi.close.Rslaves()
mpi.exit()

q(save='no',status=0)
