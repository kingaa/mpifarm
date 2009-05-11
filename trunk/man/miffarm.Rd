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
jobname <- "test"

imagefile <- paste('image_',jobname,'.rda',sep='') # binary file for saving the workspace
mpfile <- paste('modelparams_',jobname,'.csv',sep='') # input parameter file
mlefile <- paste('mle_',jobname,'.csv',sep='') # MLEs are to be saved here
modelRfile <- paste(modelStem,".R",sep='')

source(modelRfile)         # model-specific codes, loading data, etc.

if (!exists("make.pomp"))
   stop("file ",sQuote(modelRfile)," does not define ",sQuote("make.pomp")," as it should")
if (!exists("solib"))
   solib <- NULL

## read the input parameter file
parameters <- read.csv(file=mpfile)   
## random-walks and initial displacements are to be multiplicative
unfinished <- eval(
                  parse(
                        text=paste(
                          "mif.farm.init(",
                          "parameters=parameters,",
                          "make.pomp=make.pomp,",
                          paste(args,collapse=','),
                          ")",
                          sep=""
                          )
                        )
                   )

mpi.spawn.Rslaves(needlog=TRUE)

tic <- Sys.time()

results <- eval(
                parse(
                      text=paste(
                        "mif.farm(",
                        "joblist=unfinished,",
                        "solib=solib,",
                        paste(args,collapse=","),
                        ")",
                        sep=""
                        )
                      )
                )

toc <- Sys.time()
print(toc-tic)

mpi.close.Rslaves()
mpi.exit()

write.csv(results$mle,file=mlefile,na='',row.names=F)
with(results,save(finished,err,file=imagefile))

  }
}
\keyword{programming}
\keyword{utilities}
