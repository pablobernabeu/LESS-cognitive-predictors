# =============================================================================
# 09c_compare_aperiodic_grouped.R
# -----------------------------------------------------------------------------
# Raw band power vs. aperiodic Part A reference model, compared by
# PARTICIPANT-GROUPED K-fold cross-validation on the common sample.
#
# WHY THIS EXISTS: the estimand, not the arithmetic
# -------------------------------------------------
# 09b already makes the comparison *valid*, by refitting the raw-band model on the
# aperiodic model's participants so both are scored on identical observations. What it
# cannot fix is that its criterion is PSIS-LOO, which leaves out one TRIAL at a time.
#
# The two models differ only in six resting-state predictors, and every one of those is
# constant within a participant (09b builds them with distinct(participant_lab_ID), so
# the code itself depends on that). Holding out a single trial therefore leaves the other
# ~528 trials of the same participant in the training set, and those carry that
# participant's resting-state values exactly. The held-out trial's neural predictors are
# effectively already known, so the comparison is close to blind to the thing under test:
# it would return a near-zero difference for informative and uninformative neural
# predictors alike. The measured differences behave accordingly -- 0.25 (SE 0.52) pooled
# and -0.15 (SE 0.99) gender, about 0.00001 nats per observation. That is a precise
# answer to the wrong question.
#
# Leaving out a whole PARTICIPANT removes their resting-state values from training
# altogether, so the model must predict that participant's learning trajectory from
# neural characteristics it has never seen. That is the quantity the manuscript's claim
# is about, and it is what grouped CV estimates (Roberts et al., 2017,
# doi:10.1111/ecog.02881, on dependence structure in CV; Vehtari, Gelman & Gabry, 2017,
# doi:10.1007/s11222-016-9696-4, for elpd and its standard error).
#
# WHY NOT REUSE THE PROJPRED cvfits
# ----------------------------------
# 08_projpred_selection.R already caches K genuine participant-grouped refits per
# reference model (<model>_cvfits.rds). They cannot be used for THIS comparison: the raw
# and aperiodic reference models are fit to different samples (56 vs 50 participants),
# which is the whole reason 09b exists, so their cvfits rest on different rows and on
# different fold assignments. A comparison needs both models refit on the SAME rows under
# the SAME folds, which is what this script does.
#
# WHAT IT COSTS
# -------------
# K refits per model, 2 models per stratum. The Part A models fit in a few minutes each,
# so K = 10 over two strata is ~40 refits. brms::kfold() runs them sequentially within a
# stratum; the walltime in the slurm header is sized from that.
#
# RELATION TO THE OTHER TWO SCRIPTS
# ----------------------------------
#   09  -- superseded, invalid (different samples). Do not run.
#   09b -- valid but leave-one-TRIAL-out. Still reported; this script complements it.
#   09c -- this one: leave-participants-out. Writes a SEPARATE artefact so neither
#          overwrites the other and the manuscript can report both criteria.
#
# Outputs:
#   results/_aperiodic_kfold_compare.csv   one row per stratum:
#     elpd_diff_aperiodic_minus_raw, se_diff, preferred_model, k, n_obs, n_participants.
#
# Submit AFTER 09b has cached the common-sample raw refits:
#   sbatch paper_2_plasticity/hpc/09c_compare_grouped.slurm
# (Standard QoS only -- never --qos=priority.)
# =============================================================================

suppressPackageStartupMessages({
  source(here::here("_shared", "R", "00_paths.R"))
  source(here::here("_shared", "R", "01_bayesian_settings.R"))
  source(here::here("paper_2_plasticity", "scripts", "_config.R"))
  library(brms)
  library(dplyr)
})

# Folds over participants. Default 10, matching LES_PROJPRED_NFOLDS so the grouped
# criterion here and the grouped search in 08 partition at the same granularity.
LES_KFOLD_GROUPED_K <- as.integer(Sys.getenv("LES_KFOLD_GROUPED_K", unset = "10"))

