# =============================================================================
# paper_2_plasticity/manuscript_setup.R  --  Results loading and reporting helpers
# =============================================================================
#
# Sourced by the setup chunk of paper_2_neuroplasticity.qmd and by supplement.qmd, after
# _shared/R/00_paths.R, scripts/_config.R, _shared/R/05_funnel.R and
# _shared/R/06_manuscript_helpers.R, so that the two documents read the same artefacts
# through the same accessors. Render-anytime: before the HPC models exist every accessor
# returns a clearly marked placeholder; once results/_pooled_*.csv are present every
# number is populated from those artefacts (Marwick, Boettiger & Mullen, 2018,
# https://doi.org/10.1080/00031305.2017.1375986). The shared helpers this file relies on
# (.read_csv_if, apa_num, prov, flow_n, pstat, les_theme, les_div) come from
# 06_manuscript_helpers.R; LES_FIG_BASE_SIZE and has_depictr are set by the setup chunk.
# =============================================================================

# --- Collinearity among the Part A baseline predictors -------------------------
# The band powers are entered simultaneously, so each coefficient is a partial effect.
# Variance inflation factors quantify how much that costs in precision, and are computed
# here from the actual predictor frame rather than transcribed. VIF_j = 1/(1 - R^2_j) from
# regressing predictor j on the others; sqrt(VIF) is the factor by which the coefficient's
# interval is widened relative to an orthogonal predictor.
# Computed lazily on first use and then cached, so this does not depend on being placed
# after the CSV loaders below.
.les_vif_cache <- NULL
.les_vif_n     <- NULL   # participants in the complete-case frame the factors are computed on
.les_vif <- function() {
  if (!is.null(.les_vif_cache)) return(.les_vif_cache)
  f <- paper2_results("_predictor_values.csv")
  if (!file.exists(f)) return(NULL)
  pv <- utils::read.csv(f, stringsAsFactors = FALSE)
  w <- stats::reshape(pv, idvar = "participant_lab_ID", timevar = "predictor",
                      direction = "wide")
  names(w) <- sub("^value[.]", "", names(w))
  keep <- intersect(c("digit_span", "stroop_interference", "asrt_learning",
                      LES_P2_RS_MEASURES), names(w))
  d <- w[, keep, drop = FALSE]
  d <- d[stats::complete.cases(d), , drop = FALSE]
  if (nrow(d) < length(keep) + 2) return(NULL)
  .les_vif_n <<- nrow(d)
  v <- vapply(names(d), function(p) {
    r2 <- summary(stats::lm(stats::as.formula(paste(p, "~ .")), data = d))$r.squared
    1 / (1 - r2)
  }, numeric(1))
  .les_vif_cache <<- v
  v
}
vif_n <- function() { .les_vif(); if (is.null(.les_vif_n)) "NN" else as.character(.les_vif_n) }
vif_of <- function(p) {
  v <- .les_vif()
  if (is.null(v) || is.na(v[p])) "NN" else formatC(v[[p]], format = "f", digits = 2)
}
vif_range <- function(ps) {
  v <- .les_vif(); if (is.null(v)) return("NN")
  v <- v[intersect(ps, names(v))]; if (!length(v)) return("NN")
  paste0(formatC(min(v), format = "f", digits = 1), " to ",
         formatC(max(v), format = "f", digits = 1))
}
vif_widen <- function(ps) {
  v <- .les_vif(); if (is.null(v)) return("NN")
  v <- sqrt(v[intersect(ps, names(v))]); if (!length(v)) return("NN")
  paste0(formatC(min(v), format = "f", digits = 1), " to ",
         formatC(max(v), format = "f", digits = 1), " times")
}

post_tbl       <- .read_csv_if(paper2_results("_pooled_posterior_summaries.csv"))
conv_tbl       <- .read_csv_if(paper2_results("_pooled_convergence.csv"))
attainment_tbl <- .read_csv_if(paper2_results("_attainment.csv"))
reliability_tbl<- .read_csv_if(paper2_results("_reliability.csv"))
sens_tbl       <- .read_csv_if(paper2_results("_prior_sensitivity.csv"))
results_ready  <- !is.null(post_tbl)

# --- Raw-data descriptives shared with Paper 1 (participant flow + demographics,
# written by paper_1_transfer/scripts/00_extract_participants.R to both papers'
# results/) plus Paper-2 predictor/outcome descriptives (10_extract_descriptives.R).
# Injected inline so no count, demographic or task specification is transcribed.
# flow_tbl and parts_tbl are read by the shared flow_n() and pstat().
flow_tbl        <- .read_csv_if(paper2_results("_sample_flow.csv"))
parts_tbl       <- .read_csv_if(paper2_results("_participants.csv"))
task_spec_tbl   <- .read_csv_if(paper2_results("_task_specs.csv"))
predictor_desc  <- .read_csv_if(paper2_results("_predictor_descriptives.csv"))
predictor_corr  <- .read_csv_if(paper2_results("_predictor_correlations.csv"))
psd_tbl         <- .read_csv_if(paper2_results("_resting_state_psd.csv"))
acc_traj_tbl    <- .read_csv_if(paper2_results("_accuracy_trajectory_descriptives.csv"))

