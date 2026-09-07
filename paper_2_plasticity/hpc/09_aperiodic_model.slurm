#!/bin/bash
# =============================================================================
# 09_aperiodic_model.slurm  --  Part A de-confounded (specparam) variant + projpred
# -----------------------------------------------------------------------------
# The follow-up that actually USES the aperiodic features from 07_extract_aperiodic.R.
# In two sequential steps (one job):
#   (1) 04_fit_brms_predictors.R aperiodic aperiodic_gender
#         -> fits p2_predictive_trajectory_aperiodic (+ _gender), identical to the raw
#            Part A model except the raw rs-EEG band power is REPLACED by the specparam
#            decomposition: aperiodic exponent + offset and 1/f-adjusted theta/alpha/beta
#            oscillatory power (+ specparam IAF). Raw band power conflates periodic and
#            aperiodic (1/f) activity, so the parameterised quantities are the correct
#            neural predictors (Donoghue et al. 2020). The raw models are NOT refit.
#   (2) 08_projpred_selection.R aperiodic aperiodic_gender
#         -> projection-predictive variable selection over the de-confounded reference,
#            so the manuscript can compare which predictors carry signal under raw vs
#            1/f-adjusted parameterisation. Reloads the fits from (1) rather than
#            re-sampling them, though run_cvfun's K fold refits do sample once and are
#            then cached.
#
# Prereqs on the cluster: learning_trajectory.rds (02), 07_aperiodic_features.csv (07).
# Resourcing mirrors 04 (the Bernoulli fit: 4 chains x 2 threads = 8 CPUs) and 08, whose
# allocation goes to run_cvfun's K reference refits; cv_varsel itself runs sequentially.
# Standard QoS only.
#
# Submit AFTER 07 has produced the aperiodic CSV:
#   sbatch --clusters=htc --account=educ-intract paper_2_plasticity/hpc/09_aperiodic_model.slurm
# =============================================================================
#SBATCH --job-name=p2_aperiodic_model
#SBATCH --partition=long
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=12G
#SBATCH --time=3-00:00:00
#SBATCH -o paper_2_plasticity/hpc/logs/09_aperiodic_model.out

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_2_plasticity/hpc/logs

export LES_THREADS_PER_CHAIN=2                              # 4 chains x 2 = 8 CPUs (fit step)
export LES_PROJPRED_CORES="${SLURM_CPUS_PER_TASK:-8}"       # PSOCK cluster for run_cvfun
# Ten participant-grouped folds by default, the same default as 08_projpred.slurm, so the
# raw-band and aperiodic selections partition at the same granularity. The reported
# aperiodic selection ran with ten; the script prints the count it uses to the job log
# and records it in <model>_projpred_summary.rds.
export LES_PROJPRED_NFOLDS="${LES_PROJPRED_NFOLDS:-10}"
export LES_PROJPRED_NDRAWS="${LES_PROJPRED_NDRAWS:-20}"

echo "[aperiodic-model] (1) fitting de-confounded Part A variants | start $(date)"
Rscript "paper_2_plasticity/scripts/04_fit_brms_predictors.R" aperiodic aperiodic_gender \
    > "paper_2_plasticity/hpc/logs/09_fit_aperiodic.Rout" 2>&1

echo "[aperiodic-model] (2) projpred over the de-confounded reference | $(date)"
Rscript "paper_2_plasticity/scripts/08_projpred_selection.R" aperiodic aperiodic_gender \
    > "paper_2_plasticity/hpc/logs/09_projpred_aperiodic.Rout" 2>&1

echo "[aperiodic-model] finished $(date)"
