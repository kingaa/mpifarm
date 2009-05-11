\name{mif.farm}
\alias{mif.farm}
\alias{mif.farm.init}
\alias{par.trans}
\alias{par.untrans}
\title{Manage a MIF farm}
\description{
  Farm out iterated filtering jobs across a cluster.
}
\usage{
mif.farm.init(nreps = 1, init.disp = 0, parameters, make.pomp, \dots)
mif.farm(joblist, jobname = NULL, solib = NULL,
         nmifs = 10, unweighted = 0, max.fail = 0,
         gran = 5, Np = 1000, cooling.factor = 0.99,
         ic.lag = 60, var.factor = 4, 
         filter.q = TRUE, nfilters = 10,
         scratchdir = getwd(),
         checkpoint = mpi.universe.size(), \dots)
par.trans(object, params)
par.untrans(object, params)
}
\arguments{
  \item{nreps}{
    Number of replicates per parameter set
  }
  \item{init.disp}{
    optional number; initial-displacement multiplier
  }
  \item{parameters}{
    data frame; defines starting-point parameters, datasets, and models.
    Also sets the random-walk SDs.
  }
  \item{make.pomp}{
    function; creates the \code{pomp} objects.
  }
  \item{joblist}{
    A list of named lists.
    Each element represents a mif run.
  }
  \item{jobname}{
    character; name of the job (used in naming of checkpoint files).
  }
  \item{solib}{
    character; name of shared-object library to be dynamically-loaded
  }
  \item{nmifs}{
    integer; number of MIF iterations to perform
  }
  \item{unweighted}{
    integer; number of initial iterations to perform using unweighted averaging
  }
  \item{max.fail}{
    integer; maximum number of particle filtering failures to allow before triggering an error
  }
  \item{gran}{
    integer; granularity of parallel jobs, i.e., number of MIF iterations to run per assignment
  }
  \item{Np, cooling.factor, ic.lag, var.factor}{
    algorithmic parameters for \code{mif}
  }
  \item{filter.q, nfilters}{
    If \code{filter.q=TRUE}, perform \code{nfilters} additional \code{pfilter} after the MIF iterations are completed.
  }
  \item{scratchdir}{
    character; path to scratch directory in which checkpoint files will be saved
  }
  \item{checkpoint}{
    optional integer specifying the granularity of checkpointing.
    That is, the checkpoint file will be saved once every \code{checkpoint} jobs from joblist are completed.
  }
  \item{object}{
    a \code{pomp} object.
    If \code{object@userdata} contains functions named \code{transform.fn} and \code{untransform.fn}, these form the basis of the \code{par.trans} and \code{par.untrans} operations.
    Otherwise, these operations have no effect.
  }
  \item{params}{
    a named parameter vector.
    The parameters to be transformed or untransformed.
    If this is not specified, \code{coef(object)} will be used instead.
  }
  \item{\dots}{
    other arguments, ignored.
  }
}
\details{
}
\value{
  \code{mif.farm.init} returns a list of jobs suitable for entry as the \code{joblist} argument of \code{mif.farm}.
  \code{mif.farm} returns a list containing three elements:
  (i) \code{finished}, a list containing the completed jobs,
  (ii) \code{err}, a list of error messages generated on the slaves,
  (iii) \code{mle}, a data frame containing the MLEs and their likelihoods
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