# Resting-state descriptives (03/10). Carries the count of eyes-closed recordings whose
# argmax individual alpha frequency lies strictly inside the 7-13 Hz search range. The
# argmax estimator returns the lower bound of that range for a spectrum that merely decays
# across it, so a value at the bound is not necessarily a measured peak. The count of
# recordings in which the specparam decomposition fits an alpha peak is a different
# quantity and is read from that decomposition's own artefact (specparam_peak_n below).
rseeg_desc <- .read_csv_if(paper2_results("_rseeg_descriptives.csv"))
aper_feat  <- .read_csv_if(paper2_results("07_aperiodic_features.csv"))
specparam_rec_n  <- function() if (is.null(aper_feat)) "NN" else as.character(nrow(aper_feat))
specparam_peak_n <- function() {
  if (is.null(aper_feat) || !"specparam_iaf" %in% names(aper_feat)) return("NN")
  as.character(sum(!is.na(aper_feat$specparam_iaf)))
}
# Recordings in which a peak was fitted in a band: the adjusted power of a band is the
# summed height of the fitted peaks centred in it, so it is zero wherever none was fitted.
n_peak_band <- function(col) {
  if (is.null(aper_feat) || !col %in% names(aper_feat)) return("NN")
  as.character(sum(aper_feat[[col]] > 0, na.rm = TRUE))
}
rseeg_peak <- function(what = c("resolvable", "recorded"), condition_ = "eyes_closed") {
  what <- match.arg(what)
  if (is.null(rseeg_desc) ||
      !all(c("condition", "n_participants_with_resolvable_alpha_peak") %in% names(rseeg_desc)))
    return("NN")
  r <- rseeg_desc[rseeg_desc$condition == condition_ &
                    !is.na(rseeg_desc$n_participants_with_resolvable_alpha_peak), , drop = FALSE]
  if (nrow(r) < 1) return("NN")
  as.character(if (what == "resolvable")
    r$n_participants_with_resolvable_alpha_peak[1] else r$n[1])
}

# Raw pre/post means of the three cognitive indices in their own task units
# (10_extract_descriptives.R). Part B otherwise reports only standardised posteriors,
# which leaves a reader unable to see the size of the change on the measured scale.
cog_desc <- .read_csv_if(paper2_results("_cognitive_descriptives.csv"))
cog_mean <- function(index_, session_) {
  if (is.null(cog_desc)) return("NN")
  r <- cog_desc[cog_desc$index == index_ & cog_desc$session == session_, , drop = FALSE]
  if (nrow(r) != 1 || is.na(r$mean[1])) return("NN")
  apa_num(r$mean[1], digits = 1)
}

# Model identifiers of the Part B pre/post fits, composed from the ids in _config.R so
# the manuscript names a model in exactly one place: the single-index models carry the
# index as a suffix, and the joint model has its own entry in LES_P2_MODELS.
.prepost_id <- function(index) les_p2_model_id("cog_prepost", paste0("_", index))

# Per-model, per-session participant and observation counts for the Part B pre/post
# models, written by the cluster summaries job. Until that artefact lands, the
# Participants sentence prints a clearly-marked pending phrase.
prepost_tbl <- .read_csv_if(paper2_results("_prepost_ns.csv"))
prepost_n <- function(model_, session_) {
  if (is.null(prepost_tbl)) return("NN")
  r <- prepost_tbl[prepost_tbl$model == model_ & prepost_tbl$session == session_, , drop = FALSE]
  if (nrow(r) != 1 || is.na(r$n_participants[1])) return("NN")
  as.character(r$n_participants[1])
}
prepost_ns_phrase <- function() {
  if (is.null(prepost_tbl)) return("*[per-model session counts pending the summaries run]*")
  sprintf(paste0("%s at Session 1 and %s at Session 5 for digit span, %s and %s for ",
                 "Stroop interference, and %s and %s for statistical learning"),
          prepost_n(.prepost_id("digit_span"), "pre"),
          prepost_n(.prepost_id("digit_span"), "post"),
          prepost_n(.prepost_id("stroop_interference"), "pre"),
          prepost_n(.prepost_id("stroop_interference"), "post"),
          prepost_n(.prepost_id("asrt_learning"), "pre"),
          prepost_n(.prepost_id("asrt_learning"), "post"))
}

