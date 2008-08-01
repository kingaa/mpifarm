require(Rmpi)
mpi.spawn.Rslaves(needlog=T)

require(mpifarm)

x <- lapply(1:100,function(k)list(a=k,b=rnorm(1)))
y <- mpi.farm(a+b,x)
print(y)

y <- mpi.farm({if(runif(1)<0.5)stop('yikes');a+b},x)
print(y)

y <- mpi.farm({if(runif(1)<0.1)stop('yikes');a+b},x,info=F)
print(y)
warnings()

x <- lapply(1:100,function(k)list(a=k,b=0,done=0))
y <- mpi.farm({print(c(a,b,done));list(a=a,b=b+rnorm(1),done=done+1)},x,stop.condition=((abs(b)>2)|(done>10)))
print(y)

mpi.close.Rslaves()
mpi.quit()
