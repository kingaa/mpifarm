mpi.farmer <- function (pre, main, post, common,
                        checkpoint.file = NULL, checkpoint = 0,
                        stop.condition=TRUE, info = TRUE,
                        ...) {
  pre <- substitute(pre)
  main <- substitute(main)
  post <- substitute(post)

  extras <- list(...)

  checkpoint <- as.integer(checkpoint)
  checkpointing <- ((!is.null(checkpoint.file)) && (checkpoint > 0))
  if (checkpointing && file.exists(checkpoint.file)) {
    cat("loading checkpoint file",sQuote(checkpoint.file),"\n")
    olist <- try(load(checkpoint.file))
    if (inherits(olist,"try-error"))
      stop("checkpoint load error")
  } else {
    cat("setting up\n")
    joblist <- try(eval(pre,envir=extras),silent=FALSE)
    if (!is.list(joblist))
      stop("when evaluated, ",sQuote("pre")," should return a list")
    status <- rep(0L,length(joblist))
  }

  cat("running main computation\n")
  cat(sum(status==0),"unfinished jobs remaining\n")
  
  results <- try(
                 eval(
                      bquote(
                             mpi.farm(
                                      proc=.(main),
                                      common=common,
                                      joblist=joblist,
                                      status=status,
                                      checkpoint=checkpoint,
                                      checkpoint.file=checkpoint.file,
                                      stop.condition=stop.condition,
                                      info=info
                                      )
                             )
                      ),
                 silent=FALSE
                 )
  if (inherits(results,"try-error"))
    stop("error in main computation")
  else
    cat("main computation finished, post-processing\n")
  
  res <- try(eval(post,envir=extras),silent=FALSE)
  if (inherits(res,"try-error"))
    stop("post-processing error")
  
  res
}
