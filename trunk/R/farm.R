## serial version
farm <- function (proc, joblist, common=list(),
                  stop.condition = TRUE, info = TRUE) {
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
        message('farm reports: ', res)
      else
        warning('farm reports: ', res)
    }
  }
  detach(common)
  result
}
