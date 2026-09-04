# `_shared/hpc` — cluster environment and its checks

Code shared by both papers' SLURM jobs. Everything here is infrastructure: the runtime
environment the jobs run in, and the checks on that environment. No model is fitted from
this directory. The fitting stages are in `paper_1_transfer/hpc/` and
`paper_2_plasticity/hpc/`, whose READMEs hold the submission recipes and the stage tables.

See [`../../HPC_RUNBOOK.md`](../../HPC_RUNBOOK.md) for the project layout on the
cluster and the transfer/render workflow.

Nothing here reads the study's data except `validate_rseeg.R`, which reads a file Paper
2's script 03 has already written. The R library, CmdStan and the compiler flags these
scripts assume are provisioned by `../install_bayesian_dependencies.R` and are described
in section 0 of the runbook. Path resolution goes through `LES_DATA_ROOT` and
`LES_STORE`, both exported by `arc_env.sh`.

## In use

| File | What it is |
|------|------------|
| `arc_env.sh` | Sourced at the top of every job script in both papers and the single source of truth for the cluster layout. It `module load`s R, points `R_LIBS_USER`, `CMDSTAN`, `LES_DATA_ROOT` and `LES_STORE` at the project `/data` space, pins `CXXFLAGS_OPTIM = -O1` to avoid the GCC 14.2.0 `reduce_sum` internal compiler error, and `cd`s to the code root. A path changed here changes everywhere. |
| `check_arc_env.R` | One-shot sanity check. Prints where the paths resolve, which library R is using, and whether CmdStan really compiles and samples a trivial model. Run it by hand after sourcing `arc_env.sh`, or let `rebuild_cmdstan.slurm` run it. Its closing PASS/FAIL covers the compile alone, so read the lines above it as well. |
| `rebuild_cmdstan.slurm` | Run once after CmdStan is installed or moved. The precompiled headers bake in the install path, so a relocated CmdStan has to be rebuilt, and the rebuild is too memory-hungry for a login node. Its log goes to `paper_1_transfer/hpc/logs/`. |
| `validate_rseeg.R` | Checks `resting_state_eeg.rds` after Paper 2's script 03: band power and IAF by condition, the Berger effect, and the eyes-closed IAF range. Nothing invokes it automatically, so run it yourself after stage 1c. |

One level up, `_shared/install_bayesian_dependencies.R` provisions the R library and
the CmdStan toolchain that `arc_env.sh` then points at.

## Reconnaissance scripts, outside every pipeline

Six one-off scripts from June 2026 record how the resting-state recordings were located
and what format they turned out to be in. They now sit in
[`reconnaissance/`](reconnaissance/README.md), which explains what each one settled.
Nothing in either paper references any of them. They are kept as a record of how the data
were found, and not because anything needs them.
