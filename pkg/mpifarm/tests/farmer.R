library(mpifarm)
library(Rmpi)

ncpu <- 8
mpi.spawn.Rslaves(nslaves=ncpu)

mpifarm:::mpi.farmer(
                     num=100,
                     bigseed=343435L,
                     pre={
                       set.seed(bigseed)
                       seeds <- as.integer(ceiling(runif(n=num,min=0,max=2^31-1)))
                       joblist <- list()
                       for (k in seq_along(seeds))
                         joblist[[k]] <- list(seed=seeds[k],a=k)
                       joblist
                     },
                     main={
                       save.seed <- .Random.seed
                       set.seed(seed)
                       x <- rnorm(n=1,mean=a+q)
                       .Random.seed <<- save.seed
                       list(s=a+q,x=x)
                     },
                     common=list(q=11),
                     post={
                       file.remove("farmer.rda")
                       data.frame(
                                  s=sapply(results,function(x)x$s),
                                  x=sapply(results,function(x)x$x)
                                  )
                     },
                     checkpoint.file="farmer.rda",
                     checkpoint=1,
                     info=FALSE
                     ) -> results

print(results)

mpifarm:::mpi.farmer(
                     num=100,
                     chunk=5,
                     bigseed=343435L,
                     pre={
                       set.seed(bigseed)
                       seeds <- as.integer(ceiling(runif(n=num,min=0,max=2^31-1)))
                       joblist <- list()
                       for (k in seq_along(seeds))
                         joblist[[k]] <- list(seed=seeds[k],a=k)
                       joblist
                     },
                     main={
                       save.seed <- .Random.seed
                       print(c(seed,a,q))
                       set.seed(seed)
                       x <- rnorm(n=1,mean=a+q)
                       .Random.seed <<- save.seed
                       list(s=a+q,x=x)
                     },
                     common=list(q=11),
                     post={
                       file.remove("farmer.rda")
                       data.frame(
                                  s=sapply(results,function(x)x$s),
                                  x=sapply(results,function(x)x$x)
                                  )
                     },
                     checkpoint.file="farmer.rda",
                     checkpoint=1,
                     info=FALSE
                     ) -> results2

stopifnot(identical(results,results2))

mpi.close.Rslaves()
mpi.exit()

