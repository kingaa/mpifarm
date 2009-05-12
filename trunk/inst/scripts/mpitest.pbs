#!/bin/sh
#PBS -N mpitest
#PBS -l nodes=18:ppn=4
#PBS -S /bin/bash

RSCRIPT='/apps/R281/bin/Rscript --vanilla'

cd $PBS_O_WORKDIR
lamboot -v $PBS_NODEFILE
$RSCRIPT mpitest.R
lamhalt -v
