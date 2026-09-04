# =============================================================================
# 01_bayesian_settings.R  --  Shared brms / Stan configuration for both papers
# =============================================================================
#
# This module centralises every modelling choice that should be IDENTICAL across
# the two manuscripts so that the analyses are mutually consistent and each
# decision is justified exactly once. Each block cites the methodological source
# that motivates it (statistics or domain), per the project's requirement that
# all choices be defensible.
# =============================================================================

suppressPackageStartupMessages({
  if (!requireNamespace("brms", quietly = TRUE)) {
    stop("brms is required. Run _shared/install_bayesian_dependencies.R first.")
  }
  library(brms)
})

# -----------------------------------------------------------------------------
# 1. STAN BACKEND  --  cmdstanr with within-chain threading
# -----------------------------------------------------------------------------
# We use cmdstanr rather than rstan because it tracks the current Stan release
# and enables within-chain parallelisation via `reduce_sum` (the `threads`
# argument below), which materially shortens runtime for the large single-trial
# models on the HPC nodes (Carpenter et al., 2017, J. Stat. Soft.,
# https://doi.org/10.18637/jss.v076.i01; Stan Development Team, Stan User's Guide,
# "Reduce-sum" threading). If cmdstanr is unavailable the code falls back to
# rstan so the pipeline still runs, only more slowly.
#
# On ARC the threading choice carries a compile-time cost. GCC 14.2.0, the compiler in the
# R/4.5.1-gfbf-2025a toolchain, crashes while instantiating Stan's reduce_sum templates at
# -O2 and above, so keeping threading pins the CmdStan build at -O1 (see
# _shared/hpc/arc_env.sh, which applies the pin and records the measurements). Threading
# was kept in preference to raising the optimisation level because dropping it changes the
# reduce_sum reduction order and so the exact draws, whereas the optimisation level does
# not.
.les_backend <- if (requireNamespace("cmdstanr", quietly = TRUE)) "cmdstanr" else "rstan"

# Point cmdstanr at the CmdStan installation. On the ARC cluster the job scripts
# export CMDSTAN=/data/educ-intract/educ1242/new_LESS/cmdstan/cmdstan-<version> (the C++
# toolchain is kept in the project /data space, not on the personal disk), so we
# honour it explicitly rather than relying on auto-detection -- this prevents a
# fit from silently falling back to a missing/half-built toolchain.
if (.les_backend == "cmdstanr") {
  .cmdstan_env <- Sys.getenv("CMDSTAN", unset = "")
  if (nzchar(.cmdstan_env)) try(cmdstanr::set_cmdstan_path(.cmdstan_env), silent = TRUE)
}

# Number of threads PER CHAIN. On a SLURM node we request `--cpus-per-task`
# equal to CHAINS * THREADS_PER_CHAIN; here we read an env var so the same R
# code adapts to the cluster allocation without edits.
.les_threads_per_chain <- as.integer(Sys.getenv("LES_THREADS_PER_CHAIN", unset = "2"))

# -----------------------------------------------------------------------------
# 2. SAMPLER CONTROL  --  4 chains, NUTS, conservative adapt_delta / max_treedepth
# -----------------------------------------------------------------------------
# Four independent chains are the de-facto standard for assessing mixing via the
# rank-normalised split-Rhat (Vehtari, Gelman, Simpson, Carpenter & Bürkner,
# 2021, Bayesian Analysis, https://doi.org/10.1214/20-BA1221). We raise
# `adapt_delta` to 0.95 and `max_treedepth` to 12 because maximal random-effect
# models induce a challenging posterior geometry; higher adapt_delta reduces the
# step size and thereby the risk of divergent transitions (Betancourt, 2017,
# arXiv:1701.02434; Stan Dev. Team divergence guidance).
LES_CHAINS        <- 4L
LES_ITER_WARMUP   <- 2000L
LES_ITER_SAMPLING <- 8000L          # 4 * 8000 = 32000 post-warmup draws, raised from
                                    # 1000/2000 so the hardest single-trial ERP cells clear
                                    # the gate in 02_diagnostics.R (Rhat < 1.01, ESS > 400)
LES_SEED          <- 20260607L      # fixed for exact reproducibility
LES_CONTROL       <- list(adapt_delta = 0.95, max_treedepth = 12L)

