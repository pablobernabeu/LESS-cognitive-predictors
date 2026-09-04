# =============================================================================
# paper_2_plasticity/scripts/06_summaries.R
# Phase 3c -- Pool diagnostics/summaries; derive ATTAINMENT and reliability  [HPC]
# =============================================================================
#
# After the models in steps 04-05 have been fitted on the HPC, this script collates
# their artefacts into the tables the manuscript reads, and derives the two
# quantities the dedicated methods review flagged as required:
#   (1) pooled convergence gate    -> results/_pooled_convergence.csv
#   (2) pooled posterior summaries -> results/_pooled_posterior_summaries.csv
#   (3) end-of-training ATTAINMENT -> results/_attainment.csv
#   (4) rate/intercept RELIABILITY -> results/_reliability.csv
# (3) and (4) are derived for the two raw-band Part A fits only (pooled and gender-only);
# the de-confounded specparam variants are not covered here.
#
# ATTAINMENT (Part A): the model gives the learning RATE (the z_session_time slope and
# its predictor interactions); ATTAINMENT is the complementary endpoint quantity -- the
# model-implied accuracy at the END of training (max z_session_time), obtained by
# posterior prediction (brms::posterior_epred, population level), reported as a posterior
# median + 95% CrI. Reporting both rate and attainment follows the review's recommendation,
# since attainment is often the more reliable individual-difference outcome.
#
# RELIABILITY: the review (Hedge, Powell & Sumner 2018, doi:10.3758/s13428-017-0935-1;
# Hedge 2021, doi:10.5334/joc.169) requires the by-participant learning rate/intercept to
# be shown reliable before being interpreted as individual differences. We report the
# empirical-Bayes reliability of each by-participant random effect,
#     reliability = Var(E[u_i | data]) / tau^2,
# the variance of the shrunken by-participant posterior means relative to tau^2, the
# model's between-participant variance for that effect. The note at slope_reliability()
# below records why this replaced the earlier tau^2 / (tau^2 + mean_i SE_i^2) form. Either
# way this is a single-occasion estimate; a formal test-retest value would need a second
# study wave.
#
# The two effects reported are the by-participant random intercept and the z_session_time
# slope. Because z_session_time is z-scored in 02, the intercept is a participant's level
# at the MEAN session, which is not the end-of-training attainment of (3) above (that is
# evaluated at the maximum session).
# =============================================================================

suppressPackageStartupMessages({
  source(here::here("_shared", "R", "00_paths.R"))
  source(here::here("_shared", "R", "02_diagnostics.R"))
  source(here::here("paper_2_plasticity", "scripts", "_config.R"))
  library(dplyr)
})

# --- (1)+(2) Pool the per-model artefacts -------------------------------------
pool_artefacts <- function() {
  conv_files <- list.files(paper2_results(), pattern = "_convergence\\.rds$", full.names = TRUE)
  summ_files <- list.files(paper2_results(), pattern = "_summary\\.rds$",     full.names = TRUE)
  if (length(conv_files)) {
    # Take the model name from the FILENAME, as the summary pooling below already does.
    # The name stored inside the .rds is the `label` passed at fit time, and the
    # weakly-informative sensitivity fits were labelled with their base model's name.
    # Binding those as-is produced a table with the same model listed twice, carrying
    # different diagnostics and no way to tell which row was the sensitivity fit.
    conv <- dplyr::bind_rows(lapply(conv_files, function(f) {
      d <- readRDS(f); d$model <- sub("_convergence\\.rds$", "", basename(f)); d
    }))
    utils::write.csv(conv, paper2_results("_pooled_convergence.csv"), row.names = FALSE)
    message("[pool] convergence: ", sum(conv$passed, na.rm = TRUE), "/", nrow(conv), " models passed")
  }
  if (length(summ_files)) {
    summ <- dplyr::bind_rows(lapply(summ_files, function(f) {
      d <- readRDS(f); d$model <- sub("_summary\\.rds$", "", basename(f)); d
    }))
    utils::write.csv(summ, paper2_results("_pooled_posterior_summaries.csv"), row.names = FALSE)
    message("[pool] posterior summaries pooled for ", length(summ_files), " models")
  }
}