# Gamma-band retained-power fractions under the 30 Hz low-pass, from
# scripts/12_extract_gamma_attenuation.R. Injected so the attenuation quantiles are
# computed from the stored per-participant artefact rather than transcribed; written
# defensively so the prose falls back to a marked approximation if the artefact is
# absent or its columns change.
gamma_att_tbl <- .read_csv_if(paper2_results("_gamma_attenuation.csv"))
gamma_att <- function(what = c("median", "q25", "q75"),
                      col = "retained_fraction") {
  what <- match.arg(what)
  if (is.null(gamma_att_tbl) || !col %in% names(gamma_att_tbl)) return(NA_character_)
  v <- gamma_att_tbl[[col]]
  if (!length(v) || all(is.na(v))) return(NA_character_)
  q <- stats::quantile(v, c(.25, .5, .75), na.rm = TRUE)
  val <- switch(what, q25 = q[[1]], median = q[[2]], q75 = q[[3]])
  # Plain "%" (not "\\%"): the value lands in markdown prose, where Pandoc escapes it.
  paste0(formatC(100 * val, format = "f", digits = 1), "%")
}
gamma_att_ready <- function() !is.na(gamma_att("median"))
gamma_att_clause <- function() {
  if (gamma_att_ready()) {
    sprintf(paste0("the retained power across that band has a median of %s of what an ",
                   "unfiltered recording would have carried (interquartile range %s to %s), ",
                   "and no more than a median of %s even under the most permissive ",
                   "single-pass reading of the zero-phase filter"),
            gamma_att("median"), gamma_att("q25"), gamma_att("q75"),
            gamma_att("median", col = "retained_fraction_singlepass"))
  } else {
    paste0("the retained power across that band has a median of about a third of what an ",
           "unfiltered recording would have carried (interquartile range roughly a quarter ",
           "to a half) *[approximate; pending the gamma-attenuation artefact]*")
  }
}

# Companion clause: the empirically observed 30-45 Hz power relative to the
# extrapolated aperiodic background. Values far above the filter's transmission mean
# the residual band is dominated by energy the low-pass did not remove in proportion
# (mains spill, EMG, the noise floor).
gamma_att_obs_clause <- function() {
  if (!gamma_att_ready() ||
      !"observed_over_extrapolated" %in% names(gamma_att_tbl)) {
    return("*[observed-band ratio pending the gamma-attenuation artefact]*")
  }
  sprintf("a median of %s of the extrapolated background, against the %s the filter would pass",
          gamma_att("median", col = "observed_over_extrapolated"),
          gamma_att("median"))
}

# Split-half (Spearman-Brown) internal consistency of the three baseline cognitive
# predictors, from scripts/11_extract_predictor_reliability.R.
predrel_tbl <- .read_csv_if(paper2_results("_predictor_reliability.csv"))
predrel <- function(p) {
  if (is.null(predrel_tbl)) return("NN")
  r <- predrel_tbl[predrel_tbl$predictor == p, , drop = FALSE]
  if (nrow(r) != 1 || is.na(r$reliability_sb[1])) return("NN")
  sub("^0", "", formatC(r$reliability_sb[1], format = "f", digits = 2))
}
# Number of random splits behind the split-half estimates, for the appendix text.
predrel_splits <- function() {
  if (is.null(predrel_tbl) || !"n_splits" %in% names(predrel_tbl)) return("NN")
  v <- unique(predrel_tbl$n_splits)
  if (length(v) != 1L) return(paste(range(v), collapse = " to "))
  formatC(v, format = "d", big.mark = ",")
}

# Computational provenance recorded at fit time by _shared/R/04_provenance.R and read by
# the shared prov(), so the reported versions are those of the run that produced these
# results rather than of the machine rendering the document. Absent until the pipeline
# is next run.
.prov_tbl <- .read_csv_if(paper2_results("_provenance.csv"))
# How the provenance record came to exist, for the availability statement. Three states:
# absent (the placeholders print), written at fit time by script 04, or recovered from the
# fitted objects' own version stamps by 06b_recover_provenance.R, which marks the file
# with a record_source row. The sentence is emitted from the artefact so that it cannot
# describe a state the file is no longer in.
prov_record_sentence <- function() {
  if (is.null(.prov_tbl) || !nrow(.prov_tbl)) {
    return(paste0("That record has not yet been written for this paper, which is why the ",
                  "version fields under *Sampler, diagnostics and inference* print as ",
                  "pending. They populate from it automatically once the Part A predictor ",
                  "models are next fitted."))
  }
  when <- substr(.prov_tbl$recorded_utc[1], 1, 10)
  src  <- prov("record_source", fallback = "")
  if (!nzchar(src)) {
    return(paste0("It was written when those models were fitted, on ", when, ", and it ",
                  "supplies the version fields under *Sampler, diagnostics and inference*."))
  }
  fits <- prov("fits_written_utc", fallback = "")
  fits <- if (nzchar(fits)) paste0(" The fitted objects were written between ",
                                   substr(fits, 1, 10), " and ",
                                   substr(sub("^.* to ", "", fits), 1, 10), ".") else ""
  paste0("The Part A models were fitted before that mechanism was in place, so the record ",
         "was recovered from the fitted objects on ", when, ": the versions of `brms`, ",
         "`rstan`, `StanHeaders`, `cmdstanr` and CmdStan are the stamps `brms` stores in ",
         "each fitted object at fit time, the R version is the one stamped in each object's ",
         "serialisation header, and the versions of `projpred`, `loo`, `posterior` and ",
         "`bayesplot`, which leave no such stamp, are those of the pinned project library ",
         "the fits were produced from.", fits, " The record supplies the version fields ",
         "under *Sampler, diagnostics and inference*.")
}

