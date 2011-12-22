require(Rmpi)
require(mpifarm)

ncpus <- 8

mpi.spawn.Rslaves(nslaves=ncpus,needlog=T)

set.seed(1066L)
seeds <- as.integer(ceiling(runif(n=ncpus,0,2^31)))

x <- mpi.farm({set.seed(seed)},joblist=lapply(seeds,function(x)list(seed=x)),info=F)

x <- lapply(1:100,function(k)list(a=k,b=rnorm(1)))
y <- mpi.farm(a+b,x,info=F)

x <- lapply(1:100,function(k)list(a=k))
y <- mpi.farm({for (j in 1:10000) j <- j+1; a},x,info=F)
stopifnot(sum(diff(as.numeric(y))!=1)==0)

y <- mpi.farm({if(runif(1)<0.1)stop('yikes');a+runif(1)},x,info=F)
warnings()

seeds <- as.integer(ceiling(runif(n=321,1,2^31)))
x <- lapply(1:321,function(k)list(a=k,b=10*k,seed=seeds[k]))
y1 <- mpi.farm({set.seed(seed); a+mean(rnorm(n=b))},joblist=x,checkpoint.file="mpitest.rda",checkpoint=23,info=F)
load("mpitest.rda")
y2 <- mpi.farm({set.seed(seed); a+mean(rnorm(n=b))},joblist=joblist,status=status,checkpoint.file="mpitest.rda",checkpoint=23,info=F)
stopifnot(identical(y1,y2))

joblist <- x
y2 <- mpi.farm({set.seed(seed); a+mean(rnorm(n=b))},joblist=joblist,checkpoint.file="mpitest.rda",checkpoint=23,info=F)
y2 <- mpi.farm({set.seed(seed); a+mean(rnorm(n=b))},joblist=joblist,checkpoint.file="mpitest.rda",checkpoint=23,info=F)
y2 <- mpi.farm({set.seed(seed); a+mean(rnorm(n=b))},joblist=joblist,checkpoint.file="mpitest.rda",checkpoint=23,info=F)
y2 <- mpi.farm({set.seed(seed); a+mean(rnorm(n=b))},joblist=joblist,checkpoint.file="mpitest.rda",checkpoint=23,info=F)
y2 <- mpi.farm({set.seed(seed); a+mean(rnorm(n=b))},joblist=joblist,checkpoint.file="mpitest.rda",checkpoint=23,info=F)

y3 <- mpi.farm({set.seed(seed); a+mean(rnorm(n=b))},joblist=joblist,chunk=5,info=F,checkpoint=23,checkpoint.file="mpitest2.rda")
y3 <- mpi.farm({set.seed(seed); a+mean(rnorm(n=b))},joblist=joblist,chunk=5,info=F,checkpoint=23,checkpoint.file="mpitest2.rda")
stopifnot(identical(y2,y3))

x <- lapply(1:50,function(k)list(a=k,b=10*k,done=FALSE))
y <- mpi.farm(
              {
               list(a=a-1,b=b,m=mean(rnorm(n=b)),done=(a<=1))
               },
              joblist=x,
              stop.condition=done,
              checkpoint.file="mpitest.rda",
              checkpoint=500,
              info=FALSE
              )

seeds <- as.integer(ceiling(runif(n=100,1,2^31)))
x1 <- lapply(1:100,function(k)list(a=k,b=0,done=0,seed=seeds[k]))
y1 <- mpi.farm(
               {
                 set.seed(seed)
                 list(
                      a=a,
                      b=b+rnorm(1),
                      done=done+1,
                      seed=seed
                      )
               },
               joblist=x1,
               stop.condition=((abs(b)>2)|(done>10)),
               info=F
               )

x2 <- lapply(1:100,function(k)list(a=k,b=rnorm(1),seed=seeds[k]))
z1 <- unlist(mpi.farm({set.seed(seed); a+b},joblist=x2,info=F))

mpi.close.Rslaves()

y2 <- mpi.farm(
               {
                 set.seed(seed)
                 list(
                      a=a,
                      b=b+rnorm(1),
                      done=done+1,
                      seed=seed
                      )
               },
               joblist=x1,
               stop.condition=((abs(b)>2)|(done>10)),
               info=F
               )

z2 <- unlist(mpi.farm({set.seed(seed); a+b},joblist=x2,info=F))

stopifnot(identical(y1,y2))

stopifnot(identical(z1,z2))

mpi.exit()
