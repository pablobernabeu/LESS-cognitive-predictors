#!/bin/bash
# =============================================================================
# 06_summaries.slurm  --  pool diagnostics/summaries; derive attainment + reliability (ARC)
# Writes _pooled_convergence.csv, _pooled_posterior_summaries.csv, _attainment.csv,
# _reliability.csv, _prepost_ns.csv, _prior_specification.csv and, where the fits carry
# a per-fit record, _pooled_fit_metadata.csv into $LES_STORE/paper_2_plasticity/results,
# the tables the manuscript reads. Submit AFTER 04 + 05.
# =============================================================================
#SBATCH --job-name=p2_summaries
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem-per-cpu=8G
#SBATCH --time=04:00:00
#SBATCH -o paper_2_plasticity/hpc/logs/06_summaries.out

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_2_plasticity/hpc/logs

Rscript "paper_2_plasticity/scripts/06_summaries.R" \
    > "paper_2_plasticity/hpc/logs/06_summaries.Rout" 2>&1

echo "06 summaries finished $(date)"
