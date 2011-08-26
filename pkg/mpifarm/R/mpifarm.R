### farm out a bunch of jobs in parallel if possible, run serially if not
mpi.farm <- function (proc, joblist, common=list(),
                      finished = list(),
                      stop.condition = TRUE, info = TRUE,
                      checkpoint = NULL, checkpoint.file = NULL,
                      verbose = getOption("verbose")) {
  ncpus <- try(mpi.comm.size(),silent=TRUE)
  if (!is.list(joblist))
    stop("joblist must be a list")
  if (is.null(names(joblist)))
    names(joblist) <- seq(length=length(joblist))
  else
    names(joblist) <- make.unique(names(joblist))
  if ((!inherits(ncpus,"try-error"))&&(ncpus > 1)) { # run in parallel mode
    if (is.null(checkpoint.file)) {
      if (!is.null(checkpoint))
        stop("for checkpointing to work, ",sQuote("checkpoint.file")," must be set",call.=FALSE)
      checkpointing <- FALSE
    } else {
      if (!is.character(checkpoint.file))
        stop(sQuote("checkpoint.file")," must be a filename",call.=FALSE)
      if (file.exists(checkpoint.file))
        stop("file ",sQuote(checkpoint.file)," exists",call.=FALSE)
      if ((is.null(checkpoint))||(checkpoint<0))
        stop("for checkpointing to work, ",sQuote("checkpoint")," must be set to a positive integer",call.=FALSE)
      checkpoint <- as.integer(checkpoint)
      if (checkpoint>0) {
        file.ok <- file.create(checkpoint.file)
        if (!file.ok) {
          stop(
               "cannot create checkpoint file ",
               sQuote(checkpoint.file),
               call.=FALSE
               )
        } else {
          file.remove(checkpoint.file)
        }
        checkpointing <- TRUE
      } else {
        checkpointing <- FALSE
      }
    }
    mpi.bcast.Robj2slave(mpi.farm.slave)  # broadcast the slave function
    mpi.bcast.cmd(if(!exists('.Random.seed')) runif(1)) # initialize the RNG if necessary
    fn <- deparse(substitute(proc))      # deparse the procedure to text
    stop.condn <- deparse(substitute(stop.condition)) # deparse the stop condition
    mpi.remote.exec(mpi.farm.slave,fn,common,verbose=verbose,ret=FALSE) # start up the slaves
    finished <- list()
    in.progress <- list()
    nslave <- mpi.comm.size()-1
    if (nslave > length(joblist)) {
      warning("mpi.farm warning: more slaves than jobs",call.=FALSE)  
    }
    slaves.at.leisure <- as.list(seq(from=1,to=nslave,by=1))
    last.etimes <- numeric(nslave)
    live <- seq(from=1,to=nslave,by=1)    # numbers of live slaves
    slaveinfo <- matrix(
                        data=0,
                        nrow=1,
                        ncol=nslave+1,
                        dimnames=list('jobs',c(live,'total'))
                        )
    sent <- 0
    rcvd <- 0
    nerr <- 0
    withRestarts(
                 {

                   for (d in seq(length=nslave)) { # initialize the queue
                     if (length(joblist)>0) {      # farm out the work
                       ## pop the next job off the stack and send it out
                       mpi.send.Robj(joblist[1],dest=slaves.at.leisure[[1]],tag=3) 
                       sent <- sent+1
                       in.progress <- append(in.progress,joblist[1])
                       joblist[[1]] <- NULL
                       slaves.at.leisure[[1]] <- NULL
                       last.etimes <- tail(last.etimes,-1)
                     }
                   }
                   while (rcvd < sent) {
                     ## wait for someone to finish
                     res <- mpi.recv.Robj(source=mpi.any.source(),tag=mpi.any.tag()) 
                     rcvd <- rcvd+1
                     srctag <- mpi.get.sourcetag()
                     src <- srctag[1]   # who did it?
                     tag <- srctag[2]   # were they succesful?
                     slaves.at.leisure <- c(slaves.at.leisure,src)
                     last.etimes <- c(last.etimes,as.numeric(res$etime,units="secs"))
                     identifier <- res$id
                     in.progress[[identifier]] <- NULL
                     piece <- list(res$result)
                     names(piece) <- identifier
                     ##     srt <- order(last.etimes)
                     ##     slaves.at.leisure <- slaves.at.leisure[srt]
                     ##     last.etimes <- last.etimes[srt]
                     if (tag == 33) {                    # success
                       slaveinfo[1,src] <- slaveinfo[1,src]+1
                       slaveinfo[1,nslave+1] <- slaveinfo[1,nslave+1]+1
                       if (info) print(slaveinfo)
                       if (is.list(res$result)) {         # are we all finished with this job?
                         stq <- as.logical(eval(parse(text=stop.condn),envir=res$result))
                       } else {
                         stq <- TRUE
                       }
                       if (is.na(stq))
                         stop(sQuote("stop.condition")," must evaluate to TRUE or FALSE")
                       if (stq) {       # should we stop?
                         finished <- append(finished,piece)
                       } else {
                         joblist <- append(joblist,piece)
                       }
                     } else {           # an error occurred
                       if (info)
                         message('slave ',format(src),' reports: ',res$result)
                       else
                         warning('mpi.farm: slave ',format(src),' reports: ',res$result,call.=FALSE)
                       finished <- append(finished,piece)
                       nerr <- nerr+1
                     }
                     if ((checkpointing)&&((rcvd%%checkpoint)==0)) {
                       unfinished <- append(joblist,in.progress)
                       if (info) cat(
                                     "writing checkpoint file",
                                     sQuote(checkpoint.file),
                                     "\n#finished =",length(finished)-nerr,
                                     "#unfinished =",length(unfinished),
                                     "#error =",nerr,
                                     "\n"
                                     )
                       save(unfinished,finished,file=checkpoint.file)
                     }
                     if (length(joblist)>0) {       # is there more to do?
                       ## pop the next job off the stack and send it out
                       mpi.send.Robj(joblist[1],dest=slaves.at.leisure[[1]],tag=3) 
                       sent <- sent+1
                       in.progress <- append(in.progress,joblist[1])
                       joblist[[1]] <- NULL
                       slaves.at.leisure[[1]] <- NULL
                       last.etimes <- tail(last.etimes,-1)
                     }
                   }
                   for (d in live) {
                     mpi.send.Robj(0,dest=d,tag=666)
                   }
                 },
                 abort=function(){
                   cat("aborting mpi.farm: please be patient!\n\n")
                   invokeRestart("cleanup")
                 },
                 cleanup=function(){
                   while (rcvd < sent) {
                     res <- mpi.recv.Robj(source=mpi.any.source(),tag=mpi.any.tag()) # wait for someone to finish
                     srctag <- mpi.get.sourcetag()
                     src <- srctag[1]                    # who did it?
                     tag <- srctag[2]                    # were they succesful?
                     rcvd <- rcvd+1
                     identifier <- res$id
                     in.progress[[identifier]] <- NULL
                     piece <- list(res$result)
                     names(piece) <- identifier
                     if (tag == 33) {                    # success
                       slaveinfo[1,src] <- slaveinfo[1,src]+1
                       slaveinfo[1,nslave+1] <- slaveinfo[1,nslave+1]+1
                       if (info) print(slaveinfo)
                     } else {                            # an error occurred
                       if (info)
                         message('slave ',format(src),' reports: ',res$result)
                       else
                         warning('mpi.farm: slave ',format(src),' reports: ',res$result,call.=FALSE)
                       nerr <- nerr+1
                     }
                     finished <- append(finished,piece)
                   }
                   for (d in live)
                     mpi.send.Robj(0,dest=d,tag=666)
                   cat("mpi.farm aborted cleanly\n")
                 },
                 abort=function(){
                   cat(
                       "mpi.farm not aborted cleanly.\n",
                       "It is recommended that you terminate the slaves by hand!\n\n"
                       )
                 }
                 )
  } else {                 # no slaves are running: run in serial mode
    if (!exists('.Random.seed')) runif(1)
    fun <- substitute(proc)
    stop.condn <- substitute(stop.condition)
    while (length(joblist)>0) {
      identifier <- names(joblist)[1]
      res <- try(
                 evalq(eval(fun,envir=joblist[[1]]),envir=common),
                 silent=TRUE
                 )
      if (is.list(res)) {         # are we all finished with this job?
        stq <- as.logical(eval(stop.condn,envir=res))
      } else {
        stq <- TRUE
      }
      piece <- list(res)
      names(piece) <- identifier
      if (is.na(stq))
        stop(sQuote("stop.condition")," must evaluate to TRUE or FALSE")
      if (stq) {                        # should we stop?
        finished <- append(finished,piece)
        joblist[[1]] <- NULL
      } else {
        joblist <- append(joblist,piece)
        joblist[[1]] <- NULL
      }
      if (inherits(res,"try-error")) {
        if (info)
          message("mpi.farm (serial) reports: ",res)
        else
          warning("mpi.farm (serial) reports: ",res)
      }
    }
  }
  finished
}

## slave procedure for mpi.farm
mpi.farm.slave <- function (fn, common = list(), verbose = getOption("verbose")) { 
  proc <- parse(text=fn)
  me <- mpi.comm.rank()
  go <- TRUE
  while (go) {
    if (verbose)
      cat("slave",me,"awaiting instructions\n")
    rcv <- mpi.recv.Robj(source=0,tag=mpi.any.tag())
    identifier <- names(rcv)
    srctag <- mpi.get.sourcetag()
    if (srctag[2] == 3) {               # we have a job to do
      if (verbose)
        cat("slave",me,"getting to work\n")
      tic <- Sys.time()
      result <- try(
                    evalq(eval(proc,envir=rcv[[1]]),envir=common),
                    silent=FALSE
                    )
      toc <- Sys.time()
      if (inherits(result,'try-error')) {
        tag <- 66                       # error
      } else {
        tag <- 33                       # success
      }
      snd <- list(id=identifier,result=result,etime=toc-tic)
      if (verbose)
        cat("slave",me,"sending results\n")
      mpi.send.Robj(snd,dest=0,tag=tag)
    } else {                         # no job to do, our time has come
      if (verbose)
        cat("slave",me,"terminating\n")
      go <- FALSE                       # terminate
    }
  }
}
