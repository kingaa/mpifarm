## for running multi-start optimization

multistart.optim.farm <- function (fn, params, est,
                                   n = integer(0), gran = 20,
                                   jobname = NULL,
                                   scratchdir = getwd(),
                                   checkpoint = mpi.universe.size(),
                                   info = TRUE,
                                   method = c("Nelder-Mead","subplex","BFGS","L-BFGS-B"),
                                   control = list(),
                                   ...) {
  
  if (is.null(jobname))
    stop("you must supply a ",sQuote("jobname"))

  id <- paste(basename(getwd()),jobname,sep='_') # an identifier for the files to be saved
  checkpointfile <- file.path(scratchdir,paste(id,".rda",sep="")) # binary file for checkpoints

  if (!all(est%in%colnames(params)))
    stop("all the entries of ",sQuote("est")," must be names of columns in ",sQuote("params"))
  fixed <- colnames(params)[!(colnames(params)%in%est)]

  userdata <- list(...)
  
  fn.names <- setdiff(names(formals(fn)),"...")
  ind <- which(!(fn.names%in%c(colnames(params),names(userdata))))
  if (length(ind)>0)
    stop(sQuote("fn")," argument(s) ",paste(sapply(fn.names[ind],sQuote),collapse=",")," not supplied")

  n <- as.integer(n)
  gran <- as.integer(gran)
  n1 <- nrow(params)

  method <- match.arg(method)

  if (length(gran)==1)
    gran <- c(gran,rep(1,length(n)))
    
  if (length(gran)!=(length(n)+1))
    stop(
         sQuote("gran"),
         " must be either a single integer or a vector of integers of length one greater than that of ",
         sQuote("n")
         )
  if (any(gran<1))
    stop(sQuote("gran")," must be a positive integer")
  if (any(gran<1)||any(n<1)||any(diff(n)>0))
    stop(sQuote("n")," must be a decreasing sequence of positive integers")
  
  joblist <- vector(mode='list',length=ceiling(n1/gran[1]))
  st <- 1
  ed <- gran[1]
  k <- 1
  while (st <= n1) {
    joblist[[k]] <- list(params=params[st:ed,,drop=FALSE])
    st <- ed+1
    ed <- min(ed+gran[1],n1)
    k <- k+1
  }

  res <- mpi.farm(
                  {
                    vals <- numeric(nrow(params))
                    errs <- integer(nrow(params))
                    errmsg <- list()
                    nerr <- 0
                    obj.wrapper.fn <- function (x, obj.fn, userdata) {
                      do.call(obj.fn,c(as.list(x),userdata))
                    }
                    for (k in 1:nrow(params)) {
                      val <- try(
                                 obj.wrapper.fn(
                                                x=unlist(params[k,,drop=FALSE]),
                                                obj.fn=obj.fn,
                                                userdata=userdata
                                                ),
                                 silent=FALSE
                                 )
                      if (inherits(val,"try-error")) {
                        vals[k] <- NA
                        errs[k] <- nerr
                        errmsg <- append(errmsg,as.character(val))
                        nerr <- nerr+1
                      } else {
                        vals[k] <- val
                        errs[k] <- NA
                      }
                    }
                    list(
                         vals=vals,
                         params=params,
                         errs=errs,
                         errmsg=errmsg
                         )
                  },
                  joblist,
                  common=list(
                    obj.fn=fn,
                    userdata=userdata
                    ),
                  info=info
                  )

  erridx <- sapply(res,inherits,"try-error")
  nerr <- sum(erridx)
  if (nerr>0) {
    cat("at level 1: ",nerr," errors out of ",n1,"\n",sep="")
  }
  if (nerr>=n1)
    stop("all parameters resulted in error at level 1")
  
  params <- matrix(NA,nrow=n1-nerr,ncol=ncol(params),dimnames=list(NULL,colnames(params)))
  vals <- numeric(n1-nerr)
  k <- 1
  for (i in seq(length=length(res))) {
    for (j in seq(length=length(res[[i]]$val))) {
      vals[k] <- res[[i]]$vals[j]
      params[k,] <- unlist(res[[i]]$params[j,,drop=FALSE])
      k <- k+1
    }
  }

  for (lev in seq(length=length(n))) {
    
    best <- do.call(
                    c,
                    as.list(
                            tapply(
                                   seq(length=nrow(params)),
                                   lapply(fixed,function(i)params[,i]),
                                   function (k) {
                                     k[head(order(vals[k]),n[lev])]
                                   }
                                   )
                            )
                    )
    params <- params[best,,drop=FALSE]

    n1 <- nrow(params)
    joblist <- vector(mode='list',length=ceiling(n1/gran[lev+1]))
    st <- 1
    ed <- gran[lev+1]
    k <- 1
    while (st <= n1) {
      joblist[[k]] <- list(params=params[st:ed,,drop=FALSE])
      st <- ed+1
      ed <- min(ed+gran[lev+1],n1)
      k <- k+1
    }

    res <- mpi.farm(
                    {
                      vals <- numeric(nrow(params))
                      errs <- integer(nrow(params))
                      errmsg <- list()
                      nerr <- 0
                      obj.wrapper.fn <- function (x, fixed, obj.fn, userdata) {
                        do.call(obj.fn,c(as.list(x),as.list(fixed),userdata))
                      }
                      for (k in 1:nrow(params)) {
                        x <- unlist(params[k,est])
                        fixed.pars <- unlist(params[k,fixed])
                        if (method=="subplex") {
                          require(subplex)
                          fit <- try(
                                     subplex(
                                             par=x,
                                             fn=obj.wrapper.fn,
                                             obj.fn=obj.fn,
                                             fixed=fixed.pars,
                                             userdata=userdata,
                                             hessian=FALSE,
                                             control=control
                                             ),
                                     silent=FALSE
                                     )
                        } else {
                          fit <- try(
                                     optim(
                                           par=x,
                                           fn=obj.wrapper.fn,
                                           obj.fn=obj.fn,
                                           fixed=fixed.pars,
                                           userdata=userdata,
                                           hessian=FALSE,
                                           control=control
                                           ),
                                     silent=FALSE
                                     )
                        }
                        if (inherits(fit,"try-error")) {
                          vals[k] <- NA
                          errs[k] <- nerr
                          errmsg <- append(errmsg,as.character(fit))
                          nerr <- nerr+1
                        } else {
                          vals[k] <- fit$value
                          errs[k] <- NA
                          params[k,est] <- fit$par
                        }
                      }
                      list(
                           vals=vals,
                           params=params,
                           errs=errs,
                           errmsg=errmsg
                           )
                    },
                    joblist,
                    common=list(
                      obj.fn=fn,
                      fixed=fixed,
                      userdata=userdata,
                      est=est,
                      method=method,
                      control=control
                      ),
                    info=info
                    )

    erridx <- sapply(res,inherits,"try-error")
    nerr <- sum(erridx)
    if (nerr>0) {
      cat("at level ",lev,": ",nerr," errors out of ",n1,"\n",sep="")
    }
    if (nerr>=n1)
      stop("all parameters resulted in error at level 1")
  
    params <- matrix(NA,nrow=n1-nerr,ncol=ncol(params),dimnames=list(NULL,colnames(params)))
    vals <- numeric(n1-nerr)
    k <- 1
    for (i in seq(length=length(res))) {
      for (j in seq(length=length(res[[i]]$val))) {
        vals[k] <- res[[i]]$vals[j]
        params[k,] <- unlist(res[[i]]$params[j,,drop=FALSE])
        k <- k+1
      }
    }
  
  }

  cbind(params,value=vals)
}
