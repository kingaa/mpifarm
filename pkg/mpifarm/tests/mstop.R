require(Rmpi)
require(mpifarm)

ncpus <- 6

mpi.spawn.Rslaves(nslaves=ncpus,needlog=T)

njobs <- 200

set.seed(34588366L)
seeds <- as.integer(ceiling(runif(n=njobs,min=0,max=2^31-1)))
x <- list()
save.seed <- .Random.seed
for (i in seq_along(seeds)) {
  set.seed(seeds[i])
  x[[i]] <- list(rng.state=.Random.seed)
}
.Random.seed <<- save.seed

y1 <- mpi.farm(
               {
                 save.seed <- .Random.seed
                 .Random.seed <<- rng.state
                 b <- rnorm(1)
                 rng.state <- .Random.seed
                 .Random.seed <<- save.seed
                 list(
                      rng.state=rng.state,
                      b=b
                      )
               },
               joblist=x,
               stop.condition=b>0,
               info=FALSE
               )

y2 <- mpi.farm(
               {
                 save.seed <- .Random.seed
                 .Random.seed <<- rng.state
                 b <- rnorm(1)
                 rng.state <- .Random.seed
                 .Random.seed <<- save.seed
                 list(
                      rng.state=rng.state,
                      b=b
                      )
               },
               joblist=x,
               stop.condition=b>0,
               chunk=8,
               info=FALSE
               )

stopifnot(identical(y1,y2))

mpi.close.Rslaves()
mpi.exit()

