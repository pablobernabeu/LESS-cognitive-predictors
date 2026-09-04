#!/bin/bash
# =============================================================================
# 08_projpred.slurm  --  Projection-predictive variable selection for Part A
# -----------------------------------------------------------------------------
# Runs projpred::cv_varsel on the cached Part A reference fits
# (p2_predictive_trajectory + p2_predictive_trajectory_gender), with
# PARTICIPANT-GROUPED K-fold CV and validate_search=TRUE.
#
# COST NOTE -- this is the heaviest Paper 2 job. validate_search=TRUE repeats the
# WHOLE forward search inside EVERY fold, and each search step projects the
# reference posterior onto a submodel of a trial-level Bernoulli model (tens of
# thousands of rows). Cost ~ nfolds x nterms x per-projection, and it is borne almost
# entirely by cv_varsel, which 08_projpred_selection.R runs SEQUENTIALLY: every parallel
# cv_varsel backend it tried either exhausted memory or deadlocked (see the parallel-backend
# note in that script). Hence long-partition wall time. The allocation is used by the one
# step that does parallelise, the K reference refits inside run_cvfun, over a PSOCK cluster
# sized by LES_PROJPRED_CORES.
#
# The reference fits themselves are RELOADED (brms file= cache) and never re-sampled here.
# The K fold refits inside run_cvfun do sample, but only once: they are cached to
# <model_id>_cvfits.rds, so a resubmission goes straight to the projections.
#
# Submit AFTER 04 has produced the reference fits:
#   sbatch --clusters=htc --account=educ-intract paper_2_plasticity/hpc/08_projpred.slurm
# (Standard QoS only -- never --qos=priority. See paper_2_plasticity/hpc/README.md.)
# =============================================================================
#SBATCH --job-name=p2_projpred
#SBATCH --partition=long
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=6
#SBATCH --mem-per-cpu=28G
# Wall time raised from 2 days on 2026-08-08. Two days was sized for the default
# truncated solution path (min(19, D) terms) on a single reference model. A full-length
# search over BOTH the pooled and gender-agreement reference models is far more work,
# and it is what this job now runs: 08_projpred_selection.R leaves nterms_max NULL, i.e.
# every candidate term, unless LES_PROJPRED_NTERMS is set, and nothing here sets it. Job
# 12693586 reached only ~60% of the forward search for the first of the two models after
# 47 h and was killed at the limit. The cvfits are cached,
# so a resubmission does not repeat the expensive K refits, but cv_varsel itself restarts.
# Seven days leaves headroom for both models without another timeout.
#SBATCH --time=7-00:00:00
#SBATCH -o paper_2_plasticity/hpc/logs/08_projpred.out

# Memory: earlier runs OOM'd because a parallel cv_varsel gave every worker its own copy
# of the reference model + K-fold cvfits (tens of GB each). cv_varsel is now sequential, so
# its footprint is one projection at a time, and the parallel step that remains, run_cvfun's
# K refits over a PSOCK cluster, is what 6 cores x 28G = 168G is sized for. Fewer, fatter
# cores are the right shape here: each PSOCK worker carries a full copy.

source _shared/hpc/arc_env.sh
set -o errexit
set -o nounset
mkdir -p paper_2_plasticity/hpc/logs

# Sizes the PSOCK cluster for run_cvfun's K reference refits. cv_varsel ignores it and
# runs sequentially.
export LES_PROJPRED_CORES="${SLURM_CPUS_PER_TASK:-6}"
export LES_PROJPRED_NFOLDS="${LES_PROJPRED_NFOLDS:-10}"    # grouped 10-fold (over participants)
export LES_PROJPRED_NDRAWS="${LES_PROJPRED_NDRAWS:-20}"    # clustered projection draws for the search

# Forward any arguments through to the script, which accepts "pooled", "gender",
# "aperiodic" and "aperiodic_gender" and runs every stratum when given none. Without
# this the slurm file could only ever run the full set, so a single missing stratum
# could not be filled in without re-running the ones that already exist -- and at
# roughly two days per reference model that is the difference between a job that
# finishes and one that hits its wall part-way through the first model.
#   sbatch paper_2_plasticity/hpc/08_projpred.slurm gender
STRATA=("$@")
# Build the log suffix in its own step: a nested substitution inside ${x:+...} is not
# applied, so joining the array there leaves a space in the filename when more than
# one stratum is given.
LOG_SUFFIX=""
if [ "${#STRATA[@]}" -gt 0 ]; then
  LOG_SUFFIX="_$(IFS=_; echo "${STRATA[*]}")"
fi
echo "[08] strata requested: ${STRATA[*]:-<all>}"
Rscript "paper_2_plasticity/scripts/08_projpred_selection.R" "${STRATA[@]}" \
    > "paper_2_plasticity/hpc/logs/08_projpred${LOG_SUFFIX}.Rout" 2>&1

echo "08 projpred selection finished $(date)"
