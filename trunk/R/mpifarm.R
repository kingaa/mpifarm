## farm out a bunch of jobs
mpi.farm <- function (proc, joblist, common=list(),
                      stop.condition = TRUE, info = TRUE,
                      checkpoint = NULL, checkpoint.file = NULL) {
  if (is.null(checkpoint.file)) {
    if (!is.null(checkpoint))
      stop("for checkpointing to work, ",sQuote("checkpoint.file")," must be set",call.=FALSE)
    checkpointing <- FALSE
  } else {
    if (!is.character(checkpoint.file))
      stop(sQuote("checkpoint.file")," must be a filename",call.=FALSE)
    if (file.exists(checkpoint.file))
      stop("file ",sQuote(checkpoint.file)," exists",call.=FALSE)
    if ((is.null(checkpoint))||(checkpoint<=0))
      stop("for checkpointing to work, ",sQuote("checkpoint")," must be set to a positive integer",call.=FALSE)
    checkpoint <- as.integer(checkpoint)
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
  }
  if (mpi.comm.size() < 2)
    stop("mpi.farm: no slaves running")
  mpi.bcast.Robj2slave(mpi.farm.slave)  # broadcast the slave function
  mpi.bcast.cmd(if(!exists('.Random.seed')) runif(1)) # initialize the RNG if necessary
  fn <- deparse(substitute(proc))      # deparse the procedure to text
  stop.condn <- deparse(substitute(stop.condition)) # deparse the stop condition
  mpi.remote.exec(mpi.farm.slave,fn,common,ret=FALSE) # start up the slaves
  finished <- vector(mode='list',length=0)
  in.progress <- vector(mode='list',length=0)
  if (is.null(names(joblist)))
    names(joblist) <- seq(length=length(joblist))
  else
    names(joblist) <- make.unique(names(joblist))
  nslave <- mpi.comm.size()-1
  if (nslave > length(joblist)) {
    warning("mpi.farm warning: more slaves than jobs, killing unneeded slaves",call.=FALSE)
    for (d in seq(from=length(joblist)+1,to=nslave,by=1)) {
      mpi.send.Robj(0,dest=d,tag=666)   # kill unneeded slaves
    }
    nslave <- length(joblist)
  }
  live <- seq(from=1,to=nslave,by=1)    # numbers of live slaves
  on.exit(
          for (d in live) {
            mpi.send.Robj(0,dest=d,tag=666)
          }
          )
  slaveinfo <- matrix(
                      data=0,
                      nrow=1,
                      ncol=nslave+1,
                      dimnames=list('jobs',c(live,'total'))
                      )
  sent <- 0
  rcvd <- 0
  for (d in live) {                     # initialize the queue
    if (length(joblist)>0) {            # farm out the work
      sent <- sent+1
      mpi.send.Robj(joblist[1],dest=d,tag=3) # pop the next job off the stack and send it out
      in.progress <- append(in.progress,joblist[1])
      joblist[[1]] <- NULL
    }
  }
  while (rcvd < sent) {
    res <- mpi.recv.Robj(source=mpi.any.source(),tag=mpi.any.tag()) # wait for someone to finish
    srctag <- mpi.get.sourcetag()
    src <- srctag[1]                    # who did it?
    tag <- srctag[2]                    # were they succesful?
    rcvd <- rcvd+1
    if (tag == 33) {                    # success
      slaveinfo[1,src] <- slaveinfo[1,src]+1
      slaveinfo[1,nslave+1] <- slaveinfo[1,nslave+1]+1
      if (info) print(slaveinfo)
      if (is.list(res[[1]])) {         # are we all finished with this job?
        stq <- as.logical(eval(parse(text=stop.condn),envir=res[[1]]))
      } else {
        stq <- TRUE
      }
      identifier <- names(res)
      in.progress[[identifier]] <- NULL
      if (is.na(stq))
        stop("'stop.condition' must evaluate to TRUE or FALSE")
      if (stq) {                        # should we stop?
        finished <- append(finished,res)
      } else {
        joblist <- append(joblist,res)
      }
    } else {                            # an error occurred
      if (info)
        message('slave ',format(src),' reports: ',res[[1]])
      else
        warning('mpi.farm: slave ',format(src),' reports: ',res[[1]],call.=FALSE)
      finished <- append(finished,res)
    }
    if ((checkpointing)&&((rcvd%%checkpoint)==0)) {
      unfinished <- append(joblist,in.progress)
      if (info) cat(
                    "writing checkpoint file",
                    sQuote(checkpoint.file),
                    "\n#finished =",length(finished),
                    "#unfinished =",length(unfinished),
                    "\n"
                    )
      save(unfinished,finished,file=checkpoint.file)
    }
    if (length(joblist)>0) {       # is there more to do?
      sent <- sent+1
      mpi.send.Robj(joblist[1],dest=src,tag=3) # pop the next job off the stack and send it out
      in.progress <- append(in.progress,joblist[1])
      joblist[[1]] <- NULL
    } else {                            # if not, kill the slave
      mpi.send.Robj(0,dest=src,tag=666)
      live <- live[live!=src]
    }
  }
  finished[order(as.numeric(names(finished)))]
}

mpi.farm.slave <- function (fn, common=list()) { # slave procedure for mpi.farm
  proc <- parse(text=fn)
  go <- TRUE
  attach(common,warn.conflicts=FALSE)
  while (go) {
    rcv <- mpi.recv.Robj(source=0,tag=mpi.any.tag())
    identifier <- names(rcv)
    srctag <- mpi.get.sourcetag()
    if (srctag[2] == 3) {               # we have a job to do
      result <- try(
                    eval(proc,envir=rcv[[1]]),
                    silent=FALSE
                    )
      if (inherits(result,'try-error')) {
        tag <- 66                       # error
      } else {
        tag <- 33                       # success
      }
      snd <- list(result)
      names(snd) <- identifier
      mpi.send.Robj(snd,dest=0,tag=tag)
    } else {                         # no job to do, our time has come
      go <- FALSE                       # terminate
    }
  }
  detach(common)
}