# --- Part A projection-predictive selection paths (one per reference model) and the
# aperiodic-vs-raw PSIS-LOO comparison. Solution paths come from 08_projpred_selection.R
# (grouped 10-fold, validate_search = TRUE); the LOO comparison from
# 09b_compare_aperiodic_commonsample.R (09_compare_aperiodic.R is superseded).
# Injected so the selection ranking, suggested size and comparison verdict are read from
# stored artefacts rather than transcribed. The path files are named after the model ids.
projpath_raw  <- .read_csv_if(paper2_results(paste0(LES_P2_MODELS[["predictive"]], "_projpred_path.csv")))
projpath_aper <- .read_csv_if(paper2_results(paste0(LES_P2_MODELS[["predictive_aperiodic"]], "_projpred_path.csv")))
projpath_gender <- .read_csv_if(paper2_results(paste0(LES_P2_MODELS[["predictive_gender"]], "_projpred_path.csv")))
aper_loo_tbl  <- .read_csv_if(paper2_results("_aperiodic_loo_compare.csv"))

# The participant-grouped fold count of the projection-predictive searches, read from
# the path artefacts so the Method cannot drift from the runs. One value across every
# stratum is spelled out as a word; anything else prints a visible marker.
projpred_nfolds_word <- function() {
  k <- unique(unlist(lapply(list(projpath_raw, projpath_aper, projpath_gender), function(p)
    if (!is.null(p) && "n_folds" %in% names(p)) p$n_folds else NULL)))
  k <- k[is.finite(k)]
  if (length(k) != 1L) return("*[fold count pending the selection artefacts]*")
  # Words below ten and numerals from ten, as APA 7 asks of counts in running text.
  words <- c("one", "two", "three", "four", "five", "six", "seven", "eight", "nine")
  if (k >= 1 && k <= 9) words[k] else as.character(k)
}

# Which strata actually have a selection path on disk. The paper reports a gender-only
# reference model alongside the pooled one, so a reader is entitled to know whether the
# selection was run on both or only on the pooled stratum. Reading it from the artefacts
# rather than asserting it means the sentence becomes correct on its own once the missing
# stratum is fitted, instead of having to be remembered and edited.
projpred_strata <- function() {
  have <- c(pooled = !is.null(projpath_raw), gender = !is.null(projpath_gender))
  if (all(have)) return("both the pooled and the gender-agreement reference models")
  if (have[["pooled"]]) return("the pooled reference model only")
  if (have[["gender"]]) return("the gender-agreement reference model only")
  "neither reference model"
}
projpred_gender_caveat <- function() {
  if (!is.null(projpath_gender)) return("")
  paste0(" The gender-agreement stratum, which carries this paper's headline",
         " individual-difference claim, has not yet been through the same selection, so",
         " the ranking below should not be read as established for it.")
}

# The gender-stratum result, written only once that selection exists. It matters
# separately from the pooled one for two reasons: it is the stratum the paper's headline
# individual-difference claim rests on, and its search ran to the full candidate set, so
# the terms the pooled search never reached were actually evaluated there.
projpred_gender_result <- function() {
  if (is.null(projpath_gender)) return("")
  reached <- function(term) any(grepl(term, projpath_gender$predictor, fixed = TRUE))
  tail_terms <- reached("z_gamma") && reached("z_iaf")
  out <- sprintf(paste0(
    "The gender-agreement stratum, fitted to that property alone, gives the same answer:",
    " a suggested size of %s, with working memory again the first individual-difference",
    " predictor to enter, at step %s, and inhibitory control and statistical learning",
    " entering beyond it (steps %s and %s)."),
    proj_size(projpath_gender), proj_rank(projpath_gender, "z_digit_span"),
    proj_rank(projpath_gender, "z_stroop"), proj_rank(projpath_gender, "z_asrt"))
  if (tail_terms) {
    out <- paste0(out, sprintf(paste0(
      " That search ran over the full candidate set rather than projpred's default path",
      " length, so gamma power and the individual alpha frequency were evaluated and not",
      " truncated away, and they rank last of all (steps %s and %s). The full-length",
      " search was run only for this stratum, the one the individual-difference claim",
      " rests on. There, neither term added anything the retained predictors had missed,",
      " and how far beyond the suggested size a term lands is not interpreted."),
      proj_rank(projpath_gender, "z_gamma"), proj_rank(projpath_gender, "z_iaf")))
  }
  out
}

