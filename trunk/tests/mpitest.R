require(Rmpi)
mpi.spawn.Rslaves(needlog=T)

require(mpifarm)

set.seed(1066)
seeds <- ceiling(runif(n=mpi.universe.size(),0,2^31))
x <- mpi.farm({set.seed(seed)},joblist=lapply(seeds,function(x)list(seed=x)),info=F)

x <- lapply(1:100,function(k)list(a=k,b=rnorm(1)))
y <- mpi.farm(a+b,x,info=F)

y <- mpi.farm({if(runif(1)<0.1)stop('yikes');a+b},x,info=F)
warnings()

x <- lapply(1:100,function(k)list(a=k,b=0,done=0))
y <- mpi.farm({print(c(a,b,done));list(a=a,b=b+rnorm(1),done=done+1)},x,stop.condition=((abs(b)>2)|(done>10)),info=F)

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

mpi.close.Rslaves()
mpi.quit()
