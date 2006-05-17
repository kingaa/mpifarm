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
