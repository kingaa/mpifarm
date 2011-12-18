### farm out a bunch of jobs in parallel if possible, run serially if not
mpi.farm <- function (proc, joblist, common=list(), status = NULL, chunk = 1,
                      stop.condition = TRUE, info = TRUE,
                      checkpoint = NULL, checkpoint.file = NULL,
                      max.backup = 20,
                      verbose = getOption("verbose")) {

  ncpus <- try(mpi.comm.size(),silent=TRUE)
  if (inherits(ncpus,"try-error"))
    ncpus <- 1

  chunk <- as.integer(chunk)
  if ((chunk<1)||(length(chunk)>1))
    stop(sQuote("chunk")," must be a single positive integer")

  max.backup <- as.integer(max.backup)
  if (max.backup < 1) stop(sQuote("max.backup")," must be a positive integer")

  if (!is.list(joblist))
    stop("joblist must be a list")
  if (is.null(names(joblist)))
    names(joblist) <- as.character(seq_along(joblist))

  ## 'status' is an integer holding the status codes for 
  ## each individual job.
  ## status codes:
  ##        0 = waiting incomplete,
  ##        1 = running,
  ##        2 = finished OK,
  ##        4 = finished ERROR,
  ##       -1 = undetermined
  WAITING <- 0L
  RUNNING <- 2L
  FINISHED <- 1L
  ERROR <- -1L
  TMP <- 8L

  if (is.null(status)) {
    status <- rep(WAITING,length(joblist))
    names(status) <- names(joblist)
  } else if (length(status)!=length(joblist)) {
    stop(sQuote("joblist")," and ",sQuote("status")," must have the same length")
  } else if (is.null(names(status))) {
    status <- as.integer(status)
    names(status) <- names(joblist)
  } else if (any(!(names(status)%in%names(joblist)))) {
    stop("some names of ",sQuote("status")," correspond to no names of ",sQuote("joblist"))
  } else {
    status <- status[names(joblist)]
    status <- as.integer(status)
    names(status) <- names(joblist)
  }
  
  checkpointing <- FALSE
  if (is.null(checkpoint.file)) {       # no checkpointing
    if (!is.null(checkpoint))
      stop("for checkpointing to work, ",sQuote("checkpoint.file")," must be set",call.=FALSE)
  } else {                              # checkpointing
    if (!is.character(checkpoint.file))
      stop(sQuote("checkpoint.file")," must be a filename",call.=FALSE)
    if (file.exists(checkpoint.file)) {
      backup.file <- paste(checkpoint.file,"bak-%d",sep=".")
      nbkups <- 1
      while (file.exists(sprintf(backup.file,nbkups))&&(nbkups<=max.backup)) {
        nbkups <- nbkups+1
      }
      if (nbkups<=max.backup)
        backup.file <- sprintf(backup.file,nbkups)
      else
        stop("mpifarm error: ",max.backup," backup files already exist")
      file.copy(from=checkpoint.file,to=backup.file)
      warning("file ",sQuote(checkpoint.file)," exists, backup ",sQuote(backup.file)," created",call.=FALSE)
    }
    if ((is.null(checkpoint))||(checkpoint<0))
      stop("for checkpointing to work, ",sQuote("checkpoint")," must be set to a positive integer",call.=FALSE)
    checkpoint <- as.integer(checkpoint)
    if (checkpoint>0) {
      if (!file.exists(checkpoint.file)) {
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
      }
      checkpointing <- TRUE
    }
  }

  todo <- which(status==WAITING)        # indices of unfinished jobs

  if (ncpus > 1) {                       # RUN IN PARALLEL MODE

    fn <- deparse(substitute(proc))      # deparse the procedure to text
    stop.condn <- deparse(substitute(stop.condition)) # deparse the stop condition

    if (verbose)
      cat("broadcasting ",sQuote("mpi.farm.slave")," function to slaves\n")

    mpi.bcast.Robj2slave(mpi.farm.slave) # broadcast the slave function
    mpi.bcast.cmd(if(!exists('.Random.seed')) runif(1)) # initialize the RNG if necessary

    if (verbose)
      cat("starting ",sQuote("mpi.farm.slave")," processes\n")

    mpi.remote.exec(mpi.farm.slave,fn,common,verbose=verbose,ret=FALSE) # start up the slaves

    nslave <- ncpus-1
    if (nslave > sum(status==WAITING)) {
      warning("mpi.farm warning: more slaves than jobs",call.=FALSE)  
    }

    live <- seq_len(nslave)             # id numbers of live slaves
    available <- live                   # id numbers of available slaves
    
    slaveinfo <- matrix(
                        data=0,
                        nrow=1,
                        ncol=nslave+1,
                        dimnames=list('jobs',c(live,'total'))
                        )
    
    sent <- 0
    rcvd <- 0

    withRestarts(
                 {
                   for (d in live) { # initialize the queue
                     if (length(todo)>0) {      # farm out the work
                       ## pop the next job off the stack and send it out
                       jobid <- todo[1]
                       mpi.send.Robj(joblist[jobid],dest=available[1],tag=3) 
                       sent <- sent+1
                       status[jobid] <- RUNNING
                       todo <- todo[-1]
                       available <- available[-1]
                     }
                   }
                   while (rcvd < sent) {
                     ## wait for someone to finish
                     res <- mpi.recv.Robj(source=mpi.any.source(),tag=mpi.any.tag()) 
                     rcvd <- rcvd+1
                     srctag <- mpi.get.sourcetag()
                     src <- srctag[1]   # who did it?
                     tag <- srctag[2]   # were they succesful?
                     available <- c(available,src)
                     id <- which(names(joblist)==res$id)
                     status[id] <- TMP
                     joblist[[id]] <- res$result
                     if (tag == 33) {                    # success
                       slaveinfo[1,src] <- slaveinfo[1,src]+1
                       slaveinfo[1,nslave+1] <- slaveinfo[1,nslave+1]+1
                       if (info) print(slaveinfo)
                       if (is.list(res$result)) {         # are we all finished with this job?
                         stq <- as.logical(eval(parse(text=stop.condn),envir=res$result))
                         if (is.na(stq))
                           stop(sQuote("stop.condition")," must evaluate to TRUE or FALSE")
                       } else {
                         stq <- TRUE
                       }
                       if (stq) {       # should we stop?
                         status[id] <- FINISHED
                       } else {
                         status[id] <- WAITING
                         todo <- c(todo,id)
                       }
                     } else {           # an error occurred
                       if (info)
                         message('slave ',format(src),' reports: ',res$result)
                       else
                         warning('mpi.farm: slave ',format(src),' reports: ',res$result,call.=FALSE)
                       status[id] <- ERROR
                     }
                     if ((checkpointing)&&((rcvd%%checkpoint)==0)) {
                       if (info) cat(
                                     "writing checkpoint file",
                                     sQuote(checkpoint.file),
                                     "\n#finished =",sum(status==FINISHED),
                                     "#waiting =",sum(status==WAITING),
                                     "#running =",sum(status==RUNNING),
                                     "#error =",sum(status==ERROR),
                                     "\n"
                                     )
                       save(joblist,status,file=checkpoint.file)
                     }
                     if (length(todo)>0) {       # is there more to do?
                       ## pop the next job off the stack and send it out
                       jobid <- todo[1]
                       mpi.send.Robj(joblist[jobid],dest=available[1],tag=3) 
                       sent <- sent+1
                       status[jobid] <- RUNNING
                       todo <- todo[-1]
                       available <- available[-1]
                     }
                   }
                   for (d in live) {    # kill off slaves
                     mpi.send.Robj(0,dest=d,tag=666)
                   }
                 },
                 abort=function(){
                   cat("aborting mpi.farm: please be patient!\n\n")
                   invokeRestart("cleanup")
                 },
                 cleanup=function(){
                   while (rcvd < sent) {
                     res <- mpi.recv.Robj(source=mpi.any.source(),tag=mpi.any.tag()) 
                     rcvd <- rcvd+1
                     srctag <- mpi.get.sourcetag()
                     src <- srctag[1]   # who did it?
                     tag <- srctag[2]   # were they succesful?
                     available <- c(available,src)
                     id <- res$id
                     status[id] <- TMP
                     joblist[[id]] <- res$result
                     if (tag == 33) {                    # success
                       slaveinfo[1,src] <- slaveinfo[1,src]+1
                       slaveinfo[1,nslave+1] <- slaveinfo[1,nslave+1]+1
                       if (info) print(slaveinfo)
                       if (is.list(res$result)) {         # are we all finished with this job?
                         stq <- as.logical(eval(parse(text=stop.condn),envir=res$result))
                         if (is.na(stq))
                           stop(sQuote("stop.condition")," must evaluate to TRUE or FALSE")
                       } else {
                         stq <- TRUE
                       }
                       if (stq) {       # should we stop?
                         status[id] <- FINISHED
                       } else {
                         status[id] <- WAITING
                         todo <- c(todo,id)
                       }
                     } else {           # an error occurred
                       if (info)
                         message('slave ',format(src),' reports: ',res$result)
                       else
                         warning('mpi.farm: slave ',format(src),' reports: ',res$result,call.=FALSE)
                       status[id] <- ERROR
                     }
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
  } else {                 # RUN IN SERIAL MODE

    fn <- substitute(proc)
    stop.condn <- substitute(stop.condition)

    if (!exists('.Random.seed')) runif(1)

    while (length(todo)>0) {
      id <- todo[1]
      todo <- todo[-1]
      res <- try(
                 evalq(eval(fn,envir=joblist[[id]]),envir=common),
                 silent=TRUE
                 )
      if (is.list(res)) {         # are we all finished with this job?
        stq <- as.logical(eval(stop.condn,envir=res))
        if (is.na(stq))
          stop(sQuote("stop.condition")," must evaluate to TRUE or FALSE")
      } else {
        stq <- TRUE
      }
      joblist[[id]] <- res
      if (stq) {                        # should we stop?
        status[id] <- FINISHED
      } else {
        status[id] <- WAITING
        todo <- c(todo,id)
      }
      if (inherits(res,"try-error")) {
        if (info)
          message("mpi.farm (serial) reports: ",res)
        else
          warning("mpi.farm (serial) reports: ",res)
        status[id] <- ERROR
      }
    }
  }
  if (checkpointing) {
    save(joblist,status,file=checkpoint.file)
  }
  joblist
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
