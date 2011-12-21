\name{mpi.farmer}
\alias{mpi.farmer}
\title{Farm out jobs across a cluster using MPI}
\description{
  Farm out a procedure (an arbitrary block of R-code) to a cluster of slaves, with different values of the variables.
}
\usage{
mpi.farmer(\dots, jobs, common, main, post,
           chunk = 1, blocking = FALSE,
           checkpoint.file = NULL, checkpoint = 0,
           max.backup = 20,
           stop.condition = TRUE, info = TRUE,
           verbose = getOption("verbose"))
}
\arguments{
  \item{\dots}{
    named arguments other than those described below will be placed into an environment.
    This codes \code{jobs}, \code{common}, and \code{post} will be evaluated in this environment.
  }
  \item{jobs}{
    job setup code.
    An arbitrary block of \R code that creates a list of jobs.
    Each element of \code{jobs} should be a named list, defining some or all of the variables referred to by the code in \code{main}.
    If a checkpoint file exists, it will be loaded and \code{jobs} will not be executed.
  }
  \item{common}{
    common variables setup code.
    An arbitrary block of \R code that creates a list of variables common to all the jobs.
    If a checkpoint file exists, it will be loaded and \code{common} will not be executed.
  }
  \item{main}{
    main computation code, for execution in parallel.
    An arbitrary block of \R code that will be executed for each element in \code{joblist}.
    At each execution, this code will be evaluated in an environment consisting of the corresponding element of \code{joblist} plus the \code{common} list.
    That is, when the \code{k}-th job is executed, the variables referred to in \code{main} will be sought for in \code{joblist[[k]]} and, if they are not found there, in \code{common}.
  }
  \item{post}{
    post-processing code.
    An arbitrary block of \R code that will be processed after the \code{main} computations are all finished.
    When this code is executed, a list named \code{results} will be present and will contain the results of evaluating \code{main} on each element in the list created by \code{jobs}.
  }
  \item{chunk}{
    optional integer; the chunk size to be used.
    By default, \code{chunk=1} and each job in \code{joblist} is sent individually to a slave and returned when finished.
    If \code{chunk>1}, chunks of this size are sent and processed sequentially.
    In other words, \code{chunk} adjusts the granularity of the parallel computation.
  }
  \item{blocking}{
    If TRUE, blocking MPI calls will be used, altering the job scheduling system.
    The default is to use non-blocking MPI calls for greater evenness and efficiency.
  }
  \item{stop.condition}{
    After each execution, this expression will be evaluated in the context of the return-value of \code{proc}.
    For this option to have an effect, \code{proc} must return a named list and \code{stop.condition} must evaluate to \code{TRUE} or \code{FALSE} in the context of that list.
    If it evaluates to \code{FALSE}, the job is not finished; the return-value of \code{proc} will be appended to \code{joblist} for another round of processing.
    If it evaluates to \code{TRUE}, the job is finished.
    This allows one to complete the calcuation in several steps, which in turn allows for more effective load-balancing.
    If the return-value of \code{proc} is not a list, this option has no effect.
  }
  \item{info}{
    If \code{info=TRUE}, information on the progress of each slave will be printed.
  }
  \item{checkpoint}{
    optional integer specifying the granularity of checkpointing.
    That is, the checkpoint file will be saved once every \code{checkpoint} jobs from joblist are completed.
    If \code{checkpoint<1}, no checkpointing will be performed.
  }
  \item{checkpoint.file}{
    optional filename.
    if \code{checkpoint>0} then once every \code{checkpoint} jobs are finished, the current state of the computation will be saved to a binary-format file of the name given in \code{checkpoint.file}.
    If \code{checkpoint>0} and the file named in \code{checkpoint.file} exists, it will be loaded and computations will be resumed from that point.
    Old checkpoint files will be backed up.
  }
  \item{max.backup}{
    positive integer; maximum number of backup checkpoint files that will be created.
  }
  \item{verbose}{
    logical; if \code{TRUE}, information will be printed both by the master and the slaves.
  }
}
\details{
  \code{mpi.farmer} will execute the code in \code{main} repeatedly in environments defined by the entries of the list created by \code{jobs} and the variables in the list created by \code{common}.
  If \pkg{Rmpi} slaves have been spawned, the jobs will be farmed out to them according to a load-balancing algorithm;
  if no slaves are running, or \pkg{Rmpi} has not been loaded, the jobs will be executed serially.

  If the file named in \code{checkpoint.file} exists, \code{mpi.farmer} will not execute \code{jobs} or \code{common} but will instead load the checkpoint file and resume the computations.

  For many of the applications envisioned, the jobs the slaves are assigned involve stochastic simulations.
  Because of the way that \R initializes its pseudorandom number generators (RNGs), it is easy to make the mistake of failing to initialize the RNGs on different slaves to different states.
  If one fails to do this (and doesn't use a sophisticated parallel RNG like SPRNG) then it is possible that the random numbers generated on different slaves will be correlated or even identical.
  For this reason, it is a good idea to set the seed of the RNG as part of the block of code \code{main}.
  Storing the state of the RNG before doing so is often desirable, but this can be frustrating if the RNG has not been initialized.
  \code{mpi.farmer} checks to see if \code{.Random.seed} exists and, if it does not, initializes the RNG with a call to \code{runif}.
  Thus, the user is guaranteed that the RNG has been initialized on each slave.

  A user interrupt to \code{mpi.farmer} results in an attempt to terminate the slaves cleanly.
  This may take some time, since each slave has to finish the job it is currently working on before it becomes receptive to messages from the master.
  A user interrupt issued during the abort process will leave some finished jobs in the MPI queue and therefore compromise the integrity of future parallel computations.
  For this reason, when it is necessary to abort \code{mpi.farmer} and not possible to allow it to terminate cleanly, it is recommended that the slaves be closed (via \code{mpi.close.Rslaves}) and restarted before further parallel computaitons are attempted.
}
\value{
  If \code{post} is not set, \code{mpi.farmer} returns a list with one entry for each of the elements in the list created by \code{jobs}.
  If \code{post} is set, \code{mpi.farmer} returns whatever \code{post} does.
}
\author{Aaron A. King}
\examples{
  \dontrun{
library(Rmpi)

mpi.spawn.Rslaves(nslaves=5)

set.seed(87544545L)

## simulate some order statistics
mpi.farmer(
           n=1000,
           stdev=1,
           ntries=10,
           common={
             list(n=ntries,sd=stdev)
           },
           jobs={
             seeds <- as.integer(ceiling(runif(n=n,min=0,max=2^31-1)))
             lapply(seeds,function(s)list(seed=s))
           },
           main={
             save.seed <- .Random.seed
             set.seed(seed)
             x <- sort(rnorm(n=n,mean=0,sd=sd))
             .Random.seed <<- save.seed
             list(seed=seed,x=x)
           },
           post={
             res <- lapply(results,function(y)y$x)
             res <- do.call(rbind,res)
             as.data.frame(res)
           },
           chunk=10
           ) -> results

## do the same, with checkpointing
mpi.farmer(
           checkpoint=100,
           checkpoint.file="farmer.rda",
           n=1000,
           stdev=1,
           ntries=10,
           common={
             list(n=ntries,sd=stdev)
           },
           jobs={
             seeds <- as.integer(ceiling(runif(n=n,min=0,max=2^31-1)))
             lapply(seeds,function(s)list(seed=s))
           },
           main={
             save.seed <- .Random.seed
             set.seed(seed)
             x <- sort(rnorm(n=n,mean=0,sd=sd))
             .Random.seed <<- save.seed
             list(seed=seed,x=x)
           },
           post={
             res <- lapply(results,function(y)y$x)
             res <- do.call(rbind,res)
             as.data.frame(res)
           },
           chunk=10
           ) -> results

mpi.close.Rslaves()
  }
}
\keyword{programming}
\keyword{utilities}
