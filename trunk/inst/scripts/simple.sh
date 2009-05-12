#!/bin/sh
#PBS -N simple
#PBS -l nodes=18:ppn=4
#PBS -S /bin/bash

RSCRIPT='/apps/R281/bin/Rscript --vanilla'

cd $PBS_O_WORKDIR
lamboot -v $PBS_NODEFILE
$RSCRIPT simple.R nper=100 nrand=10000
lamhalt -v
