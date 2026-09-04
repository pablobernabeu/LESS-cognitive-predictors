# =============================================================================
# paper_2_plasticity/scripts/08_projpred_selection.R
# Phase 3d -- Projection-predictive variable selection for the Part A model  [HPC]
# =============================================================================
#
# PURPOSE
# -------
# The Part A joint model (04_fit_brms_predictors.R) is a *reference* model that
# deliberately keeps ALL candidate baseline predictors (digit span, Stroop, ASRT,
# and -- when 03 has run -- the resting-state EEG bands + IAF), each entered as a
# main effect and as a x learning-rate (z_session_time) interaction. That full
# model is the right object for INFERENCE (it propagates every predictor's
# uncertainty), but a reader also wants to know which SUBSET of predictors carries
# the predictive signal, and how the size-0 (intercept + time only) model compares.
#
# We answer that with PROJECTION-PREDICTIVE variable selection (projpred): project
# the rich reference posterior onto nested candidate submodels and rank predictors
# by the predictive performance retained after projection. This is the recommended
# way to do post-hoc predictor selection under a Bayesian reference model because
# it (a) inherits the reference model's regularisation instead of re-estimating each
# submodel from scratch, and (b) -- with a cross-validated forward search --
# corrects the selection-induced optimism that plagues naive "fit-then-select"
# pipelines (Piironen & Vehtari 2017, doi:10.1007/s11222-016-9649-y; Piironen,
# Paasiniemi & Vehtari 2020, doi:10.1214/20-EJS1711). Because the reference model is
# a multilevel BERNOULLI model with a correlated random slope, we use the LATENT
# projection (Catalina, Buerkner & Vehtari 2021, doi:10.48550/arXiv.2109.04702):
# submodels are projected on the continuous latent (linear-predictor) scale. This
# both sidesteps a fatal lme4/nAGQ incompatibility of the traditional multilevel
# projection for this model class (see the get_refmodel call below for the full
# explanation) and is the projpred authors' recommended projection for multilevel
# binomial models, where the traditional projection can underestimate group-level
# relevance. Predictive performance is reported back on the original 0/1 response
# scale (resp_oscale = TRUE).
#
# GUARDING AGAINST DOUBLE-DIPPING / OPTIMISTIC CV
# -----------------------------------------------
#   * validate_search = TRUE: the ENTIRE forward search (not just the final size
#     choice) is repeated inside every cross-validation fold, so the reported elpd
#     path is an out-of-sample estimate that already pays for the search. Without
#     this, the performance curve is optimistic (the selection saw the held-out
#     data). This is the exact double-dipping the references above warn about.
#   * PARTICIPANT-LEVEL grouped K-fold CV: the response is trial-level and heavily
#     clustered within participant (one participant contributes hundreds of
#     correlated judgement trials). Ordinary row-wise CV would leak a participant's
#     own trials across the train/test split and badly inflate performance. We
#     therefore assign every row of a participant to the SAME fold (grouped CV;
#     Roberts et al. 2017, doi:10.1111/ecog.02881, treat exactly this
#     hierarchical/nested-observations case -- among temporal, spatial and
#     phylogenetic structure -- as requiring block/grouped CV, of which
#     participant-grouping is one directly-named instance; matching the general
#     K-fold-for-model-selection framework of Arlot & Celisse 2010,
#     doi:10.1214/09-SS054), matching the (1 + z_session_time | participant_lab_ID)
#     grouping of the reference model. IMPORTANT: cv_varsel() itself has no
#     `folds=` argument (an earlier version of this script passed one directly to
#     cv_varsel(), where it was silently absorbed into `...` and had NO effect,
#     letting projpred fall back to its own randomly-reseeded, UNGROUPED row-level
#     folds -- exactly the leakage this paragraph describes guarding against; fixed
#     2026-07-02). The grouped fold vector must instead be threaded through
#     run_cvfun(..., folds=) to build a `cvfits` object, then passed to cv_varsel()
#     as `cvfits=` (see run_projpred_one() below).
#
# The predictive metric is elpd (log predictive density) and, for the Bernoulli
# response, classification accuracy. Both are reported as projpred's own difference to
# the REFERENCE model, i.e. to the full Part A fit, so a submodel row of roughly zero
# means that submodel has recovered the reference model's predictive performance
# (Piironen, Paasiniemi & Vehtari 2020). The size-0 (intercept-only) submodel is one of
# the rows and carries a large negative difference; it is not the baseline.
#
# DATA QUIRKS HANDLED (see 02/04 + project brief)
# -----------------------------------------------
#   * Declining N by session, and some participants/sessions missing a property:
#     we operate on EXACTLY the rows the reference model was fit to (fit$data, which
#     04 already NA-dropped on the response, time and the present predictors), so no
#     new rows or predictors are introduced here.
#   * Item codes reused across languages: irrelevant to Part A (the model has no
#     item term; the grouping factor is participant), but we never key on item.
#   * Class balance for "decoding": Part A is a *generative* accuracy model, not a
#     discriminative decoder, so no per-fold class re-balancing is required; we do
#     report the base rate so an accuracy figure is interpretable against it.
#   * A participant with too few rows to appear in every fold is fine under grouped
#     CV (it simply lands in one fold); we guard only against degenerate cases
#     (fewer participants than requested folds -> reduce K).
#
# OUTPUTS (to paper2_results())
#   <model>_cvfits.rds            the K genuine, participant-grouped brms refits
#                                 (run_cvfun() output; cached so a re-run never
#                                 repeats the expensive refits once they succeed)
#   <model>_projpred_path.csv     solution path: rank, predictor added, cumulative
#                                 size, elpd + SE, delta-elpd vs the reference model,
#                                 accuracy
#   <model>_projpred_summary.rds  suggested size + the ranked predictor list + meta
#   <model>_projpred_varsel.rds   the full cv_varsel object (for later plots)
#   _projpred_path.csv            all models pooled (manuscript-facing, like 06)
#
# USAGE (HPC; heavy -- grouped, search-validated CV over a trial-level Bernoulli model)
#   Rscript 08_projpred_selection.R              # both raw-band Part A fits, if cached
#   Rscript 08_projpred_selection.R pooled       # pooled reference only
#   Rscript 08_projpred_selection.R gender       # gender-only reference only
#   Rscript 08_projpred_selection.R aperiodic         # de-confounded (specparam) pooled
#   Rscript 08_projpred_selection.R aperiodic_gender  # de-confounded gender-only
# The two aperiodic invocations are opt-in and are NOT run when no argument is given.
# hpc/09_aperiodic_model.slurm passes both.
#
# Env knobs:
#   LES_PROJPRED_NFOLDS   grouped CV folds over participants (default 10)
#   LES_PROJPRED_NDRAWS   clustered draws used during the projection search, i.e.
#                         cv_varsel's `nclusters` (default 20). The draws used to
#                         EVALUATE performance, `ndraws_pred`, are fixed at 400 below.
#   LES_PROJPRED_NTERMS   max solution-path size (default: all candidate terms)
#   LES_PROJPRED_CORES    CPUs for the run_cvfun refit backend (default:
#                         SLURM_CPUS_PER_TASK, else 1). cv_varsel itself always runs
#                         sequentially; see the parallel-backend policy note below.
# =============================================================================