# Run the four chains of each refit CONCURRENTLY. les_brm() sets cores = LES_CHAINS for
# the original fits, but brms::kfold() refits through update(), whose default is
# cores = getOption("mc.cores", 1) -- so without this the chains run one after another and
# every refit costs four times what it should. Measured on the first attempt (job
# 12769193): ~18 min per refit sequentially, against ~4.5 min for a single chain, and the
# pooled stratum alone consumed a 6-hour allocation. With 8 CPUs and 2 threads per chain,
# 4 chains x 2 threads exactly fills the request.
options(mc.cores = LES_CHAINS)

# Same construction as 08_projpred_selection.R: every row of a participant gets the same
# fold, participants dealt round-robin over a seeded shuffle so folds differ by at most
# one participant. Duplicated here rather than sourced because 08 runs a long selection
# on load; the two must stay in step, so any change belongs in both.
.les_participant_folds <- function(dat, k, seed = LES_SEED) {
  if (!"participant_lab_ID" %in% names(dat)) {
    stop("[grouped-cv] model data has no participant_lab_ID column.")
  }
  ids <- as.character(dat$participant_lab_ID)
  uid <- unique(ids)
  n_p <- length(uid)
  if (n_p < 2L) stop("[grouped-cv] need >= 2 participants; found ", n_p)
  k <- min(k, n_p)
  set.seed(seed)
  perm   <- sample(uid)
  p_fold <- setNames(((seq_len(n_p) - 1L) %% k) + 1L, perm)
  list(folds = as.integer(unname(p_fold[ids])), k = k, n_participants = n_p)
}

