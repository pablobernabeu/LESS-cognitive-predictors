# =============================================================================
# 06_helpers.R  --  Small helpers shared by the two paper pipelines
# =============================================================================
#
# WHAT THIS PROVIDES
#   les_zscore()             standardise a numeric vector, with the treatment of an
#                            all-NA input chosen at the call site
#   les_participant_folds()  participant-grouped fold ids for cross-validation
#
# The paper scripts source this file with source(here::here("_shared", "R", "06_helpers.R"))
# after _config.R has set the project root. les_participant_folds() takes its default
# seed from LES_SEED, which 01_bayesian_settings.R defines, so that module has to be
# sourced first wherever the default is relied on.
# =============================================================================

# -----------------------------------------------------------------------------
# les_zscore()  --  z-score a numeric vector
# -----------------------------------------------------------------------------
# Returns as.numeric(scale(x)). A vector with zero or undefined SD returns zeros, so a
# predictor without variance enters a model as a constant column and never as NaN. An
# all-NA vector is the one case the two papers treat differently. Paper 1 keeps it NA
# (`all_na = "na"`, the default), so a missing measure stays missing. Paper 2 passes
# `all_na = "zero"` and receives zeros, which is what its scripts do with such a column.
# The choice is made at the call site so that it is visible there.
les_zscore <- function(x, all_na = c("na", "zero")) {
  all_na <- match.arg(all_na)
  if (all(is.na(x))) return(if (all_na == "na") as.numeric(x) else rep(0, length(x)))
  s <- stats::sd(x, na.rm = TRUE)
  if (is.na(s) || s == 0) return(rep(0, length(x)))
  as.numeric(scale(x))
}

# -----------------------------------------------------------------------------
# Build a participant-level fold id aligned to the reference model's data rows.
# -----------------------------------------------------------------------------
# Every row of a given participant_lab_ID gets the SAME fold, so no participant's
# trials straddle the train/test boundary (grouped K-fold; Roberts et al. 2017).
# Participants (not rows) are shuffled into K balanced groups with a fixed seed.
les_participant_folds <- function(dat, k, seed = LES_SEED) {
  if (!"participant_lab_ID" %in% names(dat)) {
    stop("[projpred] reference-model data has no participant_lab_ID column.")
  }
  ids <- as.character(dat$participant_lab_ID)
  uid <- unique(ids)
  n_p <- length(uid)
  if (n_p < 2L) stop("[projpred] need >= 2 participants for grouped CV; found ", n_p)
  k <- min(k, n_p)                       # never more folds than participants
  set.seed(seed)
  # Round-robin assignment over a shuffled participant list -> near-equal fold sizes:
  # shuffle the participants, then deal them out 1..k, 1..k, ... so folds differ by
  # at most one participant. Every row of a participant inherits that participant's fold.
  perm   <- sample(uid)
  p_fold <- setNames(((seq_len(n_p) - 1L) %% k) + 1L, perm)
  folds  <- unname(p_fold[ids])
  list(folds = as.integer(folds), k = k, n_participants = n_p,
       fold_sizes = as.integer(table(factor(p_fold, levels = seq_len(k)))))
}