# Task specification value (e.g. ASRT blocks / trials-per-block) from _task_specs.csv.
task_spec <- function(task_, spec_) {
  if (is.null(task_spec_tbl)) return("NN")
  r <- task_spec_tbl[task_spec_tbl$task == task_ & task_spec_tbl$spec == spec_, , drop = FALSE]
  if (nrow(r) < 1 || is.na(r$value[1])) return("NN")
  as.character(r$value[1])
}
# By-participant reliability (.NN style) of an effect from _reliability.csv.
# (Named relv, not rel: the tbl-reliability chunk assigns a data.frame to `rel`.)
relv <- function(model_id, effect_) {
  if (is.null(reliability_tbl)) return("NN")
  r <- reliability_tbl[reliability_tbl$model == model_id & reliability_tbl$effect == effect_, , drop = FALSE]
  if (nrow(r) != 1 || is.na(r$reliability)) return("NN")
  sub("^0", "", formatC(r$reliability, format = "f", digits = 2))
}

# projpred suggested (parsimonious) size, and the forward-search step (the `size`
# column) at which a given predictor first enters the solution path.
proj_size <- function(tbl) if (is.null(tbl) || !nrow(tbl)) "NN" else as.character(tbl$suggested_size[1])
proj_n    <- function(tbl) if (is.null(tbl) || !nrow(tbl)) "NN" else as.character(tbl$n_participants[1])
proj_rank <- function(tbl, term) {
  if (is.null(tbl)) return("NN")
  w <- which(tbl$predictor == term)
  if (!length(w)) return("NN")
  as.character(tbl$size[w[1]])
}
# aperiodic-vs-raw PSIS-LOO within a stratum: the elpd difference (aperiodic - raw),
# its SE, or the preferred-model verdict. Reads _aperiodic_loo_compare.csv.
aper_loo <- function(stratum_, what = c("verdict", "elpd", "se")) {
  what <- match.arg(what)
  if (is.null(aper_loo_tbl)) return(if (what == "verdict") "*[pending LOO comparison]*" else "NN")
  r <- aper_loo_tbl[aper_loo_tbl$stratum == stratum_, , drop = FALSE]
  if (nrow(r) != 1) return("NN")
  switch(what,
    verdict = {
      p <- as.character(r$preferred_model)
      if (grepl("neither", p, ignore.case = TRUE))
        "neither parameterisation was clearly preferred (the difference was within twice its standard error)"
      else sprintf("the %s parameterisation was preferred", p)
    },
    elpd    = apa_num(r$elpd_diff_aperiodic_minus_raw, digits = 1),
    se      = apa_num(r$se_diff, digits = 1))
}
# TRUE if a stratum's |elpd_diff| <= 2*se (neither parameterisation clearly preferred).
aper_loo_tie <- function(stratum_) {
  if (is.null(aper_loo_tbl)) return(NA)
  r <- aper_loo_tbl[aper_loo_tbl$stratum == stratum_, , drop = FALSE]
  if (nrow(r) != 1) return(NA)
  abs(r$elpd_diff_aperiodic_minus_raw) <= 2 * r$se_diff
}
# Trials per participant in a stratum. This is what makes the trial-level LOO
# comparison uninformative about participant-level predictors: the more trials each
# participant contributes, the more completely their random intercept is pinned by
# their own remaining data when one trial is held out, and the less any
# between-participant predictor can add to predicting it.
aper_loo_tpp <- function(stratum_) {
  if (is.null(aper_loo_tbl)) return("NN")
  r <- aper_loo_tbl[aper_loo_tbl$stratum == stratum_, , drop = FALSE]
  if (nrow(r) != 1 || is.na(r$n_participants[1]) || r$n_participants[1] == 0) return("NN")
  as.character(round(r$n_obs[1] / r$n_participants[1]))
}