# -----------------------------------------------------------------------------
# 3. PRIORS  --  INFORMATIVE on the standardised (z) scale (literature-derived)
# -----------------------------------------------------------------------------
# Paper 1 uses informative priors derived from a literature review carried out in June
# 2026, replacing the weakly-informative defaults used before then. Every source cited
# below is recorded in paper_1_transfer/references.bib, where the DOIs were checked
# against Crossref when they were added. The former defaults are retained below as
# `*_weak()` to serve as the documented prior-sensitivity baseline (Depaoli & van de
# Schoot, 2017, Psychological Methods,
# https://doi.org/10.1037/met0000065). All continuous predictors are z-scored and
# dichotomous predictors are +/-0.5 contrast-coded then z-scored (Brauer & Curtin,
# 2018, https://doi.org/10.1037/met0000159; Schielzeth, 2010,
# https://doi.org/10.1111/j.2041-210X.2010.00012.x), so coefficients share a common
# scale. The ERP response z_amplitude is standardised within participant, so every ERP
# coefficient is already in within-participant-SD units.
#
# STRATEGY = "selective, sign-informed, magnitude-regularising":
#   * The one robustly-evidenced DIRECTIONAL fact is encoded as a prior MEAN: a
#     posterior P600 in which the UNGRAMMATICAL condition is MORE POSITIVE than the
#     grammatical one in the ~400-900 ms window, reliable across native speakers and
#     artificial/miniature-language learners (Mueller, Hahne, Fujii & Friederici, 2005,
#     https://doi.org/10.1162/0898929055002463; Mueller, Hirotani & Friederici, 2007,
#     https://doi.org/10.1186/1471-2202-8-18; Chen, Shu, Liu, Zhao & Li, 2007,
#     https://doi.org/10.1017/S136672890700291X; Silva, Folia, Hagoort & Petersson,
#     2017, https://doi.org/10.1111/cogs.12343; Morgan-Short, Steinhauer, Sanz &
#     Ullman, 2012, https://doi.org/10.1162/jocn_a_00119).
#   * SIGN derivation from the data coding (import_trialbytrial_EEG_data.R):
#     grammaticality is coded Grammatical = +0.5, Ungrammatical = -0.5, so
#     z_recoded_grammaticality is HIGHER for GRAMMATICAL. Because the P600 makes the
#     ungrammatical condition MORE positive (higher amplitude), the grammaticality
#     slope in the P600 window is NEGATIVE  ->  prior normal(-0.2, 0.3).
#   * WINDOW GRADING of the grammaticality prior. The P600 onsets ~500 ms and is a
#     broad late positivity, so it occupies both the 400-900 ms window (full P600;
#     prior mean -0.2) AND the upper part of the 300-600 ms window (rising P600; milder
#     mean -0.1) for AGREEMENT violations, whose canonical late signature is a posterior
#     positivity, not an N400 (Chen, Shu, Liu, Zhao & Li, 2007: posterior P600 at
#     500-700 ms, https://doi.org/10.1017/S136672890700291X; Osterhout & Holcomb, 1992,
#     https://doi.org/10.1016/0749-596X(92)90039-Z). For DIFFERENTIAL OBJECT MARKING the
#     300-600 ms window is left NEUTRAL: case/DOM violations can elicit an N400 (opposite
#     sign) alongside the P600 (Mueller, Hahne, Fujii & Friederici, 2005,
#     https://doi.org/10.1162/0898929055002463), so the sign is ambiguous there. The
#     200-500 ms LAN window stays NEUTRAL for all properties: the anterior negativity is
#     small and present in only ~46-55% of subjects/items, so its sign is not safely
#     predictable (Caffarra, Mendoza & Davidson, 2019,
#     https://doi.org/10.1016/j.bandl.2019.01.003).
#   * TOPOGRAPHY: caudality DIRECTIONAL, hemisphere NEUTRAL. The P600 is reliably
#     POSTERIOR/centroparietal-maximal (Mueller, Hirotani & Friederici, 2007: posterior
#     F=50.98 vs anterior F<1, https://doi.org/10.1186/1471-2202-8-18; Chen et al., 2007:
#     maximal at posterior sites; Osterhout & Holcomb, 1992). With caudality coded
#     anterior=+0.5/posterior=-0.5, a P600 larger (i.e. a more negative grammaticality
#     slope) posteriorly implies a POSITIVE grammaticality x caudality prior in the
#     P600-bearing windows -> normal(+0.1, 0.3). HEMISPHERE is kept NEUTRAL: the P600 is
#     not robustly lateralised, and the one lateralised component (the left-anterior LAN)
#     is too heterogeneous to sign (Caffarra et al., 2019) -- consistent with the neutral
#     early window.
#   * EVERYTHING ELSE stays zero-centred and weakly informative -- above all the
#     grammaticality x session x language TRANSFER interaction (the hypothesis under
#     test), which the literature shows is qualitatively CONTESTED in learners (Chen
#     et al., 2007; Mueller, Oberecker & Friederici, 2009,
#     https://doi.org/10.1186/1471-2202-10-89). Zero-centred priors there keep the
#     hypothesis test unbiased.
#   * VARIANCE components stay generous (heavy-tailed half-Student-t) to absorb the
#     large, systematic between-participant negativity<->positivity continuum (Tanner
#     & Van Hell, 2014, https://doi.org/10.1016/j.neuropsychologia.2014.02.002);
#     correlations keep LKJ(2) (Lewandowski, Kurowicka & Joe, 2009,
#     https://doi.org/10.1016/j.jmva.2009.04.008).
#   * MAGNITUDE: the review found no defensible microvolt effect size (the only numeric
#     uV anchor was refuted in verification), so prior MEANS are set on SIGN and kept
#     modest; the implied amplitudes are checked with PRIOR PREDICTIVE simulation
#     (Schad, Betancourt & Vasishth, 2021, https://doi.org/10.1037/met0000275) and the
#     weakly-informative baseline is reported as a sensitivity analysis (LES_PRIOR_SET).
# General prior-choice rationale: Gelman et al. (2008,
# https://doi.org/10.1214/08-AOAS191); Gelman (2006, https://doi.org/10.1214/06-BA117A);
# McElreath (2020, Statistical Rethinking).
# Every DOI above is present in paper_1_transfer/references.bib and was Crossref-verified
# when the entry was added (see the block headers in that file).

