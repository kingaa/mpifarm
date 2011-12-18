require(Rmpi)
require(mpifarm)
nslave <- 8
mpi.spawn.Rslaves(nslaves=nslave,needlog=T)
nper <- 50
nrand <- 1000
njobs <- nper*nslave
seeds <- ceiling(runif(njobs,0,2^31))
job.list <- lapply(seeds,function(x)list(seed=x))
tic <- Sys.time()
job.result <- mpi.farm(
	               {
                         save.seed <- .Random.seed
                         set.seed(seed)
                         tic <- Sys.time()
                         x <- rnorm(n)
                         toc <- Sys.time()
                         .Random.seed <<- save.seed
                         me <- mpi.comm.rank()
                         c(slave=me,time=toc-tic,mean=mean(x),sd=sd(x),n=length(x))
                       },
                       job.list,
                       common=list(n=nrand),
                       info=FALSE
                       )
toc <- Sys.time()
x <- do.call(rbind,job.result)
print(toc-tic)
warnings()
mpi.close.Rslaves()
mpi.exit()
