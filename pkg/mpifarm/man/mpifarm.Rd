\name{mpi.farm}
\alias{mpi.farm}
\alias{mpi.farm.slave}
\keyword{internal}
\title{Farm out jobs across a cluster using MPI}
\description{
  Farm out a procedure (an arbitrary block of R-code) to a cluster of slaves, with different values of the variables.
}
\usage{
mpi.farm(proc, joblist, common = list(), status = NULL, chunk = 1,
         stop.condition = TRUE, info = TRUE,
         checkpoint = 0, checkpoint.file = NULL,
         max.backup = 20, sleep = 0.01, blocking = TRUE,
         verbose = getOption("verbose"))
mpi.farm.slave(fn, common=list(), verbose = getOption("verbose"))
}
\arguments{
  \item{proc}{
    An arbitrary block of \R code that will be executed for each element in \code{joblist}.
    At each execution, this code will be evaluated in an environment consisting of the corresponding element of \code{joblist} plus the \code{common} list.
    That is, when the \code{k}-th job is executed, the variables referred to in \code{proc} will be sought for in \code{joblist[[k]]} and, if they are not found there, in \code{common}.
  }
  \item{joblist}{
    A list of the jobs that will be farmed out.
    Each element of \code{joblist} should be a named list, defining some or all of the variables referred to by the code in \code{proc}.
  }
  \item{common}{
    An optional list of variables common to all the jobs.
  }
  \item{status}{
    An optional integer vector giving the status of the individual jobs in \code{joblist}.
    This will typically only arise when restarting from a checkpoint file.
  }
  \item{chunk}{
    optional integer; the chunk size to be used.
    By default, \code{chunk=1} and each job in \code{joblist} is sent individually to a slave and returned when finished.
    If \code{chunk>1}, chunks of this size are sent and processed sequentially.
    In other words, \code{chunk} adjusts the granularity of the parallel computation.
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
    If \code{checkpoint.file} is specified, then once every \code{checkpoint} jobs are finished, checkpoint information will be saved to a binary-format file with this name.
    This file will contain the \code{joblist} and \code{common} lists (the former having been updated) and an integer vector \code{status}, which indicates the status of each element in \code{joblist}.
  }
  \item{max.backup}{
    positive integer; maximum number of backup checkpoint files that will be created.
  }
  \item{sleep}{
    amount of time (in seconds) that the master will sleep between consecutive polls of the slave pool.
  }
  \item{blocking}{
    If TRUE, blocking MPI calls will be used, altering the job scheduling system.
    If FALSE non-blocking MPI calls are used for greater evenness and efficiency.
  }
  \item{verbose}{
    logical; if \code{TRUE}, information will be printed both by the master and the slaves.
  }
  \item{fn}{A arbitrary block of \R code, deparsed to a string.}
}
\details{
  A higher-level code is \code{mpi.farmer}, which calls \code{mpi.farm} and handles checkpointing.
  However, it may sometimes happen that a user wants to call \code{mpi.farm} directly.
  \code{mpi.farm.slave} does the work on the slaves and should never need to be called by the user.
  
  \code{mpi.farm} will execute the code in \code{proc} repeatedly in environments defined by the entries of \code{joblist} and the common environment \code{common}.
  If \pkg{Rmpi} slaves have been spawned, the jobs will be farmed out to them according to a load-balancing algorithm;
  if no slaves are running, or \pkg{Rmpi} has not been loaded, the jobs will be executed serially.

  For many of the applications envisioned, the jobs the slaves are assigned involve stochastic simulations.
  Because of the way that \R initializes its pseudorandom number generators (RNGs), it is easy to make the mistake of failing to initialize the RNGs on different slaves to different states.
  If one fails to do this (and doesn't use a sophisticated parallel RNG like SPRNG) then it is possible that the random numbers generated on different slaves will be correlated or even identical.

  For this reason, it is a good idea to set the seed of the RNG as part of the block of code \code{proc}.
  Storing the state of the RNG before doing so is often desirable, but this can be frustrating if the RNG has not been initialized.  \code{mpi.farm} checks to see if \code{.Random.seed} exists and, if it does not, initializes the RNG with a call to \code{runif}.  Thus, the user is guaranteed that the RNG has been initialized on each slave.

  A user interrupt to \code{mpi.farm} results in an attempt to terminate the slaves cleanly.
  This may take some time, since each slave has to finish the job it is currently working on before it becomes receptive to messages from the master.
  A user interrupt issued during the abort process will leave some finished jobs in the MPI queue and therefore compromise the integrity of future parallel computations.
  For this reason, when it is necessary to abort \code{mpi.farm} and not possible to allow it to terminate cleanly, it is recommended that the slaves be closed (via \code{mpi.close.Rslaves}) and restarted before further parallel computaitons are attempted.
}
\value{
  The value returned by \code{mpi.farm} and \code{farm} is a list with one entry for each of the elements in \code{joblist}.
  The elements in the result correspond to the elements in the \code{joblist} argument;
  the list \code{finished} is prepended.
}
\seealso{mpi.farmer}
\author{Aaron A. King}
\examples{
  \dontrun{
    mpi.spawn.Rslaves(needlog=F)

    x <- lapply(1:100,function(k)list(a=k,b=rnorm(1)))
    y <- mpi.farm(a+b,x)
    print(unlist(y))

    y <- mpi.farm({if(runif(1)<0.5)stop('yikes');a+b},x)
    print(unlist(y))

    y <- mpi.farm({if(runif(1)<0.1)stop('yikes');a+b},x,info=F)
    y <- y[!sapply(y,inherits,"try-error")]
    print(unlist(y))
    warnings()

    x <- lapply(1:100,function(k)list(a=k,b=0,done=0))
    y <- mpi.farm({b <- b+rnorm(1); list(a=a,b=b,done=done+1)},x,stop.condition=((abs(b)>2)|(done>10)))

    mpi.close.Rslaves()

  }
## run some jobs in serial mode
  x <- lapply(1:100,function(k)list(a=k,b=0,done=0))
  y <- mpi.farm({b <- b+rnorm(1); list(a=a,b=b,done=done+1)},x,stop.condition=((abs(b)>2)|(done>10)))
}
\keyword{programming}
\keyword{utilities}
