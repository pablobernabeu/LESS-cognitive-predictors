#!/bin/bash
# =============================================================================
# 08b_recover.slurm  --  Recover projpred path CSV + summary from cached varsel
# -----------------------------------------------------------------------------
# Post-processing ONLY: loads each <model>_projpred_varsel.rds (already computed by
# the multi-day sequential cv_varsel runs) and re-extracts the solution-path CSV +
# summary via the fixed .les_projpred_path() (projpred 2.10 $perf_sub slot). No CV,
# no sampling -- runs in minutes. Sized for the ~8 GB aperiodic varsel object.
#
#   sbatch --clusters=htc --account=educ-intract paper_2_plasticity/hpc/08b_recover.slurm
# (Standard QoS only -- never --qos=priority.)
# =============================================================================
#SBATCH --job-name=p2_projpred_recover
#SBATCH --partition=short
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem-per-cpu=40G
#SBATCH --time=00:40:00
#SBATCH -o paper_2_plasticity/hpc/logs/08b_recover.out

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_2_plasticity/hpc/logs

Rscript "paper_2_plasticity/scripts/08b_recover_projpred_path.R" \
    > "paper_2_plasticity/hpc/logs/08b_recover.Rout" 2>&1

echo "08b projpred path recovery finished $(date)"
