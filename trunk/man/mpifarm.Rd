\name{pdapply}
\alias{pdapply}
%- Also NEED an '\alias' for EACH other topic documented here.
\title{ ~~function to do ... ~~ }
\description{
  ~~ A concise (1-5 lines) description of what the function does. ~~
}
\usage{
pdapply(fun, pars, common = list(), info = T)
}
%- maybe also 'usage' for other objects documented here.
\arguments{
  \item{fun}{ ~~Describe \code{fun} here~~ }
  \item{pars}{ ~~Describe \code{pars} here~~ }
  \item{common}{ ~~Describe \code{common} here~~ }
  \item{info}{ ~~Describe \code{info} here~~ }
}
\details{
  ~~ If necessary, more details than the description above ~~
}
\value{
  ~Describe the value returned
  If it is a LIST, use
  \item{comp1 }{Description of 'comp1'}
  \item{comp2 }{Description of 'comp2'}
  ...
}
\references{ ~put references to the literature/web site here ~ }
\author{ ~~who you are~~ }
\note{ ~~further notes~~ 

 ~Make other sections like Warning with \section{Warning }{....} ~
}
\seealso{ ~~objects to See Also as \code{\link{help}}, ~~~ }
\examples{
##---- Should be DIRECTLY executable !! ----
##-- ==>  Define data, use random,
##--	or do  help(data=index)  for the standard data sets.

## The function is currently defined as
function (fun, pars, common=list(), info=T) { # row-by-row data.frame apply (parallel version)
  fn <- deparse(substitute(fun))
  mpi.remote.exec(pdapply.slave,fn,common,ret=F)
  result <- data.frame()
  sent <- 0
  rcvd <- 0
  nslave <- mpi.comm.size() - 1
  slaveinfo <- matrix(0,1,nslave+1,dimnames=list('jobs',c(1:nslave,'total')))
  for (d in 1:nslave) {  # initialize the queue
    sent <- sent+1
    if (sent <= nrow(pars)) {
      mpi.send.Robj(pars[sent,],dest=d,tag=3)
    } else {
      mpi.send.Robj(0,dest=d,tag=666)
    }
  }
  while (rcvd < nrow(pars)) {
    res <- mpi.recv.Robj(source=mpi.any.source(),tag=mpi.any.tag())
    srctag <- mpi.get.sourcetag()
    src <- mpi.get.sourcetag()[1]
    tag <- mpi.get.sourcetag()[2]
    rcvd <- rcvd+1
    if (tag == 33) {
      result <- rbind(result,res)
      slaveinfo[1,src] <- slaveinfo[1,src] + 1
      slaveinfo[1,nslave+1] <- slaveinfo[1,nslave+1] + 1
      print(slaveinfo)
    } else {
      warning(paste('slave',format(src),'reports:',res))
    }
    if (sent < nrow(pars)) {
      sent <- sent+1
      mpi.send.Robj(pars[sent,],dest=src,tag=3)
    } else {
      mpi.send.Robj(0,dest=src,tag=666)
    }
  }
  result
  }
}
\keyword{ ~kwd1 }% at least one, from doc/KEYWORDS
\keyword{ ~kwd2 }% __ONLY ONE__ keyword per line
