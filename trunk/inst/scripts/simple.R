require(Rmpi)
mpi.spawn.Rslaves(needlog=T)
require(mpifarm)
nslave <- mpi.comm.size()-1
nper <- 500
nrand <- 1000
args <- commandArgs(TRUE)
eval(parse(text=args))
njobs <- nper*nslave
seeds <- ceiling(runif(njobs,1e8,1e9))
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
                        c(slave=me,time=toc-tic,mean=mean(x),sd=sd(x))
                      },
                      job.list,
                      common=list(
                        n=nrand
                        )
                      )
toc <- Sys.time()
x <- do.call(rbind,job.result)
write.csv(x,'job.csv')
print(toc-tic)
warnings()
mpi.close.Rslaves(dellog=F)
mpi.quit()
