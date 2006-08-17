\name{pdapply}
\alias{pdapply}
\alias{plapply}
\alias{sdapply}
\alias{plapply.slave}
\alias{pdapply.slave}
\title{Parallel row-by-row data-frame and list apply.}
\description{
  Apply a procedure (an arbitrary block of R-code) to each row of a data
  frame or each element of a list.
}
\usage{
pdapply(job, pars, common = list(), info = TRUE)
sdapply(job, pars, common = list(), info = TRUE)
plapply(job, pars, common = list(), info = TRUE)
plapply.slave(fn, common=list())
pdapply.slave(fn, common=list())
}
\arguments{
  \item{job}{An arbitrary block of R code}
  \item{pars}{A data frame (in the case of \code{pdapply} and
    If R slaves have been started (using e.g.,
    \code{sdapply}) or list (in the case of \code{plapply}) defining
    variables.}
  \item{common}{A list of other variables held constant.}
  \item{info}{Print information on the progress of the slaves?}
  \item{fn}{An arbitrary block of R code.}
}
\details{
  \code{pdapply.slave} and \code{plapply.slave} do the work on the
  slaves and should never need to be called by the user.  However, these
  functions must be broadcast to the slaves, so that they will be able
  to do their part!  \code{pdapply} and \code{plapply} broadcast the
  appropriate one of these functions to the slaves before beginning to
  assign jobs.

  For many of the applications envisioned, the jobs the slaves are
  assigned involve stochastic simulations.  Because of the way that R
  initializes its pseudorandom number generators (RNGs), it is easy to make the
  mistake of failing to initialize the RNGs on different slaves to
  different states.  If one fails to do this (and doesn't use a
  sophisticated parallel RNG like SPRNG) then it is possible that the
  random numbers generated on different slaves will be correlated or
  even identical.

  For this reason, it is a good idea to set the seed of the RNG as part
  of the block of code \code{job}.  Storing the state of the RNG before
  doing so is often desirable, but this can be frustrating if the RNG
  has not been initialized.  \code{pdapply} and \code{plapply} check to
  see if \code{.Random.seed} exists and, if it does not, initialize the
  RNG with a call to \code{runif}.  Thus, the user is guaranteed that
  the RNG has been initialized on each slave.
}
\value{
  The value returned by \code{pdapply} is a data-frame (DESCRIBE).
  The value returned by \code{plapply} is a list (DESCRIBE).
  Note that the order of elements is the order in which the results were
  received from the slaves and may not correspond to the order in the
  \code{pars} argument.
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
    y <- plapply({if(runif(1)<0.1)stop('yikes');a+b},x,info=F)
    print(y)

    warnings()
    mpi.close.Rslaves()
  }
}
\keyword{programming}
\keyword{utilities}
