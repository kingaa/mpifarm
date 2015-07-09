library(mpifarm)

if (require(Rmpi)) {

  ncpu <- 8
  mpi.spawn.Rslaves(nslaves=ncpu)

  mpi.farmer(
             num=100,
             bigseed=343435L,
             jobs={
               set.seed(bigseed)
               seeds <- as.integer(ceiling(runif(n=num,min=0,max=2^31-1)))
               joblist <- list()
               for (k in seq_along(seeds))
                 joblist[[k]] <- list(seed=seeds[k],a=k)
               joblist
             },
             common=list(q=11),
             main={
               save.seed <- .Random.seed
               set.seed(seed)
               x <- rnorm(n=1,mean=a+q)
               .Random.seed <<- save.seed
               list(s=a+q,x=x)
             },
             post={
               data.frame(
                          s=sapply(results,function(x)x$s),
                          x=sapply(results,function(x)x$x)
                          )
             },
             checkpoint.file="farmer1.rda",
             checkpoint=1,
             info=FALSE
             ) -> results

  print(results)

  mpi.farmer(
             num=100,
             chunk=5,
             bigseed=343435L,
             jobs={
               set.seed(bigseed)
               seeds <- as.integer(ceiling(runif(n=num,min=0,max=2^31-1)))
               joblist <- list()
               for (k in seq_along(seeds))
                 joblist[[k]] <- list(seed=seeds[k],a=k)
               joblist
             },
             common=list(q=11),
             main={
               save.seed <- .Random.seed
               print(c(seed,a,q))
               set.seed(seed)
               x <- rnorm(n=1,mean=a+q)
               .Random.seed <<- save.seed
               list(s=a+q,x=x)
             },
             post={
               data.frame(
                          s=sapply(results,function(x)x$s),
                          x=sapply(results,function(x)x$x)
                          )
             },
             checkpoint.file="farmer2.rda",
             checkpoint=1,
             info=FALSE
             ) -> results2

  stopifnot(identical(results,results2))

  mpi.farmer(
             num=100,
             chunk=5,
             bigseed=343435L,
             blocking=TRUE,
             jobs={
               set.seed(bigseed)
               seeds <- as.integer(ceiling(runif(n=num,min=0,max=2^31-1)))
               joblist <- list()
               for (k in seq_along(seeds))
                 joblist[[k]] <- list(seed=seeds[k],a=k)
               joblist
             },
             common=list(q=11),
             main={
               save.seed <- .Random.seed
               print(c(seed,a,q))
               set.seed(seed)
               x <- rnorm(n=1,mean=a+q)
               .Random.seed <<- save.seed
               list(s=a+q,x=x)
             },
             post={
               data.frame(
                          s=sapply(results,function(x)x$s),
                          x=sapply(results,function(x)x$x)
                          )
             },
             checkpoint.file="farmer3.rda",
             checkpoint=1,
             info=FALSE
             ) -> results3

  stopifnot(identical(results,results3))

  mpi.close.Rslaves()

}
