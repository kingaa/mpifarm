## farm out a bunch of jobs
mpi.farm <- function (proc, joblist, common=list(), info=TRUE) {
  if (mpi.comm.size() < 2)
    stop("mpi.farm: no slaves running")
  mpi.bcast.Robj2slave(mpi.farm.slave)
  mpi.bcast.cmd(if(!exists('.Random.seed')) runif(1))
  fn <- deparse(substitute(proc))
  mpi.remote.exec(mpi.farm.slave,fn,common,ret=FALSE)
  result <- vector('list',length(joblist))
  sent <- 0
  rcvd <- 0
  nslave <- mpi.comm.size() - 1
  slaveinfo <- matrix(0,1,nslave+1,dimnames=list('jobs',c(1:nslave,'total')))
  for (d in 1:nslave) {  # initialize the queue
    sent <- sent+1
    if (sent <= length(joblist)) {
      mpi.send.Robj(joblist[[sent]],dest=d,tag=3)
    } else {
      mpi.send.Robj(0,dest=d,tag=666)
    }
  }
  while (rcvd < length(joblist)) {
    res <- mpi.recv.Robj(source=mpi.any.source(),tag=mpi.any.tag())
    srctag <- mpi.get.sourcetag()
    src <- mpi.get.sourcetag()[1]
    tag <- mpi.get.sourcetag()[2]
    rcvd <- rcvd+1
    if (tag == 33) {
      result[[rcvd]] <- res
      slaveinfo[1,src] <- slaveinfo[1,src] + 1
      slaveinfo[1,nslave+1] <- slaveinfo[1,nslave+1] + 1
      if (info)
        print(slaveinfo)
    } else {
      if (info)
        message('slave ',format(src),' reports: ',res)
      else
        warning('slave ',format(src),' reports: ',res)
    }
    if (sent < length(joblist)) {
      sent <- sent+1
      mpi.send.Robj(joblist[[sent]],dest=src,tag=3)
    } else {
      mpi.send.Robj(0,dest=src,tag=666)
    }
  }
  result
}

mpi.farm.slave <- function (fn, common=list()) { # slave procedure for mpi.farm
  fun <- parse(text=fn)
  wrap.fn <- function (x) eval(fun,envir=x)
  go <- TRUE
  attach(common,warn.conflicts=FALSE)
  while (go) {
    pars <- mpi.recv.Robj(source=0,tag=mpi.any.tag())
    if (mpi.get.sourcetag()[2] == 3) {
      result <- try(
                    wrap.fn(pars),
                    silent=T
                    )
      if (inherits(result,'try-error')) {
        tag <- 66
      } else {
        tag <- 33
      }
      mpi.send.Robj(result,dest=0,tag=tag)
    } else {
      go <- FALSE                       # terminate
    }
  }
  detach(common)
}

## serial version
farm <- function (proc, joblist, common=list(), info = TRUE) { 
  if (!exists('.Random.seed')) runif(1)
  fun <- substitute(proc)
  result <- vector('list',length(joblist))
  attach(common)
  for (j in 1:length(joblist)) {
    res <- try(
               eval(fun,envir=joblist[[j]]),
               silent=T
               )
    if (!(inherits(res,'try-error'))) {
      result[[j]] <- res
    } else {
      if (info)
        message('sdapply reports: ', res)
      else
        warning('sdapply reports: ', res)
    }
  }
  detach(common)
  result
}
