# =============================================================================
# 06_manuscript_helpers.R  --  Reporting helpers shared by the two manuscripts
# =============================================================================
#
# Both manuscripts (paper_1_transfer/paper_1_morphosyntax.qmd and
# paper_2_plasticity/paper_2_neuroplasticity.qmd, with its supplement) source this file
# from their setup chunk, directly after their _config.R, so that the figure theme, the
# diverging scale, the number formatters and the small artefact readers are defined
# once. Every helper here is byte-identical to the copies the two setup chunks used to
# carry, so both PDFs render exactly as before.
#
# Two helpers have a document-level input. les_theme() takes the figure text size from
# LES_FIG_BASE_SIZE, which each setup chunk sets before sourcing this file, and
# prov(), flow_n() and pstat() read .prov_tbl, flow_tbl and parts_tbl, which each setup
# chunk loads from its own results/ folder after sourcing this file. Quarto evaluates
# the chunks in the global environment, which is also where source() places these
# functions, so the lookups resolve at call time.
# =============================================================================

# Figure theme: depictr when present, base ggplot2 otherwise. Every figure calls
# les_theme() so a change here propagates to both manuscripts. The depictr flag is an
# argument, defaulting to whether the package is installed, so the helper does not
# depend on a variable of the calling document.
les_theme <- function(base_size = LES_FIG_BASE_SIZE,
                      has_depictr = requireNamespace("depictr", quietly = TRUE)) {
  base <- if (has_depictr) depictr::theme_depictr(base_size = base_size)
          else ggplot2::theme_minimal(base_size = base_size)
  # The default packs the factor levels tightly enough that the key squares read as
  # one block; give each entry room.
  base + ggplot2::theme(
    legend.key.spacing.y = ggplot2::unit(3, "pt"),
    legend.key.spacing.x = ggplot2::unit(8, "pt"),
    # A small left margin separates the key from its label; the right margin
    # keeps adjacent entries from running together.
    legend.text  = ggplot2::element_text(margin = ggplot2::margin(l = 3, r = 6)),
    legend.title = ggplot2::element_text(margin = ggplot2::margin(b = 4)),
    # Keep axis titles and tick labels clear of the plot edge; the LaTeX float
    # filter separately supplies the gap between the rendered plot and its note.
    plot.margin = ggplot2::margin(4, 8, 6, 8))
}

# Endpoints and midpoint of the diverging scale used for signed quantities (the scalp
# topography in Paper 1; the predictor correlation matrix in Paper 2). Taken from
# depictr so both papers share one diverging scale; the fallback is the same
# ColorBrewer RdBu anchors.
les_div <- if (requireNamespace("depictr", quietly = TRUE))
  depictr::depictr_palette(5, "diverging")[c(5, 3, 1)] else
  c("#005B96", "#F7F7F7", "#B2182B")

# papaja's number formatters if available; otherwise base-R fallbacks so the
# document never hard-fails on a missing optional dependency.
if (requireNamespace("papaja", quietly = TRUE)) {
  apa_num <- papaja::apa_num
  apa_p   <- papaja::apa_p
} else {
  apa_num <- function(x, digits = 2, ...) formatC(x, format = "f", digits = digits)
  apa_p   <- function(p, ...) ifelse(p < .001, "< .001", sub("^0", "", formatC(p, format = "f", digits = 3)))
}

# Read a results CSV when it exists, NULL otherwise: the render-anytime design rests on
# every artefact reader tolerating an absent file.
.read_csv_if <- function(path) if (file.exists(path)) utils::read.csv(path, stringsAsFactors = FALSE) else NULL

# Computational provenance recorded at fit time by _shared/R/04_provenance.R, read from
# the document's .prov_tbl, so the reported versions are those of the run that produced
# the results and not of the machine rendering the document. Absent until the pipeline
# is next run.
prov <- function(component, fallback = "*[version pending a pipeline run]*") {
  if (is.null(.prov_tbl)) return(fallback)
  r <- .prov_tbl[.prov_tbl$component == component, , drop = FALSE]
  if (nrow(r) != 1 || is.na(r$version[1])) return(fallback)
  as.character(r$version[1])
}

# Participant-flow count for a stage of the document's flow_tbl; `col` picks total or a
# per-language column.
flow_n <- function(stage, col = "n_total") {
  if (is.null(flow_tbl)) return("NN")
  r <- flow_tbl[flow_tbl$stage == stage, , drop = FALSE]
  if (nrow(r) != 1 || is.na(r[[col]])) return("NN")
  as.character(r[[col]])
}

# Demographic metric from the document's parts_tbl (value / sd / n / vmin / vmax).
pstat <- function(metric, col = "value", digits = 1) {
  if (is.null(parts_tbl)) return("NN")
  r <- parts_tbl[parts_tbl$metric == metric, , drop = FALSE]
  if (nrow(r) != 1 || is.na(r[[col]])) return("NN")
  v <- r[[col]]
  if (is.numeric(v) && !isTRUE(all.equal(v, round(v)))) apa_num(v, digits = digits) else as.character(v)
}
