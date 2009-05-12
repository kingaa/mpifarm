## for running multiple MIFs using Rmpi and mpifarm

mif.farm.joblist <- function (nreps = 1, init.disp = 0,
                              parameters,
                              make.pomp, ...) {

  if (missing(make.pomp))
    stop("the function ",sQuote("make.pomp")," must be supplied")
  
## fetch out the random-walk SDs
  sigma <- parameters[parameters$dataset=='sd',]
  sigma$dataset <- NULL
  sigma$model <- NULL
  sigma <- unlist(sigma) 
##  sigma <- sigma[sigma>0]
  sigma <- log(1+sigma[sigma>0])
  
  parnames <- names(sigma)
  ivpnames <- grep(glob2rx("*.0"),parnames,val=T)
  parnames <- parnames[!(parnames%in%ivpnames)]

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
    po <- make.pomp(dataset=datasets[d],model=models[d],...)               
    guess.params <- unlist(parameters[d,])
    theta.x <- matrix(
                      data=par.trans(po,guess.params),
                      ncol=nreps,
                      nrow=length(guess.params),
                      dimnames=list(names(guess.params),NULL)
                      )
    theta.x[names(sigma),] <- rnorm(
                                    n=nreps*length(sigma),
                                    mean=theta.x[names(sigma),],
                                    sd=init.disp*sigma
                                    )

    for (r in seq(length=nreps)) {
      count <- count+1
      joblist[[count]] <- list(
                               mle=po,
                               start=theta.x[,r],
                               rw.sd=sigma,
                               ivpnames=ivpnames,
                               parnames=parnames,
                               seed=seeds[count],
                               model=models[d],
                               dataset=datasets[d],
                               done=0
                               )
    }
  }
  joblist
}

mif.farm <- function (joblist,
                      jobname = NULL,
                      solib = NULL,
                      nmifs = 10,
                      unweighted = 0,
                      max.fail = 0,
                      gran = 5,
                      Np = 1000,
                      cooling.factor = 0.99,
                      ic.lag = 60,
                      var.factor = 4,
                      filter.q = TRUE,
                      nfilters = 10,
                      scratchdir = getwd(),
                      checkpoint = mpi.universe.size(),
                      ...) {
  
  if (is.null(jobname))
    stop("you must supply a ",sQuote("jobname"))

  if (!is.null(solib) && !file.exists(solib))
    stop("file ",sQuote(solib)," not found")

  if ((!is.list(joblist))||!(is.list(joblist[[1]]))||(is.null(names(joblist[[1]]))))
    stop(sQuote("joblist")," must be a list of named lists")

  id <- paste(basename(getwd()),jobname,sep='_') # an identifier for the files to be saved
  checkpointfile <- file.path(scratchdir,paste(id,".rda",sep="")) # binary file for checkpoints

  finished <- mpi.farm(
                       { # this is the expression to be evaluated on each slave
                         require(pomp)
                         ## name of a file in which to save individual-job checkpoints
                         ckptfile <- file.path(scratchdir,paste(dataset,'_',id,'_',done,'_',seed,'.rda',sep=''))
                         if (!is.null(solib)) dyn.load(solib) # load the SO library
                         if (done==0) {  # first MIF runs
                           save.seed <- .Random.seed
                           set.seed(seed)
                           rngstate <- .Random.seed
                           .Random.seed <<- save.seed
                           if (nmifs>0) {
                             mle <- mif(
                                        mle,
                                        Nmif=0,
                                        start=start,
                                        ivps=ivpnames,
                                        pars=parnames,
                                        rw.sd=rw.sd,
                                        Np=Np,
                                        cooling.factor=cooling.factor,
                                        ic.lag=ic.lag,
                                        var.factor=var.factor
                                        )
                           }
                         }
                         if (done < nmifs) { # continue MIFfing
                           save.seed <- .Random.seed
                           .Random.seed <<- rngstate
                           mle <- continue(
                                           mle,
                                           Nmif=min(gran,nmifs-done),
                                           Np=Np,
                                           cooling.factor=cooling.factor,
                                           ic.lag=ic.lag,
                                           var.factor=var.factor,
                                           weighted=(done>unweighted),
                                           warn=FALSE,
                                           max.fail=max.fail
                                           )
                           done <- done+gran
                           nfail <- conv.rec(mle,'nfail')
                           nfail <- nfail[length(nfail)-1]
                           loglik <- logLik(mle)
                           pred.mean <- NA
                           pred.var <- NA
                           filter.mean <- NA
                           cond.loglik <- NA
                           eff.sample.size <- NA
                           all.done <- FALSE
                         } else if (filter.q) { # final particle filtering
                           save.seed <- .Random.seed
                           .Random.seed <<- rngstate
                           ff <- lapply(
                                        seq(length=nfilters),
                                        function(n)pfilter(
                                                           mle,
                                                           max.fail=max.fail,
                                                           pred.mean=TRUE,
                                                           pred.var=TRUE,
                                                           filter.mean=TRUE
                                                           )
                                        )
                           nfail <- sapply(ff,function(x)x$nfail)
                           loglik <- sapply(ff,function(x)x$loglik)
                           pred.mean <- sapply(ff,function(x)x$pred.mean)
                           pred.var <- sapply(ff,function(x)x$pred.var)
                           filter.mean <- sapply(ff,function(x)x$filter.mean)
                           cond.loglik <- sapply(ff,function(x)x$cond.loglik)
                           eff.sample.size <- sapply(ff,function(x)x$eff.sample.size)
                           all.done <- TRUE
                         } else {          # nothing to do
                           all.done <- TRUE
                         }
                         rngstate <- .Random.seed
                         .Random.seed <<- save.seed
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
                                        pred.mean=pred.mean,
                                        pred.var=pred.var,
                                        filter.mean=filter.mean,
                                        cond.loglik=cond.loglik,
                                        eff.sample.size=eff.sample.size,
                                        all.done=all.done
                                        )
                         save('result',file=ckptfile)
                         result
                       },
                       joblist=joblist,
                       common=list(
                         scratchdir=scratchdir,
                         id=id,
                         unweighted=unweighted,
                         max.fail=max.fail,
                         nfilters=nfilters,
                         filter.q=filter.q,
                         gran=gran,
                         nmifs=nmifs,
                         solib=solib,
                         Np=Np,
                         cooling.factor=cooling.factor,
                         ic.lag=ic.lag,
                         var.factor=var.factor,
                         ...
                         ),
                       stop.condition=(all.done),
                       checkpoint=checkpoint,
                       checkpoint.file=checkpointfile,
                       info=TRUE
                       )

  noerr <- !sapply(finished,inherits,"try-error")
  err <- finished[!noerr]
  finished <- finished[noerr]
  if (length(err)>0) lapply(err,function(x)print(as.character(x)))

  save(list=c('finished','err'),file=checkpointfile)

  ## collate the results for storage in a CSV file
  if (filter.q) {
    x <- Reduce(
                function(x,y)merge(x,y,all=T),
                lapply(
                       finished,
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
  } else {
    x <- Reduce(
                function(x,y)merge(x,y,all=T),
                lapply(
                       finished,
                       function (x) {
                         cbind(
                               data.frame(
                                          dataset=x$dataset,
                                          model=x$model,
                                          loglik=NA,
                                          loglik.sd=NA,
                                          nfail.max=NA,
                                          nfail.min=NA
                                          ),
                               as.list(par.untrans(x$mle,coef(x$mle)))
                               )
                       }
                       )
                )
    x <- x[order(x$dataset,x$model),]
  }

  list(
       finished=finished,
       err=err,
       mle=x
       )
}
