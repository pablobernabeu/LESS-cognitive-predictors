#!/usr/bin/env bash
# =============================================================================
# deploy_to_cluster.sh  --  copy code to the cluster without breaking a live job
# -----------------------------------------------------------------------------
# WHY THIS EXISTS
# Rscript does not read a script in one go. It parses and evaluates one expression
# at a time, holding a byte offset into the file, so overwriting that file while a
# job is running shifts the content underneath the offset and the interpreter dies
# on a fragment of a line. HPC_RUNBOOK.md states the rule; this script enforces it,
# because the failure is silent until the job ends and expensive when the job is a
# fortnight of sampling.
#
# It also enforces the one absolute prohibition in this project. The decoding
# fingerprint is computed over 09_run_decoding.R and 08_decoding.slurm, so copying
# either of them invalidates every banked permutation. That pair is refused
# unconditionally unless LES_ALLOW_DECODING_DEPLOY=1 is exported deliberately.
#
# USAGE
#   bash _shared/hpc/deploy_to_cluster.sh <target> [ssh-alias]
#     target       paper_1_transfer | paper_2_plasticity | _shared | all
#     ssh-alias    defaults to $LES_CLUSTER_HOST, else arc-agent
#
#   LES_DEPLOY_ANYWAY=1        deploy even though a job of that paper is live.
#                              Only for a job you have checked by hand.
#   LES_ALLOW_DECODING_DEPLOY=1  include the decoding pair. Read the note above.
#
# WHAT IT CHECKS, IN ORDER
#   1. every file is LF-only, because a CRLF job script fails on the cluster with
#      "$'\r': command not found" and a CRLF R script fails less obviously;
#   2. no job of the target paper is running or pending;
#   3. the decoding pair is excluded unless explicitly allowed;
#   4. after copying, every file's md5 matches on both sides.
#
# It copies code only. Nothing here touches data/, the store, or any fit.
# =============================================================================
set -o errexit
set -o nounset
set -o pipefail

TARGET="${1:-}"
HOST="${2:-${LES_CLUSTER_HOST:-arc-agent}}"
REMOTE_ROOT="new_LESS"

case "$TARGET" in
  paper_1_transfer|paper_2_plasticity|_shared|all) ;;
  *)
    echo "usage: bash _shared/hpc/deploy_to_cluster.sh <paper_1_transfer|paper_2_plasticity|_shared|all> [ssh-alias]" >&2
    exit 2
    ;;
esac

cd "$(dirname "$0")/../.."          # project root, wherever the clone lives

