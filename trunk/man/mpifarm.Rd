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
\examples{}
\keyword{programming}
\keyword{utilities}