suppressPackageStartupMessages({
  source(here::here("_shared", "R", "00_paths.R"))
  source(here::here("_shared", "R", "01_bayesian_settings.R"))
  source(here::here("paper_2_plasticity", "scripts", "_config.R"))
  library(brms)
  library(dplyr)
})

# --- Ensure projpred is available (install into the project Rlib if absent) ----
# projpred needs loo (present) + brms (present), so it is one new dependency. The other
# is doParallel (with foreach, which it requires), installed just below and used only for
# the run_cvfun refits.
if (!requireNamespace("projpred", quietly = TRUE)) {
  message("[projpred] not installed -- installing into ", .libPaths()[1])
  utils::install.packages("projpred", repos = "https://cloud.r-project.org/",
                          lib = .libPaths()[1])
}
stopifnot(requireNamespace("projpred", quietly = TRUE))

# doParallel backs the K brms::kfold refits inside run_cvfun; it is optional (the run is
# correct, only slower, without it), so install best-effort. cv_varsel's own projections
# are never parallelised here -- see the parallel-backend policy note below.
if (!requireNamespace("doParallel", quietly = TRUE)) {
  try(utils::install.packages("doParallel", repos = "https://cloud.r-project.org/",
                              lib = .libPaths()[1]), silent = TRUE)
}

