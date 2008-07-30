## farm out a bunch of jobs
mpi.farm <- function (proc, joblist, common=list(),
                      stop.condition = TRUE, info = TRUE) {
  if (mpi.comm.size() < 2)
    stop("mpi.farm: no slaves running")
  mpi.bcast.Robj2slave(mpi.farm.slave)  # broadcast the slave function
  mpi.bcast.cmd(if(!exists('.Random.seed')) runif(1)) # initialize the RNG if necessary
  fn <- deparse(substitute(proc))      # deparse the procedure to text
  stop.condn <- deparse(substitute(stop.condition)) # deparse the stop condition
  mpi.remote.exec(mpi.farm.slave,fn,common,ret=FALSE) # start up the slaves
  result <- vector(mode='list',length=0)
  nslave <- mpi.comm.size()-1
  if (nslave > length(joblist)) {
    warning("more slaves than jobs, killing unneeded slaves")
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
                      0,
                      nrow=1,
                      ncol=nslave+1,
                      dimnames=list('jobs',c(live,'total'))
                      )
  sent <- 0
  rcvd <- 0
  for (d in live) {                 # initialize the queue
    if (sent < length(joblist)) {     # farm out the work
      sent <- sent+1
      mpi.send.Robj(joblist[[sent]],dest=d,tag=3)
    }
  }
  while (rcvd < length(joblist)) {
    res <- mpi.recv.Robj(source=mpi.any.source(),tag=mpi.any.tag()) # wait for someone to finish
    srctag <- mpi.get.sourcetag()
    src <- srctag[1]                    # who did it?
    tag <- srctag[2]                    # were they succesful?
    rcvd <- rcvd+1
    if (tag == 33) {                    # success
      slaveinfo[1,src] <- slaveinfo[1,src]+1
      slaveinfo[1,nslave+1] <- slaveinfo[1,nslave+1]+1
      if (info) print(slaveinfo)
      if (is.list(res)) {
        stq <- as.logical(eval(parse(text=stop.condn),envir=res))
      } else {
        stq <- TRUE
      }
      if (is.na(stq))
        stop("'stop.condition' must evaluate to TRUE or FALSE")
      if (stq) { # should we stop?
        result <- append(result,list(res))
      } else {
        joblist <- append(joblist,list(res))
      }
    } else {                            # an error occurred
      if (info)
        message('slave ',format(src),' reports: ',res)
      else
        warning('slave ',format(src),' reports: ',res)
    }
    if (sent < length(joblist)) {       # is there more to do?
      sent <- sent+1
      mpi.send.Robj(joblist[[sent]],dest=src,tag=3) # send out another job
    } else {
      mpi.send.Robj(0,dest=src,tag=666) # else kill the slave
      live <- live[live!=src]
    }
  }
  result
}

mpi.farm.slave <- function (fn, common=list()) { # slave procedure for mpi.farm
  proc <- parse(text=fn)
  go <- TRUE
  attach(common,warn.conflicts=FALSE)
  while (go) {
    pars <- mpi.recv.Robj(source=0,tag=mpi.any.tag())
    srctag <- mpi.get.sourcetag()
    if (srctag[2] == 3) {               # we have a job to do
      result <- try(
                    eval(proc,envir=pars),
                    silent=T
                    )
      if (inherits(result,'try-error')) {
        tag <- 66                       # error
      } else {
        tag <- 33                       # success
      }
      mpi.send.Robj(result,dest=0,tag=tag)
    } else {                         # no job to do, our time has come
      go <- FALSE                       # terminate
    }
  }
  detach(common)
}
