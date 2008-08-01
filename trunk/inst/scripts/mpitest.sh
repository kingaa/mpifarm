#!/bin/sh
#$ -N mpitest
#$ -cwd
#$ -j y
#$ -S /bin/bash
#$ -v LD_LIBRARY_PATH=/apps/lam711/gnu/lib

export PATH=$SGE_O_PATH


/apps/R271/gnu/bin/Rscript --vanilla mpitest.R
