require(Rmpi)
require(mpifarm)

ncpus <- 6

mpi.spawn.Rslaves(nslaves=ncpus,needlog=T)

njobs <- 200

set.seed(34588366L)
seeds <- as.integer(ceiling(runif(n=njobs,min=0,max=2^31-1)))
x <- list()
for (i in seq_along(seeds)) {
  x[[i]] <- list(seed=seeds[i],n=0,b=-1)
}

tic <- Sys.time()

y1 <- mpi.farm(
               {
                 save.seed <- get(".Random.seed",envir=.GlobalEnv)
                 if (n==0) set.seed(seed)
                 else assign(".Random.seed",rng.state,envir=.GlobalEnv)
                 b <- rnorm(1)
                 n <- n+1
                 rng.state <- get(".Random.seed",envir=.GlobalEnv)
                 assign(".Random.seed",save.seed,envir=.GlobalEnv)
                 list(
                      seed=seed,
                      rng.state=rng.state,
                      b=b,
                      n=n
                      )
               },
               joblist=x,
               stop.condition=b[1]>0,
               chunk=1,
               info=FALSE
               )

toc <- Sys.time()
print(toc-tic)

tic <- Sys.time()

y2 <- mpi.farm(
               {
                 save.seed <- get(".Random.seed",envir=.GlobalEnv)
                 if (n==0) set.seed(seed)
                 else assign(".Random.seed",rng.state,envir=.GlobalEnv)
                 b <- rnorm(1)
                 n <- n+1
                 rng.state <- get(".Random.seed",envir=.GlobalEnv)
                 assign(".Random.seed",save.seed,envir=.GlobalEnv)
                 list(
                      seed=seed,
                      rng.state=rng.state,
                      b=b,
                      n=n
                      )
               },
               joblist=x,
               stop.condition=b[1]>0,
               chunk=8,
               blocking=TRUE,
               info=FALSE
               )

toc <- Sys.time()
print(toc-tic)

tic <- Sys.time()

y3 <- mpi.farm(
               {
                 save.seed <- get(".Random.seed",envir=.GlobalEnv)
                 if (n==0) set.seed(seed)
                 else assign(".Random.seed",rng.state,envir=.GlobalEnv)
                 b <- rnorm(1)
                 n <- n+1
                 rng.state <- get(".Random.seed",envir=.GlobalEnv)
                 assign(".Random.seed",save.seed,envir=.GlobalEnv)
                 list(
                      seed=seed,
                      rng.state=rng.state,
                      b=b,
                      n=n
                      )
               },
               joblist=x,
               stop.condition=b[1]>0,
               chunk=8,
               blocking=FALSE,
               info=FALSE
               )

toc <- Sys.time()
print(toc-tic)

mpi.close.Rslaves()

z1 <- sapply(y1,function(x)x$b)
n1 <- sapply(y1,function(x)x$n)

z2 <- sapply(y2,function(x)x$b)
n2 <- sapply(y2,function(x)x$n)

z3 <- sapply(y3,function(x)x$b)
n3 <- sapply(y3,function(x)x$n)

stopifnot(identical(z1,z2)&&identical(n1,n2))
stopifnot(identical(z2,z3)&&identical(n2,n3))
