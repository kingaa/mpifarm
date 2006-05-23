require(Rmpi)

pdapply <- function (fun, pars, common=list(), info=T) { # row-by-row data.frame apply (parallel version)
  fn <- deparse(substitute(fun))
  mpi.remote.exec(pdapply.slave,fn,common,ret=F)
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
      print(slaveinfo)
    } else {
      warning(paste('slave',format(src),'reports:',res))
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

pdapply.slave <- function (fn, common=list()) { # slave procedure for pdapply
  fun <- parse(text=fn)
  wrap.fn <- function (x) eval(fun,envir=x)
  go <- TRUE
  attach(common,warn.conflicts=F)
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

plapply <- function (fun, pars, common=list(), info=T) { # parallel lapply
  fn <- deparse(substitute(fun))
  mpi.remote.exec(plapply.slave,fn,common,ret=F)
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
      print(slaveinfo)
    } else {
      warning(paste('slave',format(src),'reports:',res))
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

plapply.slave <- function (fn, common=list()) { # slave procedure for plapply
  fun <- parse(text=fn)
  wrap.fn <- function (x) eval(fun,envir=x)
  go <- TRUE
  attach(common,warn.conflicts=F)
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

sdapply <- function (fun, pars, common=list()) { # row-by-row data.frame apply (serial version)
  fn <- substitute(fun)
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
      warning(paste('sdapply reports:',res))
    }
  }
  detach(common)
  result
}