# --- INFORMATIVE priors: GAUSSIAN ERP models ---------------------------------
# `window`/`property` select the sign-informed P600 priors, graded by window and
# property (see the strategy notes above). Called per cell by step 03.
# `macroregion` is accepted so that the four prior builders share one call signature
# behind les_erp_prior() and les_acc_prior(). Step 03 does pass the cell's macroregion,
# but no prior is currently graded by it, so the argument is unused in the body. The same
# holds for `property` on the two bernoulli builders, which take it for parity only.
les_priors_gaussian <- function(window = NULL, property = NULL, macroregion = NULL) {
  pr <- c(
    brms::prior(normal(0, 0.5),       class = "b"),          # zero-centred default (incl. transfer interaction)
    brms::prior(normal(0, 0.5),       class = "Intercept"),  # DV is within-participant z -> ~0
    brms::prior(student_t(3, 0, 2.5), class = "sd"),         # generous RE SDs (Tanner & Van Hell, 2014)
    brms::prior(lkj(2),               class = "cor"),        # RE correlations (Lewandowski et al., 2009)
    brms::prior(student_t(3, 0, 2.5), class = "sigma")       # residual SD
  )
  is_dom <- !is.null(property) && property == "differential_object_marking"
  # Window-graded P600 grammaticality mean (NEGATIVE: ungrammatical more positive,
  # grammatical coded +0.5). 400_900 = full P600; 300_600 = rising P600 (agreement only;
  # DOM left neutral, N400/P600 ambiguous); 200_500 = LAN window (neutral). caud_mean > 0
  # encodes the posterior-maximal P600 (caudality anterior=+0.5/posterior=-0.5).
  # The SD is widened from 0.3 to 0.4 for DOM even in the full-P600 window because
  # case-marking violations are configuration-dependent, eliciting a P600, an N400 or a
  # biphasic response according to animacy and markedness. The sign is still the P600 one,
  # but it is held with less confidence than for the agreement properties. The manuscript
  # sets out this reasoning with its sources (paper_1_morphosyntax.qmd, prior section).
  gram_mean <- 0; gram_sd <- 0.3; caud_mean <- 0
  if (!is.null(window)) {
    if (window == "400_900") {
      gram_mean <- -0.2; gram_sd <- if (is_dom) 0.4 else 0.3; caud_mean <- 0.1
    } else if (window == "300_600" && !is_dom) {
      gram_mean <- -0.1; gram_sd <- 0.3; caud_mean <- 0.1
    }
  }
  if (gram_mean != 0) {
    pr <- c(pr, brms::prior_string(sprintf("normal(%s, %s)", gram_mean, gram_sd),
                                   class = "b", coef = "z_recoded_grammaticality"))
  }
  if (caud_mean != 0) {
    pr <- c(pr, brms::prior_string(sprintf("normal(%s, 0.3)", caud_mean),
                                   class = "b", coef = "z_recoded_grammaticality:z_recoded_caudality"))
  }
  pr
}

