#! /usr/local/bin/Rscript --vanilla

## a script for running multiple MIFs using Rmpi and mpifarm

jobname <- NULL           # this must be set by a commandline argument

## get, parse, and evaluate the command-line arguments
args <- commandArgs(trailingOnly=TRUE)
eval(parse(text=args))

if (is.null(jobname))
  stop("you must supply a ",sQuote("jobname"))

## the following cannot be changed by commandline arguments
imagefile <- paste('image_',jobname,'.rda',sep='') # binary file for saving the workspace
mpfile <- paste('modelparams_',jobname,'.csv',sep='') # input parameter file
mlefile <- paste('mle_',jobname,'.csv',sep='') # MLEs are to be saved here
modelRfile <- paste(modelStem,".R",sep='')

require(Rmpi)
require(mpifarm)
require(pomp)

source(modelRfile)         # model-specific codes, loading data, etc.

if (!exists("make.pomp"))
  stop("file ",sQuote(modelRfile)," does not define ",sQuote("make.pomp")," as it should")
if (!exists("solib"))
  solib <- NULL

if (file.exists(imagefile)) {   # we are continuing where we left off?

  load(imagefile)

} else {                                # we are starting from scratch

  ## read the input parameter file
  parameters <- read.csv(file=mpfile)   
  ## random-walks and initial displacements are to be multiplicative
  unfinished <- eval(
                     parse(
                           text=paste(
                             "mif.farm.joblist(",
                             "parameters=parameters,",
                             "make.pomp=make.pomp,",
                             paste(args,collapse=','),
                             ")",
                             sep=""
                             )
                           )
                     )

  save(unfinished,file=imagefile)
}

mpi.spawn.Rslaves(needlog=F)

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

q(save='no',status=0)