# --- (1) The file list -------------------------------------------------------
# Job scripts and R scripts only. Manuscripts, results and figures stay on the dev
# box; the cluster never renders and never reads them.
collect() {
  case "$1" in
    paper_1_transfer)
      ls paper_1_transfer/scripts/*.R paper_1_transfer/hpc/*.slurm paper_1_transfer/hpc/*.sh 2>/dev/null || true ;;
    paper_2_plasticity)
      ls paper_2_plasticity/scripts/*.R paper_2_plasticity/hpc/*.slurm paper_2_plasticity/hpc/*.sh 2>/dev/null || true ;;
    _shared)
      ls _shared/R/*.R _shared/hpc/*.sh _shared/hpc/*.slurm 2>/dev/null || true ;;
  esac
}

if [ "$TARGET" = "all" ]; then
  FILES=$(collect paper_1_transfer; collect paper_2_plasticity; collect _shared)
else
  FILES=$(collect "$TARGET")
fi

# This script deploys itself under the _shared target, which is harmless, but the
# reconnaissance directory is one-off probing that the cluster does not need.
FILES=$(printf '%s\n' "$FILES" | grep -v '/reconnaissance/' || true)

[ -n "$FILES" ] || { echo "nothing to deploy for target '$TARGET'" >&2; exit 1; }

# --- (2) The decoding prohibition -------------------------------------------
DECODING='paper_1_transfer/scripts/09_run_decoding\.R|paper_1_transfer/hpc/08_decoding\.slurm'
if printf '%s\n' "$FILES" | grep -qE "$DECODING"; then
  if [ "${LES_ALLOW_DECODING_DEPLOY:-0}" = "1" ]; then
    echo "WARNING: LES_ALLOW_DECODING_DEPLOY=1, so the decoding pair WILL be copied."
    echo "         Every banked permutation is invalidated by this."
  else
    echo "note: holding back the decoding pair (export LES_ALLOW_DECODING_DEPLOY=1 to include it)"
    FILES=$(printf '%s\n' "$FILES" | grep -vE "$DECODING")
  fi
fi

# --- (3) Line endings --------------------------------------------------------
# Only the shell-executed files are checked. A CRLF job script fails on the cluster
# with "$'\r': command not found", whereas R reads CRLF without complaint, and some
# .R files in the working copy carry it because of the checkout's autocrlf setting.
# Counting bytes before and after stripping CR is unambiguous, where a grep for the
# character is at the mercy of the platform's text-mode handling.
has_cr() {
  [ "$(tr -d '\r' < "$1" | wc -c)" -ne "$(wc -c < "$1")" ]
}
CRLF=""
for f in $FILES; do
  case "$f" in
    *.sh|*.slurm) has_cr "$f" && CRLF="$CRLF $f" ;;
  esac
done
if [ -n "$CRLF" ]; then
  echo "refusing to deploy: these job scripts carry CRLF line endings and would fail" >&2
  echo "on the cluster. Convert them with  sed -i 's/\r$//' <file>  and try again:" >&2
  printf '  %s\n' $CRLF >&2
  exit 1
fi

# --- (4) Live jobs -----------------------------------------------------------
# A job's name says which paper it belongs to (p1_*, p2_*), which is coarser than
# mapping each job to the scripts it executes but errs the safe way: a live job of
# the same paper blocks the whole target.
case "$TARGET" in
  paper_1_transfer)   PREFIX='^p1_' ;;
  paper_2_plasticity) PREFIX='^p2_' ;;
  *)                  PREFIX='^p[12]_' ;;
esac

LIVE=$(ssh "$HOST" "squeue -M htc -u \$(whoami) -h -o '%i %T %j' 2>/dev/null; \
                    squeue -M arc -u \$(whoami) -h -o '%i %T %j' 2>/dev/null" \
       | awk '{print $1, $2, $3}' | grep -E " (RUNNING|PENDING|SUSPENDED) " \
       | awk -v p="$PREFIX" '$3 ~ p' || true)

if [ -n "$LIVE" ]; then
  echo "these jobs of the target are live:" >&2
  printf '%s\n' "$LIVE" | sed 's/^/  /' >&2
  if [ "${LES_DEPLOY_ANYWAY:-0}" != "1" ]; then
    echo "refusing to deploy. Wait for them, or export LES_DEPLOY_ANYWAY=1 once you have" >&2
    echo "checked that none of them executes a file in this list." >&2
    exit 1
  fi
  echo "LES_DEPLOY_ANYWAY=1, so continuing."
fi

# --- (5) Copy, then verify ---------------------------------------------------
echo "deploying $(printf '%s\n' "$FILES" | wc -l | tr -d ' ') files to $HOST:$REMOTE_ROOT/"
# One tar stream over one connection, rather than one scp per file. Ninety separate
# scp calls take minutes of connection setup, and a per-file loop invites the stdin
# trap: ssh reads standard input by default, so an ssh inside a loop fed by a pipe
# swallows the rest of the list and the loop stops after one iteration in silence.
DIRS=$(for f in $FILES; do dirname "$f"; done | sort -u | tr '\n' ' ')
tar -cf - $FILES | ssh "$HOST" "mkdir -p '$REMOTE_ROOT' && cd '$REMOTE_ROOT' && mkdir -p $DIRS && tar -xf -"

echo "verifying checksums"
# md5sum on Windows defaults to binary mode and writes "hash *path", where GNU
# coreutils on the cluster writes "hash  path". Normalising the separator is what
# makes the two comparable; without it every line differs and the check cries wolf.
norm_sums() { sed -e 's/ \*/  /' | sort -k2; }
LOCAL_SUMS=$(printf '%s\n' "$FILES" | xargs md5sum | norm_sums)
REMOTE_SUMS=$(printf '%s\n' "$FILES" | ssh "$HOST" "cd '$REMOTE_ROOT' && xargs md5sum" | norm_sums)
if [ "$LOCAL_SUMS" = "$REMOTE_SUMS" ]; then
  echo "all files match."
else
  echo "MISMATCH after copying. Differences:" >&2
  diff <(printf '%s\n' "$LOCAL_SUMS") <(printf '%s\n' "$REMOTE_SUMS") >&2 || true
  exit 1
fi
