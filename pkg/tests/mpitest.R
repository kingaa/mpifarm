require(Rmpi)
require(mpifarm)

mpi.spawn.Rslaves(needlog=T)

set.seed(1066)
seeds <- ceiling(runif(n=mpi.universe.size(),0,2^31))
x <- mpi.farm({set.seed(seed)},joblist=lapply(seeds,function(x)list(seed=x)),info=F)

x <- lapply(1:100,function(k)list(a=k,b=rnorm(1)))
y <- mpi.farm(a+b,x,info=F)

x <- lapply(1:100,function(k)list(a=k))
y <- mpi.farm({for (j in 1:10000) j <- j+1; a},x,info=F)
sum(diff(as.numeric(y))!=1)

y <- mpi.farm({if(runif(1)<0.1)stop('yikes');a+runif(1)},x,info=F)
warnings()

x <- lapply(1:300,function(k)list(a=k,b=10*k))
y <- mpi.farm(a+mean(rnorm(n=b)),x,checkpoint.file="mpitest.rda",checkpoint=23,info=F)

file.remove("mpitest.rda")

x <- lapply(1:50,function(k)list(a=k,b=10*k,done=FALSE))
y <- mpi.farm(
              {
               list(a=a-1,b=b,m=mean(rnorm(n=b)),done=(a<=1))
               },
              x,
              stop.condition=done,
              checkpoint.file="mpitest.rda",
              checkpoint=500,
              info=FALSE
              )

file.remove("mpitest.rda")

x <- lapply(1:100,function(k)list(a=k,b=0,done=0))
y <- mpi.farm({print(c(a,b,done));list(a=a,b=b+rnorm(1),done=done+1)},x,stop.condition=((abs(b)>2)|(done>10)),info=F)

x <- lapply(1:100,function(k)list(a=k,b=rnorm(1)))
y1 <- unlist(mpi.farm(a+b,x,info=F))

mpi.close.Rslaves()

y2 <- unlist(mpi.farm(a+b,x,info=F))
max(abs(diff(y1-y2)))

x <- lapply(1:100,function(k)list(a=k,b=0,done=0))
y <- mpi.farm({print(c(a,b,done));list(a=a,b=b+rnorm(1),done=done+1)},x,stop.condition=((abs(b)>2)|(done>10)),info=F)

mpi.quit()