# --- Participant-grouped K-fold comparison (09c) ------------------------------
# The same two models scored by leaving out whole PARTICIPANTS rather than single trials,
# which is the criterion the question actually calls for. Its standard error is clustered
# on participants: loo_compare's own SE treats the pointwise differences as independent,
# and under grouped CV they are not, so it understates the uncertainty severalfold. The
# ratio is reported in the artefact and quoted in the text, because the corrected and
# uncorrected numbers support different conclusions and the reader is entitled to see that.
aper_kf_tbl <- .read_csv_if(paper2_results("_aperiodic_kfold_compare.csv"))
aper_kf_ready <- function() !is.null(aper_kf_tbl) && nrow(aper_kf_tbl) >= 2
aper_kf <- function(stratum_, what = c("elpd", "se", "se_naive", "inflation", "k")) {
  what <- match.arg(what)
  if (is.null(aper_kf_tbl)) return("NN")
  r <- aper_kf_tbl[aper_kf_tbl$stratum == stratum_, , drop = FALSE]
  if (nrow(r) != 1) return("NN")
  switch(what,
    elpd      = apa_num(r$elpd_diff_aperiodic_minus_raw, digits = 1),
    se        = apa_num(r$se_diff, digits = 1),
    se_naive  = apa_num(r$se_naive_independent, digits = 1),
    inflation = apa_num(r$se_inflation_from_clustering, digits = 1),
    k         = as.character(r$k[1]))
}
# TRUE only if BOTH strata are ties on the clustered SE, so the sentence below cannot
# describe a split verdict as a single one.
aper_kf_tie <- function() {
  if (!aper_kf_ready()) return(NA)
  all(abs(aper_kf_tbl$elpd_diff_aperiodic_minus_raw) <= 2 * aper_kf_tbl$se_diff)
}
# The sentence reporting the grouped comparison. Emitted only once the artefact exists, so
# the paragraph reads correctly before the job has run and does not have to be remembered
# and edited afterwards.
aper_kf_sentence <- function() {
  if (!aper_kf_ready()) {
    return(paste0(" A direct participant-grouped elpd comparison would complement it and",
                  " is pending."))
  }
  tie <- isTRUE(aper_kf_tie())
  paste0(
    sprintf(paste0(
      "\n\nWe then ran the participant-grouped comparison directly, refitting both models on",
      " the common sample under the %s-fold participant-blocked scheme described in the",
      " Method. The aperiodic-minus-raw difference was %s in the pooled stratum and %s for",
      " gender agreement."),
      aper_kf("pooled", "k"), aper_kf("pooled", "elpd"), aper_kf("gender", "elpd")),
    sprintf(paste0(
      " These are reported with standard errors clustered on participants (%s and %s),",
      " which exceed the naive independent-observation standard errors by factors of %s",
      " and %s, since the pointwise contributions are dependent within a participant."),
      aper_kf("pooled", "se"), aper_kf("gender", "se"),
      aper_kf("pooled", "inflation"), aper_kf("gender", "inflation")),
    if (tie) {
      sprintf(paste0(
        " Neither difference reaches twice its clustered standard error, so neither",
        " characterisation predicts a held-out participant's trajectory detectably better",
        " than the other, and although both differences favour the raw bands in direction",
        " we draw no conclusion from the sign. At these standard errors only a difference",
        " beyond about %s nats in the pooled stratum and %s for gender agreement would be",
        " read as decisive, so this tie bounds the comparison without establishing",
        " equivalence."),
        apa_num(2 * abs(as.numeric(aper_kf_tbl$se_diff[aper_kf_tbl$stratum == "pooled"][1])), digits = 0),
        apa_num(2 * abs(as.numeric(aper_kf_tbl$se_diff[aper_kf_tbl$stratum == "gender"][1])), digits = 0))
    } else {
      # Report the per-stratum verdict in prose. Directing the reader to a CSV would put a
      # repository file path into the Results, and the verdict is a one-clause statement.
      .kf_verdict <- function(s) {
        d <- suppressWarnings(as.numeric(aper_kf_tbl$elpd_diff_aperiodic_minus_raw[
          aper_kf_tbl$stratum == s][1]))
        e <- suppressWarnings(as.numeric(aper_kf_tbl$se_diff[aper_kf_tbl$stratum == s][1]))
        if (is.na(d) || is.na(e)) return("could not be evaluated")
        if (abs(d) > 2 * e)
          sprintf("favours the %s characterisation", if (d > 0) "aperiodic" else "raw-band")
        else "leaves the two indistinguishable"
      }
      sprintf(paste0(" On that corrected scale, the comparison %s in the pooled stratum",
                     " and %s for gender agreement."),
              .kf_verdict("pooled"), .kf_verdict("gender"))
    })
}

# Median widening of credible intervals under weakly-informative vs informative priors.
prior_ci_widening <- function(tbl = sens_tbl) {
  if (is.null(tbl)) return("*[pending sensitivity run]*")
  r <- stats::median(tbl$ci_width_weak / tbl$ci_width_inf, na.rm = TRUE)
  paste0(round(100 * (r - 1)), "%")
}

