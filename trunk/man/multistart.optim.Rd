\name{multistart.optim.farm}
\alias{multistart.optim.farm}
\title{Manage a multistart/multistage optimization farm}
\description{
  Farm out optimization jobs across a cluster.
}
\usage{
multistart.optim.farm(fn, params, est, n = integer(0),
                      gran = 20, jobname = NULL,
                      scratchdir = getwd(),
                      checkpoint = mpi.universe.size(),
                      info = TRUE,
                      method = c("Nelder-Mead", "subplex", "BFGS", "L-BFGS-B"),
                      control = list(), \dots)
}  
\arguments{
  \item{fn}{
    The objective function to be minimized.
  }
  \item{params}{
    A matrix or data-frame containing the starting parameter values.
    Must have column names.
  }
  \item{est}{
    character; names of parameters to estimate.
    All other parameter will be treated as fixed.
  }
  \item{n}{
    integer; number of items to skim at each level.  
  }
  \item{gran}{
    integer vector;
    granularity of parallel jobs, i.e., number of parallel evaluations/optimizations to run per assignment.
  }
  \item{jobname}{
    character; name of the job (used in naming of checkpoint files).
  }
  \item{scratchdir}{
    character; path to scratch directory in which checkpoint files will be saved
  }
  \item{checkpoint}{
    optional integer specifying the granularity of checkpointing.
    That is, the checkpoint file will be saved once every \code{checkpoint} jobs from joblist are completed.
  }
  \item{info}{
    should progress information be displayed?
  }
  \item{method}{
    The optimization algorithm to be used.
    See \code{\link[subplex]{subplex}} and \code{\link{optim}} for information on the available options.
  } 
  \item{control}{
    optional; list of control parameters to be passed to \code{\link{optim}} or \code{\link[subplex]{subplex}}.
    See the documentation for these functions for details and defaults.
  }
  \item{\dots}{
    additional arguments are passed to \code{fn}.
  }
}
\details{}
\value{}
\author{Aaron A. King}
\examples{
 \dontrun{
mpi.spawn.Rslaves()

## Rosenbrock banana function
rosen <- function (x1, x2, g = 0, h = 0) {
  100*(x2-h-x1*x1)^2+(1-x1)^2+g
}

## Find the global optimum.
res <- multistart.optim.farm(
                             fn=rosen,
                             params=sobol(list(x1=c(-30,50),x2=c(-10,10)),n=10000),
                             g=110,
                             h=-6,
                             est=c("x1","x2"),
                             n=c(100,48,16),
                             gran=c(100,4,1,1),
                             jobname="bob"
                             )

## Profile over g and h
res <- multistart.optim.farm(
                             fn=rosen,
                             params=cbind(
                               sobol(list(x1=c(-30,50),x2=c(-10,10)),n=10000),
                               g=100,
                               h=rep(-4:5,each=1000)
                               ),
                             est=c("x1","x2"),
                             n=c(100,48,16,1),
                             gran=c(100,4,1,1,1),
                             jobname="bob"
                             )
mpi.close.Rslaves()
}
}
\keyword{programming}
\keyword{utilities}
