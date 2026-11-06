#!/bin/bash
# Compare a new case's ELM output against a base case with cprnc
# (tier 2 regression test, step 6 of notes/test_workflow.md).
#
# Usage: ./cprnc_compare.sh <base_case> <new_case> [path/to/machine.env]
#   base_case  the reference case, e.g. TG_NLDAS2_5d_2000_baseline
#   new_case   the case to compare, e.g. TG_NLDAS2_5d_2000_new
#              Both are looked up under $OUTPUT_ROOT; an absolute path to a case
#              directory also works.
#   env file   defaults to ../run_scripts/config/${MACHINE_ENV:-pm-cpu}.env
#              (only OUTPUT_ROOT is used).
#
# Compares the restart file (*.elm.r.*, full model state) first, then the daily
# (h0) and hourly (h1) history files. Files are paired by the part of the name
# after the case name, so <base_case>.elm.r.2000-01-06-00000.nc is compared with
# <new_case>.elm.r.2000-01-06-00000.nc.
# The full cprnc output goes to <new_case>/cprnc/vs_<base_case>.*.txt.
# Runs cprnc -m (as CIME's regression tests do). Variables present in only one
# file, e.g. a restart field the new code adds, are listed but don't count as a
# difference.
# Exit status: 0 if every pair is identical, 1 otherwise.
set -euo pipefail

# --- Hardcoded settings ---------------------------------------------------------
CPRNC=/global/cfs/cdirs/e3sm/tools/cprnc/cprnc
FILE_TYPES=(elm.r elm.h0 elm.h1)   # restart first: it holds the whole model state

# --- Arguments and environment --------------------------------------------------
if [ $# -lt 2 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi
BASE_ARG=$1
NEW_ARG=$2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${3:-$SCRIPT_DIR/../run_scripts/config/${MACHINE_ENV:-pm-cpu}.env}"
if [ ! -f "$ENV_FILE" ]; then
    echo "Env file not found: $ENV_FILE" >&2
    exit 1
fi
set -a; source "$ENV_FILE"; set +a
: "${OUTPUT_ROOT:?must be set in $ENV_FILE}"

if [ ! -x "$CPRNC" ]; then
    echo "cprnc not found or not executable: $CPRNC" >&2
    exit 1
fi

# A case argument is a name under $OUTPUT_ROOT or an absolute case directory
case_dir() {
    if [[ "$1" = /* ]]; then echo "${1%/}"; else echo "$OUTPUT_ROOT/$1"; fi
}
BASE_DIR=$(case_dir "$BASE_ARG")
NEW_DIR=$(case_dir "$NEW_ARG")
BASELINE_CASE=$(basename "$BASE_DIR")
NEW_CASE=$(basename "$NEW_DIR")

for d in "$BASE_DIR" "$NEW_DIR"; do
    if [ ! -d "$d/run" ]; then
        echo "Run directory not found: $d/run" >&2
        exit 1
    fi
    # Warn if the run didn't finish; its output may be incomplete
    if ! grep -q "case.run success" "$d/case_scripts/CaseStatus" 2>/dev/null; then
        echo "WARNING: no 'case.run success' in $d/case_scripts/CaseStatus" >&2
    fi
done

if [ "$NEW_DIR" = "$BASE_DIR" ]; then
    echo "The base and new case are the same: $NEW_DIR" >&2
    exit 1
fi

LOG_DIR=$NEW_DIR/cprnc
mkdir -p "$LOG_DIR"

echo "Base:     $BASE_DIR"
echo "Compare:  $NEW_DIR"
for d in "$BASE_DIR" "$NEW_DIR"; do
    commit_file=$d/case_scripts/E3SM_COMMIT.txt
    if [ -f "$commit_file" ]; then
        echo "  $(basename "$d"): $(grep -m1 -i 'commit' "$commit_file")"
    fi
done
echo

# --- Compare --------------------------------------------------------------------
n_same=0
n_diff=0
n_missing=0
n_err=0
shopt -s nullglob
for type in "${FILE_TYPES[@]}"; do
    base_files=("$BASE_DIR/run/$BASELINE_CASE.$type."*.nc)
    if [ ${#base_files[@]} -eq 0 ]; then
        echo "[$type] no baseline files"
        continue
    fi
    for base_file in "${base_files[@]}"; do
        suffix=${base_file##*/$BASELINE_CASE}           # .elm.r.2000-01-06-00000.nc
        new_file=$NEW_DIR/run/$NEW_CASE$suffix
        label=${suffix#.}
        if [ ! -f "$new_file" ]; then
            echo "MISSING    $label (no $new_file)"
            n_missing=$((n_missing + 1))
            continue
        fi
        log=$LOG_DIR/vs_${BASELINE_CASE}${suffix%.nc}.txt
        # -m: compare records by position, not by matching "time" values.
        # Restart files have no time dimension and cprnc aborts without it.
        "$CPRNC" -m "$base_file" "$new_file" > "$log" 2>&1 || true
        # Variables present in only one file (e.g. a restart field added by the
        # new code) are skipped by cprnc; list them so they aren't overlooked.
        only_one=$(grep -E "Could not find match|not found on file" "$log" || true)
        # cprnc's summary ends with "files seem to be IDENTICAL" or "... DIFFERENT"
        if grep -q "seem to be IDENTICAL" "$log"; then
            echo "IDENTICAL  $label"
            n_same=$((n_same + 1))
        elif grep -q "seem to be DIFFERENT" "$log"; then
            echo "DIFFERENT  $label   -> $log"
            grep -E "diff_field|RMS|had non-zero" "$log" | head -20 | sed 's/^/    /'
            n_diff=$((n_diff + 1))
        else
            echo "ERROR      $label   (cprnc gave no summary) -> $log"
            tail -5 "$log" | sed 's/^/    /'
            n_err=$((n_err + 1))
        fi
        [ -n "$only_one" ] && echo "$only_one" | sed 's/^ */    in one file only: /'
    done
done

echo
echo "Summary: $n_same identical, $n_diff different, $n_missing missing, $n_err errors"
echo "Full cprnc output: $LOG_DIR"
if [ $n_same -eq 0 ]; then
    echo "No files were compared." >&2
    exit 1
fi
[ $n_diff -eq 0 ] && [ $n_missing -eq 0 ] && [ $n_err -eq 0 ]
