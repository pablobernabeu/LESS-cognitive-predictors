# Hand package resolution to renv only once renv has a library to resolve against.
#
# renv/activate.R is tracked but renv/library is not, because renv/.gitignore excludes it,
# so a fresh clone carries the activation script and an empty library. The guard used to
# test only for the script, so it fired in exactly the situation where renv cannot help:
# renv::load() replaces .libPaths() with that empty project library and discards
# R_LIBS_USER, which on the cluster is the project library at $LES_BASE/Rlib/R-4.5. Every
# library(brms) and library(here) then fails, in the SLURM jobs and in the Quarto and knitr
# sessions alike. Testing for a populated library as well keeps R on the system library
# until renv::restore() has actually built the project one.
#
# The renv cache is deliberately not set here. It belongs outside the working copy and is a
# per-machine choice: on the cluster set it in _shared/hpc/arc_env.sh, for instance
# export RENV_PATHS_CACHE="${LES_BASE}/renv-cache", because $HOME there is quota-limited.
# The relative path this file used to set resolved against whatever directory R happened to
# start in, so the cache landed inside the working copy rather than beside it.
if (file.exists("renv/activate.R") &&
    length(list.files(file.path("renv", "library"))) > 0L) {
  source("renv/activate.R")
}
