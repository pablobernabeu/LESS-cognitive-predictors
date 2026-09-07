# =============================================================================
# _shared/R/write_codebook.R  --  Column-level codebook for the results CSVs
# =============================================================================
#
# WHAT IT DOES
# Writes results/CODEBOOK.md in each paper: one table per manuscript-facing CSV, giving
# for every column its name, the R class that read.csv() infers from the first 200 rows,
# a description and the script that writes the file. The descriptions come from
# _shared/R/codebook_descriptions.csv, a hand-maintained table with the columns
#   paper, file_pattern, column, description, writer_script
# where file_pattern is an exact file name or a glob such as '_pooled_*.csv'. An exact
# name takes precedence over a glob, and among globs the one with more literal
# characters wins. A column with no matching row prints '(description pending)' and is
# listed in a warning at the end so the table can be completed; the script never stops
# on one.
#
# WHEN TO RUN IT
# Opt-in, and called by no pipeline stage or slurm job. Run it by hand from the project
# root on the rendering box after the CSVs have been pulled from the cluster, so that
# every manuscript-facing file is present:
#     Rscript _shared/R/write_codebook.R
# On Windows:
#     "C:/Program Files/R/R-4.6.1/bin/Rscript.exe" _shared/R/write_codebook.R
# The working directory does not matter: paths resolve through here::here(). Only base R
# and the here package are needed, and the manuscripts already require here.
#
# WHICH FILES
#   paper_1_transfer/results:   _*.csv and *_decoding_*.csv
#   paper_2_plasticity/results: _*.csv and p2_*.csv
# Every *.rds is left out, as is 07_aperiodic_features.csv, the one pipeline-internal
# table in Paper 2. A CSV that matches no pattern is not listed.
#
# The class column is what read.csv() infers from the first 200 rows, so a column that is
# entirely NA within those rows reads as logical. The row count printed under each file is
# the number of records after the header, counted with count.fields() so that quoted
# fields spanning lines are counted once.
# =============================================================================

if (!requireNamespace("here", quietly = TRUE)) {
  stop("The here package is required: install.packages('here').")
}

LES_CODEBOOK_ROOT <- here::here()

# File-name globs listed for each paper, applied to the paper's results/ folder.
LES_CODEBOOK_PAPERS <- list(
  paper_1_transfer   = c("_*.csv", "*_decoding_*.csv"),
  paper_2_plasticity = c("_*.csv", "p2_*.csv")
)

# Files matched by a pattern above that are nevertheless left out.
LES_CODEBOOK_SKIP <- c("07_aperiodic_features.csv")

LES_CODEBOOK_DESCRIPTIONS <- file.path(LES_CODEBOOK_ROOT, "_shared", "R",
                                       "codebook_descriptions.csv")
LES_CODEBOOK_PENDING <- "(description pending)"
LES_CODEBOOK_NROWS   <- 200L   # rows read.csv() reads to infer a column's class

# --- Helpers -------------------------------------------------------------------
.les_glob_match <- function(pattern, x) grepl(utils::glob2rx(pattern), x)

# The CSVs a paper's codebook lists, sorted in a locale-independent order.
.les_codebook_files <- function(paper) {
  dir   <- file.path(LES_CODEBOOK_ROOT, paper, "results")
  files <- list.files(dir, pattern = "\\.csv$")
  if (!length(files)) return(character(0))
  hit <- Reduce(`|`, lapply(LES_CODEBOOK_PAPERS[[paper]], .les_glob_match, x = files),
                init = logical(length(files)))
  sort(files[hit & !files %in% LES_CODEBOOK_SKIP], method = "radix")
}

.les_read_descriptions <- function() {
  if (!file.exists(LES_CODEBOOK_DESCRIPTIONS)) {
    stop("Description table not found: ", LES_CODEBOOK_DESCRIPTIONS)
  }
  # na.strings = character(0): the literal text 'NA' is part of several descriptions.
  d <- utils::read.csv(LES_CODEBOOK_DESCRIPTIONS, stringsAsFactors = FALSE,
                       encoding = "UTF-8", na.strings = character(0))
  need <- c("paper", "file_pattern", "column", "description", "writer_script")
  miss <- setdiff(need, names(d))
  if (length(miss)) {
    stop("codebook_descriptions.csv lacks the column(s): ", paste(miss, collapse = ", "))
  }
  d[need]
}

# Description rows that apply to one file of one paper, most specific first: an exact
# name before a glob, and among globs the one with more literal characters.
.les_rows_for_file <- function(desc, paper, file) {
  d <- desc[desc$paper == paper, , drop = FALSE]
  if (!nrow(d)) return(d)
  hit <- vapply(d$file_pattern, .les_glob_match, logical(1), x = file)
  d <- d[hit, , drop = FALSE]
  if (!nrow(d)) return(d)
  literal <- nchar(gsub("[*?]", "", d$file_pattern))
  d[order(d$file_pattern != file, -literal), , drop = FALSE]
}

# Column names and the class read.csv() infers from the first LES_CODEBOOK_NROWS rows.
.les_column_classes <- function(path) {
  d <- utils::read.csv(path, nrows = LES_CODEBOOK_NROWS, stringsAsFactors = FALSE,
                       check.names = FALSE)
  vapply(d, function(col) class(col)[1], character(1))
}

# Records after the header. count.fields() honours quoting, so a quoted field that
# spans lines is counted once.
.les_count_rows <- function(path) {
  n <- length(utils::count.fields(path, sep = ",", quote = "\"", comment.char = "",
                                  blank.lines.skip = TRUE))
  max(n - 1L, 0L)
}

