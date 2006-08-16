\name{pdapply}
\alias{pdapply}
\alias{plapply}
\alias{sdapply}
\alias{plapply.slave}
\alias{pdapply.slave}
\title{Row-by-row data-frame apply (parallel version).}
\description{
Apply a procedure (an arbitrary block of R-code) to each row of a data
frame.
}
\usage{
pdapply(fun, pars, common = list(), info = T)
plapply(fun, pars, common = list(), info = T)
sdapply(fun, pars, common = list(), info = T)
plapply.slave(fn, common=list())
pdapply.slave(fn, common=list())
}
\arguments{
  \item{fun}{An arbitrary block of R code}
  \item{pars}{A data frame defining variables.}
  \item{common}{A list of other variables held constant.}
  \item{info}{Print information on the progress of the slaves?}
  \item{fn}{An arbitrary block of R code.}
}
\details{}
\value{
  The value returned by \code{pdapply} is a data-frame (DESCRIBE).
  The value returned by \code{plapply} is a list (DESCRIBE).
  \code{pdapply.slave} and \code{plapply.slave} do the work on the slaves.
}
\author{Aaron A. King}
\note{}
\seealso{}
\examples{
  \dontrun{
    require(Rmpi)
    mpi.spawn.Rslaves(needlog=F)
    
    require(pdapply)

    x <- data.frame(a=1:50,b=101:150)
    y <- pdapply(a+b,x)
    print(y)
    y <- pdapply({if(runif(1)<0.5)stop('help');a+b},x)
    print(y)

    x <- lapply(1:100,function(k)list(a=k,b=rnorm(1)))
    y <- plapply(a+b,x)
    print(y)
    y <- plapply({if(runif(1)<0.5)stop('yikes');a+b},x)
    print(y)
    y <- plapply({if(runif(1)<0.5)stop('yikes');a+b},x,info=F)
    print(y)

    warnings()
    mpi.close.Rslaves()
  }
}
\keyword{programming}
\keyword{utilities}
