\name{mpi.farm}
\alias{mpi.farm}
\alias{mpi.farm.slave}
\alias{farm}
\title{Farm out jobs across a cluster using MPI}
\description{
  Farm out a procedure (an arbitrary block of R-code) to a cluster of slaves, with different values of the variables.
}
\usage{
mpi.farm(proc, joblist, common = list(), stop.condition = TRUE, info = TRUE,
         checkpoint = NULL, checkpoint.file = NULL
         )
farm(proc, joblist, common = list(), stop.condition = TRUE, info = TRUE)
mpi.farm.slave(fn, common=list())
}
\arguments{
  \item{proc}{An arbitrary block of R code}
  \item{joblist}{
    A list of named lists.
    Each element is a named list to be treated as an environment defining some or all of the variables in \code{proc}.}
  \item{common}{An optional list of variables common to all the jobs.}
  \item{stop.condition}{
    This will be evaluated in the context of the return-value of \code{proc}.
    For this option to have an effect, \code{proc} must return a named list and \code{stop.condition} must evaluate to \code{TRUE} or \code{FALSE} in the context of that list.
    If it evaluates to \code{FALSE}, the return-value of \code{proc} is appended to \code{joblist}.
    This allows one to complete the calcuation in several steps, which in turn allows for more effective load-balancing.
    If the return-value of \code{proc} is not a list, this option has no effect.
  }
  \item{info}{Print information on the progress of the slaves?}
  \item{checkpoint}{
    optional integer specifying the granularity of checkpointing.
    That is, the checkpoint file will be saved once every \code{checkpoint} jobs from joblist are completed.
  }
  \item{checkpoint.file}{
    optional filename.
    If \code{checkpoint.file} is specified, then once every \code{checkpoint} jobs are finished, checkpoint information will be saved to a binary-format file with this name.
    This file will contain two lists: \code{finished}, consisting of those jobs in \code{joblist} that are fully completed and
    \code{unfinished}, consisting of that portion of \code{joblist} that has not yet been fully finished.
  }
  \item{fn}{A arbitrary block of R code, deparsed to a string.}
}
\details{
  \code{mpi.farm.slave} does the work on the slaves and should never need to be called by the user.
  This function is broadcast to the slaves, so that they will be able to do their part.
  \code{mpi.farm} broadcasts the \code{mpi.farm.slave} to the slaves before beginning to assign jobs.

  For many of the applications envisioned, the jobs the slaves are assigned involve stochastic simulations.
  Because of the way that R initializes its pseudorandom number generators (RNGs), it is easy to make the mistake of failing to initialize the RNGs on different slaves to different states.
  If one fails to do this (and doesn't use a sophisticated parallel RNG like SPRNG) then it is possible that the random numbers generated on different slaves will be correlated or even identical.

  For this reason, it is a good idea to set the seed of the RNG as part of the block of code \code{proc}.
  Storing the state of the RNG before doing so is often desirable, but this can be frustrating if the RNG has not been initialized.  \code{mpi.farm} checks to see if \code{.Random.seed} exists and, if it does not, initializes the RNG with a call to \code{runif}.  Thus, the user is guaranteed that the RNG has been initialized on each slave.
}
\value{
  The value returned by \code{mpi.farm} and \code{farm} is a list with one entry for each of the elements in \code{joblist}.
  The elements in the result correspond to the elements in the \code{joblist} argument.
}
\author{Aaron A. King}
\note{}
\seealso{}
\examples{
  \dontrun{
    mpi.spawn.Rslaves(needlog=F)

    x <- lapply(1:100,function(k)list(a=k,b=rnorm(1)))
    y <- mpi.farm(a+b,x)
    print(y)

    y <- mpi.farm({if(runif(1)<0.5)stop('yikes');a+b},x)
    print(y)

    y <- mpi.farm({if(runif(1)<0.1)stop('yikes');a+b},x,info=F)
    print(y)
    warnings()

    x <- lapply(1:100,function(k)list(a=k,b=0,done=0))
    y <- mpi.farm({b <- b+rnorm(1); list(a=a,b=b,done=done+1)},x,stop.condition=((abs(b)>2)|(done>10)))

    mpi.close.Rslaves()
  }
}
\keyword{programming}
\keyword{utilities}