# --- INFORMATIVE priors: BERNOULLI accuracy models ---------------------------
# Grammaticality-judgement accuracy is well above chance and improves with training
# (Mueller, Oberecker & Friederici, 2009, https://doi.org/10.1186/1471-2202-10-89:
# learners 89%, natives 99%, significant gain across blocks). session is coded
# 0,1,2,3 (later = higher), so the training effect on accuracy is a POSITIVE session
# slope; the intercept sits clearly above chance (logit ~ +1.5..2).
les_priors_bernoulli <- function(property = NULL) {
  c(
    brms::prior(normal(0, 1),         class = "b"),                                # zero-centred default (incl. transfer interaction)
    # Sign-informed only: the cited percentages establish that accuracy improves with
    # training, not a logit-per-standardised-session slope, so 0.3 is a modest positive
    # shift chosen under the MAGNITUDE policy above rather than a derived quantity.
    brms::prior(normal(0.3, 0.5),     class = "b", coef = "z_recoded_session"),    # accuracy improves with training
    brms::prior(normal(1.5, 1),       class = "Intercept"),                        # accuracy >> chance
    brms::prior(student_t(3, 0, 2.5), class = "sd"),
    brms::prior(lkj(2),               class = "cor")
  )
}

# --- WEAKLY-INFORMATIVE baselines (retained for the prior-SENSITIVITY analysis) -
# The pre-2026 defaults: normal(0,1) (ERP) / normal(0,1.5) (logit) on every slope and
# intercept. Re-running the pipeline with LES_PRIOR_SET=weak refits every model under
# these priors so the informative-vs-weak posterior shift can be reported.
les_priors_gaussian_weak <- function(window = NULL, property = NULL, macroregion = NULL) {
  c(
    brms::prior(normal(0, 1),         class = "b"),
    brms::prior(normal(0, 1),         class = "Intercept"),
    brms::prior(student_t(3, 0, 2.5), class = "sd"),
    brms::prior(lkj(2),               class = "cor"),
    brms::prior(student_t(3, 0, 2.5), class = "sigma")
  )
}
les_priors_bernoulli_weak <- function(property = NULL) {
  c(
    brms::prior(normal(0, 1.5),       class = "b"),
    brms::prior(normal(0, 1.5),       class = "Intercept"),
    brms::prior(student_t(3, 0, 2.5), class = "sd"),
    brms::prior(lkj(2),               class = "cor")
  )
}

# --- Prior-set selector (informative by default; "weak" for the sensitivity run) -
# Set the env var LES_PRIOR_SET=weak to refit every model under the weakly-informative
# baseline; les_prior_tag() then suffixes the cached files so the two runs never clash.
LES_PRIOR_SET <- function() tolower(Sys.getenv("LES_PRIOR_SET", unset = "informative"))
les_prior_tag <- function() if (LES_PRIOR_SET() == "weak") "_weakprior" else ""
les_erp_prior <- function(window = NULL, property = NULL, macroregion = NULL) {
  if (LES_PRIOR_SET() == "weak") les_priors_gaussian_weak(window, property, macroregion)
  else                           les_priors_gaussian(window, property, macroregion)
}
les_acc_prior <- function(property = NULL) {
  if (LES_PRIOR_SET() == "weak") les_priors_bernoulli_weak(property) else les_priors_bernoulli(property)
}

# -----------------------------------------------------------------------------
# 4. ONE ENTRY POINT  --  fit a brms model with all shared settings applied
# -----------------------------------------------------------------------------
# Centralising the call guarantees that every model in both papers uses the same
# chains, seed, priors, backend and threading, and writes a self-describing .rds.
les_brm <- function(formula, data, family,
                    prior   = NULL,
                    file    = NULL,          # path WITHOUT extension; brms caches here
                    threads = .les_threads_per_chain,
                    ...) {

  if (is.null(prior)) {
    prior <- switch(family$family,
      gaussian  = les_priors_gaussian(),
      bernoulli = les_priors_bernoulli(),
      binomial  = les_priors_bernoulli(),
      les_priors_gaussian()
    )
  }

  brms::brm(
    formula  = formula,
    data     = data,
    family   = family,
    prior    = prior,
    chains   = LES_CHAINS,
    cores    = LES_CHAINS,
    threads  = if (.les_backend == "cmdstanr") brms::threading(threads) else NULL,
    iter     = LES_ITER_WARMUP + LES_ITER_SAMPLING,
    warmup   = LES_ITER_WARMUP,
    seed     = LES_SEED,
    control  = LES_CONTROL,
    backend  = .les_backend,
    # Prior draws are stored alongside the posterior. Nothing in either pipeline reads
    # them at present: the reported prior predictive check refits with sample_prior =
    # "only" (02_diagnostics.R) and the prior sensitivity analysis compares this run with
    # the separate LES_PRIOR_SET=weak run. Leave the argument in place regardless, because
    # les_brm caches with file_refit = "on_change" and changing the model configuration
    # would invalidate every fit already in results/.
    sample_prior = "yes",
    file     = file,
    file_refit = "on_change",
    ...
  )
}

cat(sprintf("[bayes] backend = %s | chains = %d | threads/chain = %d\n",
            .les_backend, LES_CHAINS, .les_threads_per_chain))
