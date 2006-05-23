\name{pdapply}
\alias{pdapply}
\alias{plapply}
\alias{sdapply}
\title{Row-by-row data-frame apply (parallel version).}
\description{
Apply a procedure (an arbitrary block of R-code) to each row of a data
frame.
}
\usage{
pdapply(fun, pars, common = list(), info = T)
plapply(fun, pars, common = list(), info = T)
sdapply(fun, pars, common = list())
}
\arguments{
  \item{fun}{An arbitrary block of R code}
  \item{pars}{A data frame defining variables.}
  \item{common}{A list of other variables held constant.}
  \item{info}{Print information on the progress of the slaves?}
}
\details{}
\value{
  The value returned by \code{pdapply} is a data-frame (DESCRIBE).
  The value returned by \code{plapply} is a list (DESCRIBE).
}
\author{Aaron A. King}
\note{}
\seealso{}
\examples{}
\keyword{programming}
\keyword{utilities}
