#!/bin/bash
# =============================================================================
# 09c_compare_grouped.slurm  --  participant-grouped K-fold comparison of the
# raw-band and aperiodic Part A reference models.
# -----------------------------------------------------------------------------
# Complements 09b, which compares the same two models by PSIS-LOO. That criterion
# leaves out one trial at a time, and the six predictors distinguishing the models
# are constant within a participant, so it is close to blind to what is being
# compared. This job leaves out whole participants instead. See the long note at
# the top of 09c_compare_aperiodic_grouped.R.
#
# COST, now measured from a real run rather than inferred. K refits per model, two models
# per stratum, two strata: 40 brms refits at K = 10.
#
# A refit costs about ONE HOUR. Job 12775656 logged "Chain 1 finished in 3426.1 seconds"
# and a total execution time of ~3600 s per fold, with the 4 chains running concurrently.
# That is the honest figure: 40 refits ~= 40 hours, so this belongs on `long`, not `short`.
#
# Two earlier estimates were wrong, and both mistakes are worth recording because they are
# easy to repeat:
#   1. Job 12391960 ("p2_fit_partA") completed in 18 minutes, which was read as the cost of
#      fitting the Part A set. It is not: les_brm() uses file_refit = "on_change", so that
#      run was almost entirely cache hits. A fresh fit of this model samples 32,000
#      post-warmup draws (4 chains, iter 10,000, warmup 2,000) over 26,454 observations.
#   2. brms::kfold() refits through update(), which does NOT inherit les_brm()'s cores
#      setting and defaults to getOption("mc.cores", 1), so the chains ran one after
#      another. The script now sets options(mc.cores = LES_CHAINS). That was a real 4x
#      defect, but it sat on top of a baseline that was already wrong by an order of
#      magnitude, so fixing it alone did not save the run (job 12775656 still died).
#
# The CV refits deliberately keep the production sampler settings, so the models being
# cross-validated are exactly the models the manuscript reports. Lighter refits would be
# defensible for an elpd, which is a posterior expectation, but the comparison is easier to
# defend if nothing about the fits differs.
#
# 3 days against a measured 40 h leaves ~80% headroom, which two underestimates have shown
# to be worth having. Raise LES_KFOLD_GROUPED_K only with the walltime raised to match.
# The script writes each stratum's row as soon as that stratum finishes, so a walltime kill
# during the second stratum no longer destroys the first one's result.
#
# PREREQUISITE: 09b must have cached the common-sample raw refits
# (<raw_id>_commonsample.rds). This job skips a stratum, with a message, if not.
#
# SUBMIT (standard QoS only -- never --qos=priority):
#   sbatch paper_2_plasticity/hpc/09c_compare_grouped.slurm
# =============================================================================
#SBATCH --job-name=p2_grouped_cv
#SBATCH --partition=long
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=16G
#SBATCH --time=3-00:00:00
#SBATCH -o paper_2_plasticity/hpc/logs/09c_compare_grouped_%j.out

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_2_plasticity/hpc/logs

# Job-specific R log. The fixed name this used to write was truncated by the next
# submission, which destroyed the previous run's timings -- the very measurements that
# sized this job. The slurm .out already carries %j; the R log now does too, so a failed
# run's evidence survives the attempt that replaces it.
Rscript "paper_2_plasticity/scripts/09c_compare_aperiodic_grouped.R" \
    > "paper_2_plasticity/hpc/logs/09c_compare_grouped_${SLURM_JOB_ID}.Rout" 2>&1

echo "Participant-grouped comparison finished at $(date)"
