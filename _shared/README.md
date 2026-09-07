# `_shared` — code both papers use

Everything here exists so that a decision is made once and applied to both manuscripts.
Path resolution, the brms and Stan configuration, the convergence thresholds, the
read-only contract over `data/`, the provenance record and the participant-flow figure
are all defined here and sourced by each paper's `scripts/`. No analysis is run from this
folder and no model is fitted in it.

| Path | What it holds |
|------|---------------|
| [`R/`](R/README.md) | The seven modules the pipelines source, and the opt-in codebook writer. See its readme for what each one does. |
| [`hpc/`](hpc/README.md) | The cluster environment script every SLURM job sources, and the checks that run against it. |
| [`hpc/reconnaissance/`](hpc/reconnaissance/README.md) | Six one-off scripts kept as the record of how the resting-state EEG was located. Outside every pipeline. |
| `install_bayesian_dependencies.R` | Bootstraps an unpinned R library and CmdStan toolchain where none exists yet, as a cluster job. The reproduction route is `hpc/00_restore_environment.slurm`, which restores `../renv.lock` and builds the recorded CmdStan. |

## Where the data are

`../data/` holds every input, and **no pipeline may write inside it**. That contract is
enforced at run time by `les_assert_readonly_data()` in
[`R/03_data_manifest.R`](R/03_data_manifest.R), which is called on every pipeline write
path and stops the script if the path resolves inside `data/`. Derived datasets go to
`paper_1_transfer/data_derived/` or `paper_2_plasticity/data_derived/` instead, neither of
which is in version control.

On the cluster the same tree is reached through `LES_DATA_ROOT`, and results through
`LES_STORE`, both exported by [`hpc/arc_env.sh`](hpc/arc_env.sh). Locally both resolve
relative to the project root, which [`R/00_paths.R`](R/00_paths.R) finds by searching
upwards for `LESS Project.Rproj`. No R script hard-codes an absolute path; the cluster root
is set once, in `hpc/arc_env.sh`.

## Dependencies

The R packages are pinned in `../renv.lock`, which describes the **cluster** fitting
environment (Linux, R 4.5.1) and is not meant to be restored on the rendering box. Four of
the packages are not on CRAN; `../README.md` names their sources. CmdStan and the GCC
toolchain are not R packages and so appear in no lockfile; they are set in
[`hpc/arc_env.sh`](hpc/arc_env.sh), together with the `-O1` build flag that works around a
GCC 14.2.0 compiler crash, which that file's header explains.

## Reproducing a run

The order is the same for both papers: rebuild the recorded environment once with
`hpc/00_restore_environment.slurm` (`install_bayesian_dependencies.R` is the unpinned
bootstrap for a library where none exists), then run that paper's numbered `scripts/` in
order, with the heavy stages submitted as the SLURM jobs in its `hpc/`. Each paper's
readme has the stage table and the submission recipe. Every fitting run writes
`results/_provenance.csv` through [`R/04_provenance.R`](R/04_provenance.R), which holds
the R and platform versions, the versions of every package in `LES_PROVENANCE_PKGS`
(`_shared/R/04_provenance.R`), the CmdStan version and the seeds. Where any account of
the environment disagrees with that file, the file is right.