# Cores for the run_cvfun refit backend only; use the SLURM allocation if set.
.les_projpred_cores <- as.integer(Sys.getenv("LES_PROJPRED_CORES",
  unset = Sys.getenv("SLURM_CPUS_PER_TASK", unset = "1")))
if (is.na(.les_projpred_cores) || .les_projpred_cores < 1) .les_projpred_cores <- 1L

# Grouped-CV fold count (over participants). Default 10 (the slurm sets it): grouped
# 10-fold corrects the forward-search selection optimism better than 5 while remaining
# tractable. Grouped leave-one-participant-out (K = n participants) is NOT used: the
# cvfits mechanism holds all K reference-model refits in memory at once, so K ~ 55 would
# need hundreds of GB (even K = 5 OOM'd before the FORK fix); LOO is therefore infeasible
# here, and grouped 10-fold is the rigorous, memory-feasible choice (Roberts et al. 2017).
.les_nfolds <- as.integer(Sys.getenv("LES_PROJPRED_NFOLDS", unset = "10"))
.les_ndraws <- as.integer(Sys.getenv("LES_PROJPRED_NDRAWS", unset = "20"))
.les_nterms <- suppressWarnings(as.integer(Sys.getenv("LES_PROJPRED_NTERMS", unset = "")))

# --- Parallel backend policy ---------------------------------------------------
# run_cvfun's K brms::kfold refits are parallelised with a PSOCK backend + mc.cores
# (registered inside run_projpred_one, torn down before cv_varsel). cv_varsel ITSELF
# runs SEQUENTIALLY: on this trial-level Bernoulli workload every parallel cv_varsel
# backend failed. A PSOCK cv_varsel serialises the huge reference model + cvfits to each
# worker (OOM: jobs 8099406/8100219/8101599, even at 240G). A FORK cv_varsel either OOMs
# when a worker ships its per-fold projection back over the socket (aperiodic 8107408 at
# 469G under a 480G cap, then 8108170 at 945G under a 960G cap) or DEADLOCKS with every
# worker idle at 0% CPU (raw 8107407 hung ~28h, 6 forked workers sleeping on ~388G).
# Sequential keeps memory at ~1x -- one projection at a time, well under a normal node's
# 380G -- with no socket serialisation and no forking, so it is the only robust option;
# the `long` partition (30-day wall) absorbs the extra wall-time. .les_want_parallel
# therefore gates only the run_cvfun PSOCK backend now, never cv_varsel.
.les_want_parallel <- .les_projpred_cores > 1L &&
  requireNamespace("foreach", quietly = TRUE) &&
  requireNamespace("doParallel", quietly = TRUE)
.les_parallel_ok <- FALSE   # cv_varsel always sequential (see note above)