# A value that is safe inside a Markdown table cell.
.les_md_cell <- function(x) {
  x <- gsub("[\r\n]+", " ", x)
  gsub("|", "\\|", x, fixed = TRUE)
}

# One '## file' section. Returns the Markdown lines and the columns left pending.
.les_codebook_section <- function(paper, file, desc) {
  path    <- file.path(LES_CODEBOOK_ROOT, paper, "results", file)
  classes <- tryCatch(.les_column_classes(path), error = function(e) NULL)
  if (is.null(classes)) {
    warning(paper, "/results/", file, " could not be read and was skipped.", call. = FALSE)
    return(list(lines = character(0), pending = character(0), columns = character(0),
                patterns = character(0)))
  }
  rows <- .les_rows_for_file(desc, paper, file)
  file_writer <- if (nrow(rows)) rows$writer_script[1] else LES_CODEBOOK_PENDING

  pending <- character(0)
  body <- character(0)
  for (col in names(classes)) {
    r <- rows[rows$column == col, , drop = FALSE]
    if (nrow(r)) {
      descr  <- r$description[1]
      writer <- r$writer_script[1]
    } else {
      descr  <- LES_CODEBOOK_PENDING
      writer <- file_writer
      pending <- c(pending, col)
    }
    body <- c(body, sprintf("| `%s` | %s | %s | %s |",
                            .les_md_cell(col), classes[[col]],
                            .les_md_cell(descr), .les_md_cell(writer)))
  }

  lines <- c(
    sprintf("## `%s`", file),
    "",
    sprintf("%d data row(s), %d column(s).", .les_count_rows(path), length(classes)),
    "",
    "| Column | Class | Description | Writer script |",
    "|---|---|---|---|",
    body,
    ""
  )
  # Described columns the file does not carry, reported so the table can be pruned or,
  # where a newer script version writes the column, left in place.
  extra <- setdiff(rows$column, names(classes))
  if (length(extra)) {
    message("[codebook] ", paper, "/results/", file, ": described but absent: ",
            paste(extra, collapse = ", "))
  }
  list(lines = lines, pending = pending, columns = names(classes),
       patterns = unique(rows$file_pattern))
}

.les_codebook_header <- function(paper) {
  c(
    sprintf("# Codebook for `%s/results`", paper),
    "",
    paste0(
      "This file is machine-written by `_shared/R/write_codebook.R` and is not edited by ",
      "hand. It lists every manuscript-facing CSV in this folder and, for each column, the ",
      "R class that `read.csv()` infers from the first ", LES_CODEBOOK_NROWS, " rows (a ",
      "column that is entirely NA within those rows reads as `logical`), a description ",
      "taken from `_shared/R/codebook_descriptions.csv`, and the script that writes the ",
      "file. To regenerate it after pulling the CSVs from the cluster, run ",
      "`Rscript _shared/R/write_codebook.R` from the project root. Descriptions are added ",
      "or corrected in `_shared/R/codebook_descriptions.csv`; a column still marked ",
      "`", LES_CODEBOOK_PENDING, "` needs one. The row counts are those of the files ",
      "present when the codebook was generated."
    ),
    ""
  )
}

# --- Main ----------------------------------------------------------------------
# Writes results/CODEBOOK.md for each paper and returns, invisibly, a list of the
# columns still lacking a description, keyed by paper and file. Warnings are the only
# signal for missing descriptions; the function never stops on one.
les_write_codebook <- function(papers = names(LES_CODEBOOK_PAPERS)) {
  desc <- .les_read_descriptions()
  pending_all <- list()

  for (paper in papers) {
    files <- .les_codebook_files(paper)
    lines <- .les_codebook_header(paper)
    pending <- list()
    seen_patterns <- character(0)

    for (file in files) {
      sec <- .les_codebook_section(paper, file, desc)
      lines <- c(lines, sec$lines)
      if (length(sec$pending)) pending[[file]] <- sec$pending
      seen_patterns <- c(seen_patterns, sec$patterns)
    }

    # Description rows whose pattern matches no file on disk.
    d <- desc[desc$paper == paper, , drop = FALSE]
    stale <- setdiff(unique(d$file_pattern), unique(seen_patterns))
    if (length(stale)) {
      message("[codebook] ", paper, ": description pattern(s) matching no file: ",
              paste(stale, collapse = ", "))
    }

    out <- file.path(LES_CODEBOOK_ROOT, paper, "results", "CODEBOOK.md")
    con <- file(out, open = "wb")
    writeLines(enc2utf8(lines), con, sep = "\n", useBytes = TRUE)
    close(con)
    message(sprintf("[codebook] %s: %d file(s), %d column(s) pending -> %s",
                    paper, length(files), sum(lengths(pending)), out))
    pending_all[[paper]] <- pending
  }

  # Final warning listing every pending column, so the table can be completed.
  n_pending <- sum(vapply(pending_all, function(p) sum(lengths(p)), integer(1)))
  if (n_pending > 0) {
    detail <- unlist(lapply(names(pending_all), function(paper) {
      p <- pending_all[[paper]]
      vapply(names(p), function(f) sprintf("%s/results/%s: %s", paper, f,
                                            paste(p[[f]], collapse = ", ")),
             character(1))
    }), use.names = FALSE)
    old <- options(warning.length = 8170L)
    on.exit(options(old), add = TRUE)
    warning(sprintf("%d column(s) still marked '%s':\n  %s", n_pending,
                    LES_CODEBOOK_PENDING, paste(detail, collapse = "\n  ")),
            call. = FALSE)
  }
  invisible(pending_all)
}

if (sys.nframe() == 0L) les_write_codebook()
