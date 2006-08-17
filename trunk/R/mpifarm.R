pdapply.slave <- function (fn, common=list()) { # slave procedure for pdapply
  fun <- parse(text=fn)
  wrap.fn <- function (x) eval(fun,envir=x)
  go <- TRUE
  attach(common,warn.conflicts=FALSE)
  while (go) {
    pars <- mpi.recv.Robj(source=0,tag=mpi.any.tag())
    if (mpi.get.sourcetag()[2] == 3) {
      result <- try(
                    cbind(before=pars,after=wrap.fn(pars)),
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

## row-by-row data.frame apply (parallel version)
pdapply <- function (job, pars, common = list(), info = TRUE) {
  if (mpi.comm.size() < 2)
    stop("pdapply: no slaves running")
  mpi.bcast.Robj2slave(pdapply.slave)
  mpi.bcast.cmd(if(!exists('.Random.seed')) runif(1))
  fn <- deparse(substitute(job))
  mpi.remote.exec(pdapply.slave,fn,common,ret=FALSE)
  result <- data.frame()
  sent <- 0
  rcvd <- 0
  nslave <- mpi.comm.size() - 1
  slaveinfo <- matrix(0,1,nslave+1,dimnames=list('jobs',c(1:nslave,'total')))
  for (d in 1:nslave) {  # initialize the queue
    sent <- sent+1
    if (sent <= nrow(pars)) {
      mpi.send.Robj(pars[sent,],dest=d,tag=3)
    } else {
      mpi.send.Robj(0,dest=d,tag=666)
    }
  }
  while (rcvd < nrow(pars)) {
    res <- mpi.recv.Robj(source=mpi.any.source(),tag=mpi.any.tag())
    srctag <- mpi.get.sourcetag()
    src <- mpi.get.sourcetag()[1]
    tag <- mpi.get.sourcetag()[2]
    rcvd <- rcvd+1
    if (tag == 33) {
      result <- rbind(result,res)
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
    if (sent < nrow(pars)) {
      sent <- sent+1
      mpi.send.Robj(pars[sent,],dest=src,tag=3)
    } else {
      mpi.send.Robj(0,dest=src,tag=666)
    }
  }
  result
}

plapply.slave <- function (fn, common=list()) { # slave procedure for plapply
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

plapply <- function (job, pars, common=list(), info=TRUE) { # parallel lapply
  if (mpi.comm.size() < 2)
    stop("plapply: no slaves running")
  mpi.bcast.Robj2slave(plapply.slave)
  mpi.bcast.cmd(if(!exists('.Random.seed')) runif(1))
  fn <- deparse(substitute(job))
  mpi.remote.exec(plapply.slave,fn,common,ret=FALSE)
  result <- vector('list',length(pars))
  sent <- 0
  rcvd <- 0
  nslave <- mpi.comm.size() - 1
  slaveinfo <- matrix(0,1,nslave+1,dimnames=list('jobs',c(1:nslave,'total')))
  for (d in 1:nslave) {  # initialize the queue
    sent <- sent+1
    if (sent <= length(pars)) {
      mpi.send.Robj(pars[[sent]],dest=d,tag=3)
    } else {
      mpi.send.Robj(0,dest=d,tag=666)
    }
  }
  while (rcvd < length(pars)) {
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
    if (sent < length(pars)) {
      sent <- sent+1
      mpi.send.Robj(pars[[sent]],dest=src,tag=3)
    } else {
      mpi.send.Robj(0,dest=src,tag=666)
    }
  }
  result
}

## row-by-row data.frame apply (serial version)
sdapply <- function (job, pars, common=list(), info = TRUE) { 
  fn <- substitute(job)
  result <- data.frame()
  wrap.fn <- function (x) eval(fn,envir=x)
  attach(common)
  for (k in 1:nrow(pars)) {
    res <- try(
               cbind(before=pars[k,],after=wrap.fn(pars[k,])),
               silent=T
               )
    if (!(inherits(res,'try-error'))) {
      result <- rbind(result,res)
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
