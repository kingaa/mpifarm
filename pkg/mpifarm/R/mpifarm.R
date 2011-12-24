### farm out a bunch of jobs in parallel if possible, run serially if not
mpi.farm <- function (proc, joblist, common=list(), status = NULL, chunk = 1,
                      stop.condition = TRUE, info = TRUE,
                      checkpoint = 0, checkpoint.file = NULL,
                      max.backup = 20, sleep = 0.01, blocking = FALSE,
                      verbose = getOption("verbose")) {

  ncpus <- try(mpi.comm.size(),silent=TRUE)
  if (inherits(ncpus,"try-error"))
    ncpus <- 1

  chunk <- as.integer(chunk)
  if ((chunk<1)||(length(chunk)>1))
    stop(sQuote("chunk")," must be a single positive integer")
  chnk <- seq_len(chunk)

  max.backup <- as.integer(max.backup)
  if (max.backup < 1) stop(sQuote("max.backup")," must be a positive integer")

  stop.condn <- substitute(stop.condition) # the stop condition
  
  if (!is.list(joblist))
    stop(sQuote("joblist")," must be a list")
  if (is.null(names(joblist)))
    names(joblist) <- as.character(seq_along(joblist))
  else
    names(joblist) <- make.unique(names(joblist))

  ## 'status' is an integer holding the status codes for 
  ## each individual job.
  ## status codes:
  ##  0 = waiting incomplete,
  ##  1 = finished OK,
  ## -1 = finished ERROR,
  UNFINISHED <- 0L
  FINISHED <- 1L
  ERROR <- -1L

  if (is.null(status)) {
    status <- rep(UNFINISHED,length(joblist))
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
  checkpoint <- as.integer(checkpoint)
  if (checkpoint>0) {
    if (is.null(checkpoint.file)) {
      stop("for checkpointing to work, ",sQuote("checkpoint.file")," must be set",call.=FALSE)
    } else {
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
      } else {
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

  todo <- which(status==UNFINISHED)     # indices of unfinished jobs

  if (ncpus > 1) {                      # RUN IN PARALLEL MODE

    fn <- deparse(substitute(proc))    # deparse the procedure to text

    mpi.anysource <- mpi.any.source()
    mpi.anytag <- mpi.any.tag()

    if (verbose)
      cat("broadcasting ",sQuote("mpi.farm.slave")," function to slaves\n")

    mpi.bcast.Robj2slave(mpi.farm.slave) # broadcast the slave function
    mpi.bcast.cmd(if(!exists('.Random.seed')) runif(1)) # initialize the RNG if necessary

    if (verbose)
      cat("starting ",sQuote("mpi.farm.slave")," processes\n")

    mpi.remote.exec(mpi.farm.slave,fn,common,verbose=verbose,ret=FALSE) # start up the slaves

    nslave <- ncpus-1
    if (nslave > sum(status==UNFINISHED)) {
      warning("mpi.farm warning: more slaves than jobs",call.=FALSE)  
    }

    slaves <- seq_len(nslave)         # id numbers of live slaves
    idle <- slaves                    # id numbers of idle slaves
    
    ## to hold progress information
    if (info) {
      progress <- matrix(
                         data=0,
                         nrow=1,
                         ncol=nslave+1,
                         dimnames=list('jobs',c(slaves,'total'))
                         )
    }

    sent <- 0
    rcvd <- 0
    
    withRestarts(
                 {
                   if (verbose)
                     cat("sending out first batch of jobs\n")
                   ## initialize the queue
                   for (i in slaves) {
                     ## pop the next chunk off the stack and send it out
                     if (length(todo)>0) {
                       if (length(todo)>chunk) {
                         jobid <- todo[chnk]
                         todo <- todo[-chnk]
                       } else {
                         jobid <- todo
                         todo <- integer(0)
                       }
                       mpi.isend.Robj(joblist[jobid],dest=idle[1],tag=sent+1)
                       sent <- sent+1
                       idle <- idle[-1]
                     }
                   }
                   if (verbose)
                     cat("beginning main loop\n")

                   if (blocking) {    # USE BLOCKING MPI CALLS

                     while (rcvd < sent) {
                       ## wait for someone to finish
                       res <- mpi.recv.Robj(source=mpi.anysource,tag=mpi.anytag) 
                       rcvd <- rcvd+1
                       srctag <- mpi.get.sourcetag()
                       src <- srctag[1]
                       idle <- c(idle,src)
                       if (verbose)
                         cat("slave ",src," has sent results\n")
                       for (id in names(res)) {
                         joblist[[id]] <- res[[id]]
                         if (inherits(res[[id]],"try-error")) { # error
                           status[id] <- ERROR
                           if (info)
                             message('slave ',format(src),' reports: ',res[[id]])
                           else
                             warning('mpi.farm: slave ',format(src),' reports: ',res[[id]],call.=FALSE)
                         } else {                    # success
                           if (is.list(res[[id]])) { # evaluate the stop condition
                             stq <- eval(stop.condn,envir=res[[id]],enclos=NULL)
                             if (!is.logical(stq)||is.na(stq))
                               stop(sQuote("stop.condition")," must evaluate to TRUE or FALSE")
                           } else {
                             stq <- TRUE
                           }
                           if (stq) {       # should we stop?
                             status[id] <- FINISHED
                           } else {
                             status[id] <- UNFINISHED
                             todo <- c(todo,which(names(joblist)==id))
                           }
                         }
                       }
                       if (length(todo)>0) {       # is there more to do?
                         ## pop the next job off the stack and send it out
                         if (length(todo)>chunk) {
                           jobid <- todo[chnk]
                           todo <- todo[-chnk]
                         } else {
                           jobid <- todo
                           todo <- integer(0)
                         }
                         mpi.send.Robj(joblist[jobid],dest=idle[1],tag=sent+1) 
                         sent <- sent+1
                         if (verbose)
                           cat("sending next chunk to slave ",idle[1],"\n")
                         idle <- idle[-1]
                       }
                       if (info) {
                         progress[1,src] <- progress[1,src]+1
                         progress[1,nslave+1] <- progress[1,nslave+1]+1
                         print(progress)
                       }
                       if ((checkpointing)&&((rcvd%%checkpoint)==0)) {
                         if (info) cat(
                                       "writing checkpoint file",
                                       sQuote(checkpoint.file),
                                       "\n#finished =",sum(status==FINISHED),
                                       "#waiting =",sum(status==UNFINISHED),
                                       "#error =",sum(status==ERROR),
                                       "\n"
                                       )
                         save(joblist,status,common,file=checkpoint.file)
                       }
                     }
                     
                   } else {           # USE NONBLOCKING MPI CALLS

                     i <- 1
                     while (rcvd<sent) {
                       ## check each busy slave in turn to see if it has finished
                       repeat {
                         i <- (i%%nslave)+1
                         if (mpi.iprobe(source=i,tag=mpi.anytag)) break
                       }
                       ## slave i has sent results
                       srctag <- mpi.get.sourcetag()
                       src <- srctag[1]
                       tag <- srctag[2]
                       if (verbose)
                         cat("slave ",src," has sent results\n")
                       ## is there more to do and someone to do it?
                       ## if so, pop the next job off the stack and send it out
                       if ((length(idle)>0)&&(length(todo)>0)) {
                         if (length(todo)>chunk) {
                           jobid <- todo[chnk]
                           todo <- todo[-chnk]
                         } else {
                           jobid <- todo
                           todo <- integer(0)
                         }
                         mpi.isend.Robj(joblist[jobid],dest=idle[1],tag=sent+1) 
                         sent <- sent+1
                         if (verbose)
                           cat("sending next chunk to slave ",idle[1],"\n")
                         idle <- idle[-1]
                       }
                       ## retrieve the results
                       res <- mpi.recv.Robj(source=src,tag=tag)
                       rcvd <- rcvd+1
                       idle <- c(idle,src)
                       ## evaluate and package the results
                       for (id in names(res)) {
                         joblist[[id]] <- res[[id]]
                         if (inherits(res[[id]],"try-error")) { # error
                           status[id] <- ERROR
                           if (info)
                             message('slave ',format(src),' reports: ',res[[id]])
                           else
                             warning('mpi.farm: slave ',format(src),' reports: ',res[[id]],call.=FALSE)
                         } else {                    # success
                           if (is.list(res[[id]])) { # evaluate the stop condition
                             stq <- eval(stop.condn,envir=res[[id]],enclos=NULL)
                             if (!is.logical(stq)||is.na(stq))
                               stop(sQuote("stop.condition")," must evaluate to TRUE or FALSE")
                           } else {
                             stq <- TRUE
                           }
                           if (stq) {       # should we stop?
                             status[id] <- FINISHED
                           } else {
                             status[id] <- UNFINISHED
                             todo <- c(todo,which(names(joblist)==id))
                           }
                         }
                       }
                       if (info) {
                         progress[1,src] <- progress[1,src]+1
                         progress[1,nslave+1] <- progress[1,nslave+1]+1
                         print(progress)
                       }
                       if ((checkpointing)&&((rcvd%%checkpoint)==0)) {
                         if (info) cat(
                                       "writing checkpoint file",
                                       sQuote(checkpoint.file),
                                       "\n#finished =",sum(status==FINISHED),
                                       "#waiting =",sum(status==UNFINISHED),
                                       "#error =",sum(status==ERROR),
                                       "\n"
                                       )
                         save(joblist,status,common,file=checkpoint.file)
                       }
                       ## is there more to do?
                       ## if so, pop the next job off the stack and send it out
                       if (length(todo)>0) {
                         if (length(todo)>chunk) {
                           jobid <- todo[chnk]
                           todo <- todo[-chnk]
                         } else {
                           jobid <- todo
                           todo <- integer(0)
                         }
                         mpi.isend.Robj(joblist[jobid],dest=idle[1],tag=sent+1) 
                         sent <- sent+1
                         if (verbose)
                           cat("sending next chunk to slave ",idle[1],"\n")
                         idle <- idle[-1]
                       }
                       Sys.sleep(sleep)
                     }
                   }
                   if (verbose)
                     cat("killing off all farm slaves\n")
                   for (i in slaves) {  # kill off slaves
                     mpi.isend.Robj(0,dest=i,tag=666)
                   }
                 },
                 abort=function(){
                   cat("aborting mpi.farm: please be patient!\n\n")
                   invokeRestart("cleanup")
                 },
                 cleanup=function(){
                   while (rcvd < sent) {
                     ## wait for someone to finish
                     res <- mpi.recv.Robj(source=mpi.anysource,tag=mpi.anytag) 
                     rcvd <- rcvd+1
                     srctag <- mpi.get.sourcetag()
                     src <- srctag[1]
                     idle <- c(idle,src)
                     for (id in names(res)) {
                       joblist[[id]] <- res[[id]]
                       if (inherits(res[[id]],"try-error")) { # error
                         status[id] <- ERROR
                         if (info)
                           message('slave ',format(src),' reports: ',res[[id]])
                         else
                           warning('mpi.farm: slave ',format(src),' reports: ',res[[id]],call.=FALSE)
                       } else {                    # success
                         if (is.list(res[[id]])) { # evaluate the stop condition
                           stq <- eval(stop.condn,envir=res[[id]],enclos=NULL)
                           if (!is.logical(stq)||is.na(stq))
                             stop(sQuote("stop.condition")," must evaluate to TRUE or FALSE")
                         } else {
                           stq <- TRUE
                         }
                         if (stq) {       # should we stop?
                           status[id] <- FINISHED
                         } else {
                           status[id] <- UNFINISHED
                           todo <- c(todo,which(names(joblist)==id))
                         }
                       }
                     }
                     if (info) {
                       progress[1,src] <- progress[1,src]+1
                       progress[1,nslave+1] <- progress[1,nslave+1]+1
                       print(progress)
                     }
                     if (verbose)
                       cat("killing slave ",src,"\n")
                     mpi.isend.Robj(0,dest=src,tag=666)
                     if ((checkpointing)&&((rcvd%%checkpoint)==0)) {
                       if (info) cat(
                                     "writing checkpoint file",
                                     sQuote(checkpoint.file),
                                     "\n#finished =",sum(status==FINISHED),
                                     "#waiting =",sum(status==UNFINISHED),
                                     "#error =",sum(status==ERROR),
                                     "\n"
                                     )
                       save(joblist,status,common,file=checkpoint.file)
                     }
                   }
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

    if (chunk > 1)
      warning("in serial mode, ",sQuote("chunk")," is ignored")

    fn <- substitute(proc)

    if (!exists('.Random.seed')) runif(1)

    count <- 0
    while (length(todo)>0) {
      id <- todo[1]
      todo <- todo[-1]
      res <- try(
                 evalq(eval(fn,envir=joblist[[id]]),envir=common),
                 silent=TRUE
                 )
      if (is.list(res)) {         # are we all finished with this job?
        stq <- eval(stop.condn,envir=res,enclos=NULL)
        if (!is.logical(stq)||is.na(stq))
          stop(sQuote("stop.condition")," must evaluate to TRUE or FALSE")
      } else {
        stq <- TRUE
      }
      joblist[[id]] <- res
      if (stq) {                        # should we stop?
        status[id] <- FINISHED
      } else {
        status[id] <- UNFINISHED
        todo <- c(todo,id)
      }
      if (inherits(res,"try-error")) {
        if (info)
          message("mpi.farm (serial) reports: ",res)
        else
          warning("mpi.farm (serial) reports: ",res)
        status[id] <- ERROR
      }
      count <- count+1
      if ((checkpointing)&&((count%%checkpoint)==0)) {
        if (info) cat(
                      "writing checkpoint file",
                      sQuote(checkpoint.file),
                      "\n#finished =",sum(status==FINISHED),
                      "#waiting =",sum(status==UNFINISHED),
                      "#error =",sum(status==ERROR),
                      "\n"
                      )
        save(joblist,status,common,file=checkpoint.file)
      }
    }
  }
  if (checkpointing) {
    save(joblist,status,common,file=checkpoint.file)
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
    srctag <- mpi.get.sourcetag()
    if (is.list(rcv)) {                 # we have a job to do
      if (verbose)
        cat("slave",me,"getting to work on a chunk of size",length(rcv),"\n")
      snd <- vector(mode="list",length=length(rcv))
      names(snd) <- names(rcv)
      for (j in seq_along(rcv)) {
        result <- try(
                      evalq(eval(proc,envir=rcv[[j]]),envir=common),
                      silent=FALSE
                      )
        snd[[j]] <- result
      }
      if (verbose)
        cat("slave",me,"sending results\n")
      mpi.send.Robj(snd,dest=0,tag=srctag[2])
    } else {                         # no job to do, our time has come
      if (verbose)
        cat("slave",me,"terminating\n")
      go <- FALSE                       # terminate
    }
  }
}
