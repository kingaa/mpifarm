mpi.farmer <- function (..., jobs, common, main, post, chunk = 1, blocking = TRUE,
                        checkpoint.file = NULL, checkpoint = 0, max.backup = 20,
                        stop.condition = TRUE, info = TRUE,
                        verbose = getOption("verbose")) {

  extras <- list(...)  # environment for evaluating jobs, common, post

  main <- substitute(main)
  jobs <- substitute(jobs)
  common <- substitute(common)
  if (missing(post)) post <- NULL
  else post <- substitute(post)
  stop.condition <- substitute(stop.condition)
  
  checkpoint <- as.integer(checkpoint)
  checkpointing <- !is.null(checkpoint.file)
  if (checkpointing && (checkpoint<1))
    stop("for checkpointing to work, ",sQuote("checkpoint")," must be a positive integer")
  if (checkpointing && file.exists(checkpoint.file)) {
    cat("loading checkpoint file",sQuote(checkpoint.file),"\n")
    cat(sQuote("jobs"),"and",sQuote("common"),"will not be evaluated\n")
    olist <- try(load(checkpoint.file))
    if (inherits(olist,"try-error"))
      stop("checkpoint load error")
    if (!all(c("joblist","common","status")%in%olist))
      stop("inappropriate checkpoint file ",sQuote(checkpoint.file))
  } else {
    cat("setting up\n")
    joblist <- try(eval(jobs,envir=extras),silent=FALSE)
    if (!is.list(joblist))
      stop("when evaluated, ",sQuote("jobs")," should return a list")
    common <- try(eval(common,envir=extras),silent=FALSE)
    if (!is.list(common))
      stop("when evaluated, ",sQuote("common")," should return a list")
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
                                      max.backup=max.backup,
                                      stop.condition=.(stop.condition),
                                      chunk=chunk,
                                      info=info,
                                      verbose=verbose
                                      )
                             )
                      ),
                 silent=FALSE
                 )
  if (inherits(results,"try-error"))
    stop("error in main computation")
  else
    cat("main computation finished, post-processing\n")

  if (!is.null(post)) {
    results <- try(eval(post,envir=extras),silent=FALSE)
    if (inherits(results,"try-error"))
      stop("post-processing error")
  }

  results
}
