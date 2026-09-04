# `_shared/hpc/reconnaissance` — how the resting-state EEG was located

Six scripts from June 2026, kept as the record of how the resting-state recordings were
found and what format they turned out to be in. **None of them is part of any pipeline.**
Nothing in either paper sources, calls or imports them, no SLURM job submits them, and no
result in either manuscript depends on them. They are here so that the reasoning behind
`paper_2_plasticity/scripts/03_extract_resting_state_eeg.R` is recoverable, and for no
other purpose. Deleting the folder would break nothing and would lose that record.

They were moved here from `_shared/hpc/` in September 2026, so that the parent folder
holds only the environment script and the checks that run against it.

## Data, dependencies, reproducibility

Every one of these scripts prints to stdout and writes no file. Each reads either the
study's own resting-state exports under
`data/raw data/EEG/Session 2/Export/<ppt>_RS_eyes_{closed,open}.{txt,vhdr}`, or the OSF
project `tq7vy` over the network. Run one, if you want to, with the cluster environment
sourced first:

```bash
source _shared/hpc/arc_env.sh
Rscript _shared/hpc/reconnaissance/probe_rseeg5.R
```

`probe_rseeg2.R` and `probe_rseeg4_osf.R` need outbound network access. The rest read
local files only. Each carries a STATUS note in its header saying what it settled and
what superseded it.

## What each one settled

| File | What it asked, and what it found |
|------|----------------------------------|
| `probe_rseeg.R` | First pass at the resting-state import. Superseded once the recordings were located. |
| `probe_rseeg2.R` | Is OSF project `tq7vy` resting-state or task EEG? Task EEG. The OSF route was abandoned. |
| `probe_rseeg3.R` | Characterises the local resting-state files on ARC. Established that `eegUtils` cannot read them. |
| `probe_rseeg4_osf.R` | OSF coverage and file format for the `rs-` files. Closed the OSF route for good. |
| `probe_rseeg5.R` | Prototype of the base-R read plus Welch PSD that script 03 grew from. |
| `dbg_rseeg.R` | One-file check of the resting-state channel labelling. |

The short version is that the recordings are local, in the task-EEG tree, and not on OSF,
and that they are BrainVision ASCII exports which `eegUtils` cannot read.
`paper_2_plasticity/scripts/03_extract_resting_state_eeg.R` therefore parses them in base
R and computes its own Welch PSD. That script is the only implementation that matters.

There is one trap. `probe_rseeg5.R` still defines `welch_psd`, `les_band_power` and
`les_iaf` under the production names, so sourcing it in a session where script 03 is
already loaded will silently shadow the real functions. Run it in a fresh session or not
at all.