.les_predictor_cols <- c("z_digit_span", "z_stroop", "z_asrt",
                         "z_alpha", "z_theta", "z_beta", "z_delta", "z_gamma", "z_iaf")

# --- (3) End-of-training attainment from each Part A fit -----------------------
derive_attainment <- function() {
  rows <- list()
  for (mid in c(LES_P2_MODELS[["predictive"]], LES_P2_MODELS[["predictive_gender"]])) {
    ffit <- paper2_results(paste0(mid, ".rds"))
    if (!file.exists(ffit)) next
    fit <- readRDS(ffit)
    d   <- fit$data
    nd  <- data.frame(z_session_time = max(d$z_session_time, na.rm = TRUE))
    for (p in intersect(.les_predictor_cols, names(d))) nd[[p]] <- 0          # predictors at their mean
    if ("grammatical_property" %in% names(d))
      nd <- merge(nd, data.frame(grammatical_property = unique(d$grammatical_property)))
    ep  <- brms::posterior_epred(fit, newdata = nd, re_formula = NA, allow_new_levels = TRUE)
    att <- rowMeans(ep)                                                       # average over properties
    rows[[mid]] <- data.frame(
      model = mid, quantity = "end_training_attainment_accuracy",
      median = stats::median(att),
      ci_low = stats::quantile(att, .025, names = FALSE),
      ci_high = stats::quantile(att, .975, names = FALSE)
    )
  }
  if (length(rows)) {
    res <- do.call(rbind, rows)
    utils::write.csv(res, paper2_results("_attainment.csv"), row.names = FALSE)
    message("[attainment] wrote ", nrow(res), " row(s)")
    invisible(res)
  }
}

# --- (4) Empirical-Bayes reliability of by-participant rate + intercept --------
slope_reliability <- function() {
  rows <- list()
  for (mid in c(LES_P2_MODELS[["predictive"]], LES_P2_MODELS[["predictive_gender"]])) {
    ffit <- paper2_results(paste0(mid, ".rds"))
    if (!file.exists(ffit)) next
    fit <- readRDS(ffit)
    re  <- brms::ranef(fit)$participant_lab_ID            # [participant, stat, term]
    sdc <- brms::VarCorr(fit)$participant_lab_ID$sd       # group-level SDs (Estimate, ...)
    for (term in dimnames(re)[[3]]) {
      se  <- re[, "Est.Error", term]   # posterior SD of each shrunken deviation u_i
      ui  <- re[, "Estimate",  term]   # posterior mean of each by-participant deviation
      tau <- sdc[term, "Estimate"]     # between-participant (group-level) SD
      rows[[paste(mid, term)]] <- data.frame(
        model = mid, effect = term, group_sd = tau,
        mean_posterior_se = mean(se, na.rm = TRUE),
        # Reliability = the between-participant signal the model actually recovers:
        # the variance of the shrunken posterior-mean deviations relative to the model's
        # total between-participant variance, Var(E[u_i | data]) / tau^2. The previous
        # form tau^2 / (tau^2 + mean(se^2)) substituted the posterior SD of the *shrunken*
        # effect for the sampling SE and so systematically overstated reliability (it is
        # second-order when reliability is high but material when it is not: the gender-only
        # learning rate falls from ~.64 to ~.44 under the correct expression). This ratio is
        # the normal-theory identity reliability = 1 - E[Var(u_i | data)] / tau^2, computed
        # here from the posterior means so it remains valid for the Bernoulli GLMM with a
        # correlated intercept-slope random-effects structure.
        reliability = stats::var(ui, na.rm = TRUE) / tau^2
      )
    }
  }
  if (length(rows)) {
    res <- do.call(rbind, rows)
    utils::write.csv(res, paper2_results("_reliability.csv"), row.names = FALSE)
    message("[reliability] wrote ", nrow(res), " row(s)")
    invisible(res)
  }
}

