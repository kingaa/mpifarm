#!/bin/sh
#$ -N simple
#$ -cwd
#$ -j y
#$ -S /bin/bash
#$ -q fast.q@@*
#$ -v LD_LIBRARY_PATH=/apps/lam711/gnu/lib

export PATH=$SGE_O_PATH

R_EXE='/apps/R271/gnu/bin/Rscript --vanilla'
WORKDIR=$SGE_O_WORKDIR
NCPU=$NSLOTS

$R_EXE job.R nper=100 nrand=10000