compare_grouped <- function(stratum, raw_id, aper_id) {
  raw_common_cache <- paper2_results(paste0(raw_id, "_commonsample"))
  aper_cache       <- paper2_results(aper_id)
  if (!file.exists(paste0(raw_common_cache, ".rds"))) {
    message("[grouped-cv] ", stratum, ": no common-sample raw refit -- run 09b first. Skipping.")
    return(NULL)
  }
  if (!file.exists(paste0(aper_cache, ".rds"))) {
    message("[grouped-cv] ", stratum, ": aperiodic fit missing -- skipping.")
    return(NULL)
  }
  fit_raw  <- brms::brm(file = raw_common_cache)
  fit_aper <- brms::brm(file = aper_cache)

  # 09b built the common frame from fit_aper$data, preserving its row order, and fit the
  # raw model to exactly that. Both models therefore hold the same rows in the same order,
  # which is what lets one fold vector serve both and what makes elpd_diff pointwise
  # meaningful. Assert it rather than trust it: a silent mismatch here would produce a
  # number that looks fine and means nothing.
  stopifnot(nrow(fit_raw$data) == nrow(fit_aper$data))
  stopifnot(identical(as.character(fit_raw$data$participant_lab_ID),
                      as.character(fit_aper$data$participant_lab_ID)))

  fd <- .les_participant_folds(fit_aper$data, LES_KFOLD_GROUPED_K)
  message(sprintf("[grouped-cv] %s: K = %d over %d participants, %d rows",
                  stratum, fd$k, fd$n_participants, nrow(fit_aper$data)))

  # kfold() refits the model K times, each time holding out one fold of PARTICIPANTS.
  # The returned object is cached: each call costs ~10 hours, and the first attempt at this
  # comparison was killed twice by the scheduler. Caching means an interrupted run resumes
  # at the model boundary instead of starting over. The cache carries the fold vector it was
  # built from, so a changed fold assignment can never be silently reused.
  kf_cached <- function(fit, tag) {
    f <- paper2_results(paste0("_kfold_", tag))
    if (file.exists(paste0(f, ".rds"))) {
      ck <- try(readRDS(paste0(f, ".rds")), silent = TRUE)
      if (!inherits(ck, "try-error") && identical(ck$folds, fd$folds)) {
        message("[grouped-cv] ", tag, ": resumed from cached kfold")
        return(ck$kf)
      }
      message("[grouped-cv] ", tag, ": cached kfold ignored (folds changed); recomputing")
    }
    kf <- brms::kfold(fit, folds = fd$folds, save_fits = FALSE)
    saveRDS(list(kf = kf, folds = fd$folds), paste0(f, ".rds"))
    kf
  }
  kf_raw  <- kf_cached(fit_raw,  paste0(raw_id, "_commonsample"))
  kf_aper <- kf_cached(fit_aper, aper_id)

  cmp <- loo::loo_compare(list(raw = kf_raw, aperiodic = kf_aper))
  rn <- rownames(cmp)
  raw_row <- cmp[rn == "raw", , drop = FALSE]
  ap_row  <- cmp[rn == "aperiodic", , drop = FALSE]
  # loo_compare zeroes the better row, so the other row's own elpd_diff is the contrast.
  elpd_diff <- ap_row[, "elpd_diff"] - raw_row[, "elpd_diff"]
  se_naive  <- max(raw_row[, "se_diff"], ap_row[, "se_diff"])

  # --- Participant-clustered standard error -----------------------------------
  # loo_compare's SE treats the pointwise differences as independent. Under grouped CV they
  # are not: each participant contributes ~500 trials that share that participant's neural
  # predictors, their random intercept and their random slope, so the effective sample size
  # is the number of participants, not the number of trials. The naive SE is therefore
  # optimistic, by roughly the square root of the design effect, and reporting the raw ratio
  # would overstate the evidence.
  #
  # Summing the pointwise differences within participant and taking the SE across those
  # totals is the standard cluster-robust correction: the point estimate is unchanged (the
  # sums are identical), while the uncertainty is estimated from the 50 units that are
  # actually independent. Reported alongside the naive SE rather than instead of it, so the
  # discrepancy is visible.
  .pw <- function(kf) {
    m <- kf$pointwise
    j <- grep("^elpd", colnames(m))[1]
    if (is.na(j)) stop("[grouped-cv] no elpd column in kfold pointwise output.")
    m[, j]
  }
  d_i <- .pw(kf_aper) - .pw(kf_raw)
  pid <- as.character(fit_aper$data$participant_lab_ID)
  stopifnot(length(d_i) == length(pid))
  d_p <- tapply(d_i, pid, sum)
  n_p <- length(d_p)
  se_clustered <- sqrt(n_p) * stats::sd(d_p)
  # Point estimate from the pointwise route must equal loo_compare's, up to rounding.
  stopifnot(abs(sum(d_p) - elpd_diff) < 1e-6)

  preferred <- if (abs(elpd_diff) > 2 * se_clustered) {
    if (elpd_diff > 0) "aperiodic" else "raw"
  } else {
    "neither clearly preferred (|elpd_diff| <= 2*clustered SE)"
  }

  message(sprintf(paste0("[grouped-cv] %s: elpd_diff(aperiodic-raw) = %.2f",
                         " | clustered SE %.2f (naive %.2f, design effect %.1fx) -> %s"),
                  stratum, elpd_diff, se_clustered, se_naive,
                  se_clustered / se_naive, preferred))
  data.frame(
    stratum = stratum, raw_model = paste0(raw_id, "_commonsample"),
    aperiodic_model = aper_id, criterion = "participant-grouped K-fold",
    k = fd$k, n_obs = nrow(fit_aper$data), n_participants = fd$n_participants,
    elpd_diff_aperiodic_minus_raw = elpd_diff,
    se_diff = se_clustered, se_naive_independent = se_naive,
    se_inflation_from_clustering = se_clustered / se_naive,
    preferred_model = preferred, stringsAsFactors = FALSE
  )
}

out <- paper2_results("_aperiodic_kfold_compare.csv")

# Write after EACH stratum rather than once at the end. The first attempt (job 12769193)
# hit its walltime part-way through and lost everything, because the only write came after
# both strata had finished. Each stratum is a complete, independently meaningful row, so
# there is no reason to make the second one's failure destroy the first one's result.
STRATA <- list(
  list(stratum = "pooled", raw = "p2_predictive_trajectory",
       aper = "p2_predictive_trajectory_aperiodic"),
  list(stratum = "gender", raw = "p2_predictive_trajectory_gender",
       aper = "p2_predictive_trajectory_aperiodic_gender")
)

res <- NULL
for (s in STRATA) {
  row <- compare_grouped(s$stratum, s$raw, s$aper)
  if (is.null(row)) next
  res <- dplyr::bind_rows(res, row)
  les_assert_readonly_data(out)
  utils::write.csv(res, out, row.names = FALSE)
  message("[grouped-cv] wrote ", basename(out), " (", nrow(res), " row(s) so far)")
}

if (!is.null(res) && nrow(res)) {
  print(res)
} else {
  message("[grouped-cv] nothing to write -- no strata compared.")
}