# Prior-sensitivity inline reporter: an effect's posterior median and interval under
# the weakly-informative ("weak") or the informative ("inf") prior, read from
# _prior_sensitivity.csv rather than transcribed.
sens_effect <- function(model_id, term, which = c("weak", "inf")) {
  which <- match.arg(which)
  if (is.null(sens_tbl)) return("*[pending sensitivity run]*")
  r <- sens_tbl[sens_tbl$model == model_id & sens_tbl$parameter == term, , drop = FALSE]
  if (nrow(r) != 1) return("NN")
  med <- r[[paste0("median_", which)]]
  lo  <- r[[paste0("ci_low_", which)]]
  hi  <- r[[paste0("ci_high_", which)]]
  d <- .les_digits(med, lo, hi)
  sprintf("$b = %s$, 95%% CrI $[%s, %s]$",
          apa_num(med, digits = d), apa_num(lo, digits = d), apa_num(hi, digits = d))
}
# Largest weak-prior probability of direction among the nine predictor-by-session
# interactions, across both Part A models: the value that shows the attainment-not-rate
# asymmetry survives flat priors. Deliberately excludes the design terms
# (session-by-property), whose pd is 1 by construction.
sens_max_rate_pd <- function() {
  if (is.null(sens_tbl)) return("*[pending sensitivity run]*")
  rate_terms <- paste0("z_session_time:z_",
                       c("digit_span", "stroop", "asrt", LES_P2_RS_MEASURES))
  r <- sens_tbl[sens_tbl$parameter %in% rate_terms, , drop = FALSE]
  if (!nrow(r)) return("NN")
  sub("^0", "", formatC(max(r$pd_weak, na.rm = TRUE), format = "f", digits = 2))
}

.pretty_term <- function(x) {
  x |>
    gsub("^b_", "", x = _) |>
    gsub("z_session_time", "Session", x = _) |>
    gsub("z_digit_span", "Working memory", x = _) |>
    gsub("z_stroop", "Inhibitory control", x = _) |>
    gsub("z_asrt", "Statistical learning", x = _) |>
    gsub("z_iaf", "IAF", x = _) |>
    gsub("z_alpha", "Alpha", x = _) |> gsub("z_theta", "Theta", x = _) |>
    gsub("z_beta", "Beta", x = _) |> gsub("z_delta", "Delta", x = _) |> gsub("z_gamma", "Gamma", x = _) |>
    gsub("grammatical_property", "Property:", x = _) |>
    gsub(":", " × ", x = _)
}

# Decimal precision that keeps a credible interval visibly clear of zero. A bound
# can sit very close to zero without touching it (the working-memory predictor's
# lower bound is .005), and at a fixed two decimals such an interval prints as though
# it reached zero, contradicting the credibility being claimed for it. Widen only
# where that would happen, capped at four decimals; everything else stays at two.
# The companion paper's helper applies the same rule with a higher floor (three
# decimals for quantities below .1, on its within-participant SD scale), so the two
# stay local to their documents.
.les_digits <- function(med, lo, hi, min_d = 2L, max_d = 4L) {
  # The rule is simply that no non-zero quantity may print as zero. That matters most
  # for a credible interval, where a "0.00" bound contradicts the credibility claimed
  # for it in the text, but it applies equally to a median, which would otherwise
  # appear as the signed zero "-0.00". Two decimals is the floor and four the ceiling,
  # so effects large enough to be read at two decimals are unaffected and precision
  # widens only where the alternative is a misleading or malformed number.
  v <- abs(c(med, lo, hi))
  v <- v[is.finite(v) & v > 0]
  if (!length(v)) return(min_d)
  d <- min_d
  while (d < max_d && round(min(v), d) == 0) d <- d + 1L
  d
}

# Inline reporter: "b = m, 95% CrI [lo, hi], pd = p%"
report_effect <- function(model_id, term, tbl = post_tbl) {
  if (is.null(tbl)) return("*[pending model fit]*")
  row <- tbl[tbl$model == model_id & tbl$parameter == term, , drop = FALSE]
  if (nrow(row) != 1) return("*[term not found]*")
  d <- .les_digits(row$median, row$ci_low, row$ci_high)
  sprintf("$b = %s$, 95%% CrI $[%s, %s]$, $p_d %s\\%%$",
          apa_num(row$median, digits = d), apa_num(row$ci_low, digits = d),
          apa_num(row$ci_high, digits = d), .fmt_pd_pct(row$pd, math = TRUE))
}

# Probability of direction as a percentage to one decimal. A posterior probability is
# never exactly one, so values that would round to 100.0 print as a bound instead. In
# maths mode the relation sign is part of the string, so "= 95.7" and "> 99.9" both
# follow "p_d" without a doubled sign.
.fmt_pd_pct <- function(pd, math = FALSE) {
  if (!is.finite(pd)) return(if (math) "= NA" else "NA")
  if (pd > 0.9995) return(if (math) "> 99.9" else "> 99.9")
  v <- apa_num(100 * pd, digits = 1)
  if (math) paste0("= ", v) else v
}