# --- (5) Fitted-sample sizes for the Part B pre/post models --------------------
# The Methods must report the n each pre/post model was actually fitted on (which
# differs by measure, because missingness is per index), and the manuscript's rule
# is that no count is transcribed. One row per model x session: participants and
# observations, taken from each fit's own data slot so the reported n can never
# diverge from what the sampler saw.
prepost_ns <- function() {
  files <- list.files(paper2_results(), pattern = "^p2_cognition_prepost.*\\.rds$",
                      full.names = TRUE)
  files <- files[!grepl("_(convergence|summary)\\.rds$", files)]
  if (!length(files)) { message("[prepost-ns] no pre/post fits found -- skipped"); return(invisible(NULL)) }
  rows <- lapply(files, function(f) {
    fit <- readRDS(f)
    d <- fit$data
    if (is.null(d) || !all(c("session_prepost", "participant_lab_ID") %in% names(d))) return(NULL)
    ag <- aggregate(list(n_obs = d$participant_lab_ID),
                    by = list(session_prepost = d$session_prepost), FUN = length)
    np <- aggregate(list(n_participants = d$participant_lab_ID),
                    by = list(session_prepost = d$session_prepost),
                    FUN = function(x) length(unique(x)))
    m <- merge(ag, np, by = "session_prepost")
    m$model <- sub("\\.rds$", "", basename(f))
    m$session <- ifelse(m$session_prepost < 0, "pre", "post")
    m[, c("model", "session", "n_participants", "n_obs")]
  })
  res <- do.call(rbind, Filter(Negate(is.null), rows))
  if (!is.null(res)) {
    utils::write.csv(res, paper2_results("_prepost_ns.csv"), row.names = FALSE)
    message("[prepost-ns] wrote ", nrow(res), " row(s)")
  }
  invisible(res)
}

# --- (6) Realised prior specification, one row per model x prior ----------------
# Written from brms::prior_summary() on the stored fits, so the Methods' prior
# prose can be checked (or injected) against what the sampler actually used, and a
# prior change in the fit scripts can never silently falsify the manuscript.
prior_specification <- function() {
  # Enumerate models from the pooled-convergence artefact rather than globbing
  # p2_*.rds: the results directory also holds cached cross-validation objects
  # (each carrying ten refitted models), and loading those exhausts the job's
  # memory (job 12820185 died OUT_OF_MEMORY doing exactly that). Fits are
  # loaded one at a time and freed before the next.
  conv <- paper2_results("_pooled_convergence.csv")
  if (!file.exists(conv)) {
    message("[prior-spec] no pooled convergence yet -- skipped")
    return(invisible(NULL))
  }
  models <- unique(utils::read.csv(conv, stringsAsFactors = FALSE)$model)
  rows <- lapply(models, function(m) {
    f <- paper2_results(paste0(m, ".rds"))
    if (!file.exists(f)) return(NULL)
    fit <- try(readRDS(f), silent = TRUE)
    if (inherits(fit, "try-error") || !inherits(fit, "brmsfit")) return(NULL)
    pr <- as.data.frame(brms::prior_summary(fit))
    pr$model <- m
    rm(fit); invisible(gc(verbose = FALSE))
    pr
  })
  res <- do.call(rbind, Filter(Negate(is.null), rows))
  if (!is.null(res) && nrow(res)) {
    utils::write.csv(res, paper2_results("_prior_specification.csv"), row.names = FALSE)
    message("[prior-spec] wrote ", nrow(res), " row(s) across ",
            length(unique(res$model)), " model(s)")
  }
  invisible(res)
}

# =============================================================================
.run <- function() {
  pool_artefacts()
  derive_attainment()
  slope_reliability()
  prepost_ns()
  prior_specification()
  message("[p2-summaries] done.")
}

if (sys.nframe() == 0L) .run()
