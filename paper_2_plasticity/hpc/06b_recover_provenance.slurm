#!/bin/bash
# =============================================================================
# 06b_recover_provenance.slurm  --  Recover results/_provenance.csv from the fitted objects
# -----------------------------------------------------------------------------
# Post-processing only. Reads the four Part A brmsfit objects for their version stamps
# and the R version in their serialisation headers, and writes the provenance record the
# manuscript injects. No sampling, no refit; runs in minutes. The largest object read is
# about 40 MB. The next completed run of 04_fit_predictors.slurm overwrites the file with
# a record written at fit time.
#
#   sbatch --clusters=htc --account=educ-intract paper_2_plasticity/hpc/06b_recover_provenance.slurm
# (Standard QoS only -- never --qos=priority.)
# =============================================================================
#SBATCH --job-name=p2_recover_provenance
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=8G
#SBATCH --time=00:20:00
#SBATCH -o paper_2_plasticity/hpc/logs/06b_recover_provenance.out

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_2_plasticity/hpc/logs

Rscript "paper_2_plasticity/scripts/06b_recover_provenance.R" \
    > "paper_2_plasticity/hpc/logs/06b_recover_provenance.Rout" 2>&1

echo "06b provenance recovery finished $(date)"