# Probability of direction alone, as an inline percentage: for the places where the
# prose refers back to an effect already reported in full, so the pd cannot silently
# go stale on a refit.
pd_of <- function(model_id, term, tbl = post_tbl) {
  if (is.null(tbl)) return("NN")
  row <- tbl[tbl$model == model_id & tbl$parameter == term, , drop = FALSE]
  if (nrow(row) != 1 || is.na(row$pd)) return("NN")
  .fmt_pd_pct(row$pd)
}

# The minimum age, read from the participant table, for the one sentence that names it.
# Emitted from the data so that the sentence and the guardian-consent clause disappear by
# themselves if the minimum ever rises to 18 or above.
minor_age <- function() {
  if (is.null(parts_tbl)) return("")
  r <- parts_tbl[parts_tbl$metric == "age_years", , drop = FALSE]
  if (nrow(r) != 1 || is.na(r$vmin) || r$vmin >= 18) return("")
  as.character(as.integer(r$vmin))
}

# The IAF-resolved sensitivity refit (04_fit_brms_predictors.R under LES_P2_IAF_RESOLVED=1)
# drops the two recordings whose argmax sits at the 7 Hz floor with no fitted peak. Its
# estimate is reported once the pooled summaries carry the tagged model; until then the
# sentence prints a visible pending marker.
iafres_sentence <- function() {
  id <- paste0(LES_P2_MODELS[["predictive_gender"]], "_iafres")
  if (is.null(post_tbl) || !any(post_tbl$model == id & post_tbl$parameter == "z_iaf")) {
    return(paste0("A refit of the gender-agreement model that excludes the two floor-pinned ",
                  "recordings *[is pending, and its individual-alpha-frequency estimate will ",
                  "appear here once it is fitted]*."))
  }
  paste0("In a refit of the gender-agreement model that excludes the two floor-pinned ",
         "recordings, the individual-alpha-frequency association was ",
         report_effect(id, "z_iaf"), ".")
}

# Direct posterior contrast between the working-memory and statistical-learning main
# effects, written by 06_summaries.R only under LES_P2_DERIVED_CONTRASTS=1. The sentence
# prints nothing until that opt-in artefact exists.
contrast_tbl <- .read_csv_if(paper2_results("_predictor_contrasts.csv"))
contrast_sentence <- function() {
  if (is.null(contrast_tbl)) return("")
  sprintf(" The direct contrast between the two coefficients is %s pooled and %s for gender agreement.",
          report_effect(LES_P2_MODELS[["predictive"]], "z_digit_span_minus_z_asrt", tbl = contrast_tbl),
          report_effect(LES_P2_MODELS[["predictive_gender"]], "z_digit_span_minus_z_asrt", tbl = contrast_tbl))
}

# The sign-aligned joint pre/post refit (LES_P2_SIGN_ALIGNED=1 in 05_fit_brms_prepost.R),
# in which the Stroop index is reversed before standardisation so that a positive change
# means improvement on every index. Reported from the pooled summaries once the fit has
# been pooled, so the polarity confound is quantified and not only named.
.signaligned_id <- les_p2_model_id("cog_prepost_joint", "_signaligned")
signaligned_ready <- function() !is.null(post_tbl) && any(post_tbl$model == .signaligned_id)
signaligned_sentence <- function() {
  if (!signaligned_ready()) return("*[sign-aligned joint refit pending]*")
  term <- "session_prepost:measurestroop_interference"
  .pd <- function(m) { r <- post_tbl[post_tbl$model == m & post_tbl$parameter == term, ]
    if (nrow(r) == 1) r$pd else NA_real_ }
  # The interpretive clause is emitted only while the artefacts support it: a Stroop
  # contrast whose probability of direction falls by more than a tenth once the polarity is
  # aligned owed that much of its separation to the polarity opposition.
  gap <- .pd(LES_P2_MODELS[["cog_prepost_joint"]]) - .pd(.signaligned_id)
  clause <- if (is.finite(gap) && gap > 0.10)
    ", so much of the separation in the reported Stroop contrast reflects the polarity opposition" else ""
  sprintf(paste0(
    "Refitting the joint model with the Stroop index reversed before standardisation, so ",
    "that a positive change means improvement on all three indices, gives a digit-span ",
    "change of %s, a Stroop contrast of %s and a statistical-learning contrast of %s%s. ",
    "The statistical-learning contrast is unaffected by the alignment, since a higher ",
    "ASRT score already means better performance."),
    report_effect(.signaligned_id, "session_prepost"),
    report_effect(.signaligned_id, term),
    report_effect(.signaligned_id, "session_prepost:measureasrt_learning"), clause)
}