# -----------------------------------------------------------------------------
# Build a participant-level fold id aligned to the reference model's data rows.
# -----------------------------------------------------------------------------
# Every row of a given participant_lab_ID gets the SAME fold, so no participant's
# trials straddle the train/test boundary (grouped K-fold; Roberts et al. 2017).
# Participants (not rows) are shuffled into K balanced groups with a fixed seed.
.les_participant_folds <- function(dat, k, seed = LES_SEED) {
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

# -----------------------------------------------------------------------------
# Load a cached Part A reference fit by its brms `file=` cache (NO refit).
# -----------------------------------------------------------------------------
# 04 caches via les_brm(file = paper2_results(model_id)), i.e. brms writes
# paper2_results("<model_id>.rds"); brms::brm(file=...) reloads that object.
.les_load_reference <- function(model_id) {
  cache <- paper2_results(model_id)            # path WITHOUT extension (brms convention)
  rds   <- paste0(cache, ".rds")
  if (!file.exists(rds)) return(NULL)
  # Reload only -- passing file= to brm() returns the cached fit without sampling.
  fit <- brms::brm(file = cache)
  fit
}

# -----------------------------------------------------------------------------
# Run projpred cv_varsel on one reference fit and write the tidy artefacts.
# -----------------------------------------------------------------------------
run_projpred_one <- function(model_id) {
  fit <- .les_load_reference(model_id)
  if (is.null(fit)) {
    message("[projpred] cached reference '", model_id, ".rds' not found -- skipping ",
            "(run 04 on the HPC first).")
    return(invisible(NULL))
  }
  dat <- fit$data
  message(sprintf("[projpred] %s | %d rows | %d participants",
                  model_id, nrow(dat), dplyr::n_distinct(dat$participant_lab_ID)))

  fold_info <- .les_participant_folds(dat, .les_nfolds)
  message(sprintf("[projpred] grouped %d-fold CV over %d participants (fold sizes: %s)",
                  fold_info$k, fold_info$n_participants,
                  paste(fold_info$fold_sizes, collapse = "/")))

  # --- LATENT projection (Catalina, Buerkner & Vehtari 2021) ------------------
  # `latent = TRUE` is required here. The reference model carries a CORRELATED random
  # slope+intercept, (1 + z_session_time | participant_lab_ID).
  # Under projpred's TRADITIONAL projection, multilevel Bernoulli submodels are fit
  # with lme4::glmer, whose PIRLS-convergence-failure auto-retry escalates nAGQ; but
  # lme4 rejects nAGQ > 1 for ANY non-scalar (>1-term) random-effects structure, so
  # the forward search crashes with "nAGQ > 1 is only available for models with a
  # single, scalar random-effects term". This was hit on the HPC (job 8086912
  # failed at 80% of the search) and reproduced in a standalone lme4 test (nAGQ>1
  # fails for any model with >1 RE term, correlated OR uncorrelated -- so simplifying
  # the RE structure would NOT fix it without dropping the random slope, which is the
  # model's whole point). The latent projection instead fits submodels on the
  # continuous latent (linear-predictor) scale via lme4::lmer (no nAGQ, no PIRLS
  # loop), so the crash is structurally unreachable (verified against projpred
  # source: get_refmodel(latent=TRUE) sets the submodel family to gaussian-identity,
  # which routes fit_glmer_callback to its lmer branch, never reaching the glmer
  # call). The Bayesian Stan reference model itself is left completely unchanged.
  # Latent projection is also the projpred authors' recommended projection for
  # multilevel binomial models, where the traditional projection can underestimate
  # group-level relevance. For a brms bernoulli response projpred supplies the
  # response-scale back-transform helpers internally (no latent_ll_oscale /
  # latent_ppd_oscale needed); response-scale (0/1) performance is then requested via
  # resp_oscale = TRUE at the summary stage (.les_projpred_path below).
  refmodel <- projpred::get_refmodel(fit, latent = TRUE)

  # Candidate solution-path length: all non-response predictor terms unless capped.
  # (nterms_max counts terms; leave NULL to let projpred use the full set.)
  nterms_max <- if (length(.les_nterms) && !is.na(.les_nterms)) .les_nterms else NULL

  # --- Genuine, PARTICIPANT-GROUPED K-fold reference-model refits ---------------
  # cv_varsel() has NO `folds=` argument (verified against projpred's actual API,
  # CRAN 2.10.0, cross-checked byte-for-byte against GitHub master): passing one is
  # silently absorbed into `...` and has NO effect whatsoever. Left as it was, this
  # would make cv_varsel(cv_method="kfold") fall back to its internal get_kfold()
  # default, which -- because no `cvfits` is supplied -- generates a FRESH,
  # RANDOMLY-RESEEDED, ROW-LEVEL (ungrouped) fold assignment via cv_folds() every
  # run, silently discarding fold_info$folds and reintroducing exactly the
  # participant-level leakage this function exists to prevent (the response is
  # trial-level and heavily clustered within participant). The documented, correct
  # mechanism is run_cvfun(..., folds=): it attaches the user's exact fold vector as
  # the "folds" attribute of the returned `cvfits` object, which get_kfold() then
  # reads back verbatim (no reseeding) -- so `cvfits=`, not `folds=`, must go to
  # cv_varsel(). run_cvfun() triggers the K genuine brms::kfold() refits of the
  # reference model itself (brms supplies this via get_refmodel.brmsfit()'s default
  # cvfun), so this step is the expensive one, not cv_varsel() itself. Cached to
  # disk (parallel to the reference fit's own brms file= cache) so a re-run of this
  # script never repeats the K refits once they have succeeded.
  # --- Parallelise the K brms::kfold refits (run_cvfun) via a PSOCK backend + mc.cores.
  # This matches the ORIGINAL config that completed run_cvfun fast. run_cvfun's cost is
  # brms::kfold fitting the folds; that parallelises through mc.cores/mclapply and/or the
  # foreach backend. We use PSOCK (separate processes, NOT fork), which -- unlike a FORK
  # cluster -- does not deadlock against cmdstanr's own subprocess forking during the
  # refits. Both are torn down right after run_cvfun, before cv_varsel (which then runs
  # sequentially; see below). NOTE: a no-backend run_cvfun is single-threaded and far too
  # slow (the 10 sequential refits took >5h before this change).
  if (.les_want_parallel) {
    .les_cl <- parallel::makeCluster(.les_projpred_cores)      # PSOCK (default type)
    doParallel::registerDoParallel(.les_cl)
    options(mc.cores = .les_projpred_cores)
    message("[projpred] PSOCK backend + mc.cores=", .les_projpred_cores,
            " registered for run_cvfun.")
  }
  cvfits_path <- paper2_results(paste0(model_id, "_cvfits.rds"))
  if (file.exists(cvfits_path)) {
    message("[projpred] ", model_id, " | reusing cached participant-grouped cvfits")
    cvfits <- readRDS(cvfits_path)
  } else {
    message(sprintf("[projpred] %s | running %d genuine participant-grouped brms refits (run_cvfun)...",
                    model_id, fold_info$k))
    cvfits <- projpred::run_cvfun(refmodel, folds = fold_info$folds, seed = LES_SEED)
    saveRDS(cvfits, cvfits_path)
  }

  # run_cvfun (cmdstanr) is done. Tear down the PSOCK backend and reset the foreach
  # backend to sequential so cv_varsel does NOT inherit a stale cluster: cv_varsel runs
  # sequentially (parallel = FALSE) here -- one per-fold projection at a time -- which is
  # the only configuration that neither OOMs nor deadlocks on this workload (see the
  # parallel-backend policy note above).
  if (.les_want_parallel) {
    try(parallel::stopCluster(.les_cl), silent = TRUE)
    try(foreach::registerDoSEQ(), silent = TRUE)
    options(mc.cores = 1L)
  }
  # Restates the file-level policy after the cluster teardown: whatever happened above,
  # cv_varsel is entered with parallelism off.
  .les_parallel_ok <- FALSE
  message("[projpred] ", model_id, " | cv_varsel running SEQUENTIALLY (parallel = FALSE).")

  # cv_varsel with the pre-built, participant-grouped cvfits + validate_search=TRUE.
  # method="forward" is the default and the one whose search we cross-validate.
  vs <- projpred::cv_varsel(
    refmodel,
    method          = "forward",
    cv_method       = "kfold",
    cvfits          = cvfits,              # genuine, participant-grouped K-fold refits
    validate_search = TRUE,                # cross-validate the WHOLE search (anti-optimism)
    ndraws_pred     = 400,                 # draws for performance evaluation
    nclusters       = .les_ndraws,         # clustered draws for the projection search (speed)
    nterms_max      = nterms_max,
    seed            = LES_SEED,
    parallel        = .les_parallel_ok,    # FALSE -- sequential per-fold CV (robust: no OOM, no deadlock)
    verbose         = TRUE
  )

  saveRDS(vs, paper2_results(paste0(model_id, "_projpred_varsel.rds")))

  # Suggested size: projpred's heuristic with its defaults (baseline = "ref"): the
  # smallest submodel whose cross-validated elpd difference to the REFERENCE model
  # has an upper one-SE bound reaching zero, i.e. within one SE of the reference
  # model, not of the best submodel (Piironen, Paasiniemi & Vehtari 2020).
  sug <- tryCatch(projpred::suggest_size(vs, stat = "elpd"),
                  error = function(e) NA_integer_)

  path_df <- .les_projpred_path(vs, model_id, sug, fold_info)
  utils::write.csv(path_df, paper2_results(paste0(model_id, "_projpred_path.csv")),
                   row.names = FALSE)

  ranking <- .les_solution_terms(vs)
  summ <- list(
    model                = model_id,
    suggested_size       = sug,
    solution_path        = ranking,
    n_candidate_terms    = length(ranking),
    n_participants       = fold_info$n_participants,
    n_folds              = fold_info$k,
    base_rate            = mean(dat[[.les_response_name(fit)]] == 1, na.rm = TRUE),
    validate_search      = TRUE,
    cv_method            = "participant-grouped kfold"
  )
  saveRDS(summ, paper2_results(paste0(model_id, "_projpred_summary.rds")))

  message(sprintf("[projpred] %s | suggested size = %s | ranking: %s",
                  model_id, ifelse(is.na(sug), "NA", sug),
                  paste(ranking, collapse = " > ")))
  invisible(path_df)
}

# --- response variable name (Bernoulli: usually "correct") --------------------
.les_response_name <- function(fit) {
  rn <- tryCatch(all.vars(brms::brmsterms(fit$formula)$respform)[1],
                 error = function(e) NA_character_)
  if (is.na(rn) || !rn %in% names(fit$data)) rn <- names(fit$data)[1]
  rn
}

# --- ordered predictor ranking from the cv_varsel object ----------------------
# Prefer the modern ranking() API (projpred >= 2.6); fall back to the deprecated
# solution_terms(), then to the raw slot, so this survives a version bump.
.les_solution_terms <- function(vs) {
  st <- NULL
  if (exists("ranking", where = asNamespace("projpred"), inherits = FALSE)) {
    st <- tryCatch(projpred::ranking(vs)$fulldata, error = function(e) NULL)
  }
  if (is.null(st)) st <- tryCatch(projpred::solution_terms(vs), error = function(e) NULL)
  if (is.null(st)) st <- tryCatch(vs$solution_terms, error = function(e) NULL)
  as.character(st)
}

# -----------------------------------------------------------------------------
# Tidy the performance-vs-size path into a data frame.
# -----------------------------------------------------------------------------
# projpred::summary(vs) yields per-size predictive stats (elpd etc.) for the submodels,
# each already expressed as a difference to the REFERENCE model (the full Part A fit).
# We copy those differences through unchanged, so elpd_diff below is "delta-elpd vs the
# reference model", and the size-0 submodel is simply the first row of that path, not a
# baseline of zero.
# resp_oscale = TRUE: under the LATENT projection the search runs on the latent
# (linear-predictor) scale, but predictive performance must be reported on the
# ORIGINAL 0/1 response scale (projpred back-transforms it via the binomial helpers
# it supplies internally for a bernoulli reference). resp_oscale defaults to TRUE,
# but we state it explicitly. Accuracy ("acc") should be available for the binomial
# family, but if a given projpred version restricts it under the latent projection
# we fall back to elpd alone (elpd is the primary selection statistic regardless).
.les_projpred_path <- function(vs, model_id, suggested_size, fold_info) {
  smy <- tryCatch(
    summary(vs, stats = c("elpd", "acc"),
            type = c("mean", "se", "diff", "diff.se"), resp_oscale = TRUE),
    error = function(e) {
      message("[projpred] 'acc' unavailable under latent projection (", conditionMessage(e),
              ") -- reporting elpd only.")
      summary(vs, stats = "elpd",
              type = c("mean", "se", "diff", "diff.se"), resp_oscale = TRUE)
    })
  # projpred 2.10 stores the per-size performance path in $perf_sub (the reference
  # row is separate, in $perf_ref); older/other versions used $perf_stats or
  # $selection. Fall through the known slot names so this survives a version bump.
  perf <- smy$perf_sub
  if (is.null(perf)) perf <- smy$perf_stats
  if (is.null(perf)) perf <- smy$selection
  perf <- as.data.frame(perf)
  if (!nrow(perf))
    stop("projpred summary() returned no per-size rows for ", model_id,
         " (available slots: ", paste(names(smy), collapse = ", "), ")")

  # Harmonise column names across projpred versions.
  size_col <- intersect(c("size", "nterms"), names(perf))[1]
  term_col <- intersect(c("ranking_fulldata", "solution_terms", "predictor", "term"),
                        names(perf))[1]

  size_vals <- if (!is.na(size_col)) perf[[size_col]] else seq_len(nrow(perf)) - 1L
  out <- data.frame(
    model         = model_id,
    size          = size_vals,
    predictor     = if (!is.na(term_col)) as.character(perf[[term_col]]) else NA_character_,
    stringsAsFactors = FALSE
  )
  # With two stats requested projpred prefixes every column (elpd.se, acc.se, ...);
  # the elpd-only fallback drops the prefix (se, diff, diff.se). Try prefixed first.
  cp <- function(...) {
    for (nm in c(...)) if (nm %in% names(perf)) return(perf[[nm]])
    NA_real_
  }
  out$elpd            <- cp("elpd")
  out$elpd_se         <- cp("elpd.se", "se")
  out$elpd_diff       <- cp("elpd.diff", "diff")      # vs reference (projpred convention)
  out$elpd_diff_se    <- cp("elpd.diff.se", "diff.se")
  out$acc             <- cp("acc")
  out$acc_se          <- cp("acc.se")
  out$acc_diff        <- cp("acc.diff")
  # Fold-wise ranking-stability diagnostic: the proportion of CV folds in which the
  # predictor added at this size occupied this rank. projpred's summary() already
  # computes it in $perf_sub; retaining it lets the manuscript report how stable the
  # "entered at step k" ordering is across folds, rather than presenting a single
  # full-data path as if it were definitive.
  out$cv_prop_diag    <- cp("cv_proportions_diag", "cv_proportions.diag", "cv_proportions")
  out$suggested_size  <- suggested_size
  out$is_suggested    <- !is.na(suggested_size) & out$size == suggested_size
  out$n_folds         <- fold_info$k
  out$n_participants  <- fold_info$n_participants
  out
}

# -----------------------------------------------------------------------------
# Pool per-model paths into one manuscript-facing CSV (mirrors 06's pooled CSVs).
# -----------------------------------------------------------------------------
pool_paths <- function() {
  files <- list.files(paper2_results(), pattern = "_projpred_path\\.csv$", full.names = TRUE)
  files <- files[basename(files) != "_projpred_path.csv"]     # skip the pooled target
  if (!length(files)) return(invisible(NULL))
  pooled <- dplyr::bind_rows(lapply(files, utils::read.csv, stringsAsFactors = FALSE))
  utils::write.csv(pooled, paper2_results("_projpred_path.csv"), row.names = FALSE)
  message("[projpred] pooled ", length(files), " path CSV(s) -> _projpred_path.csv")
  invisible(pooled)
}

# =============================================================================
# Entry point
# =============================================================================
.run <- function() {
  which <- commandArgs(trailingOnly = TRUE)
  do_pooled <- length(which) == 0 || "pooled" %in% which
  do_gender <- length(which) == 0 || "gender" %in% which
  if (do_pooled) run_projpred_one(LES_P2_MODELS[["predictive"]])
  if (do_gender) run_projpred_one(LES_P2_MODELS[["predictive_gender"]])
  # De-confounded (specparam) reference model(s): opt-in, select over the aperiodic
  # exponent/offset + 1/f-adjusted band power in place of raw band power.
  if ("aperiodic"        %in% which) run_projpred_one(LES_P2_MODELS[["predictive_aperiodic"]])
  if ("aperiodic_gender" %in% which) run_projpred_one(LES_P2_MODELS[["predictive_aperiodic_gender"]])
  pool_paths()
  # (The run_cvfun PSOCK backend is created and torn down per-model inside
  # run_projpred_one; cv_varsel runs sequentially, so there is no global cluster here.)
  message("[projpred] done.")
}

if (sys.nframe() == 0L) .run()
