#!/bin/bash
# Compare a test case's ELM output against the baseline case with cprnc
# (tier 2 regression test, step 6 of notes/test_workflow.md).
#
# Usage: ./cprnc_compare.sh <case_name> [path/to/machine.env]
#   case_name  the case to compare, e.g. TG_NLDAS2_5d_2000_new. It is looked up
#              under $OUTPUT_ROOT; an absolute path to a case directory also works.
#   env file   defaults to ../run_scripts/config/${MACHINE_ENV:-pm-cpu}.env
#              (only OUTPUT_ROOT is used).
#
# Compares the restart file (*.elm.r.*, full model state) first, then the daily
# (h0) and hourly (h1) history files. Files are paired by the part of the name
# after the case name, so baseline.elm.r.2000-01-06-00000.nc is compared with
# <case_name>.elm.r.2000-01-06-00000.nc.
# The full cprnc output goes to <case>/cprnc/vs_<BASELINE_CASE>.*.txt.
# Exit status: 0 if every pair is identical, 1 otherwise.
set -euo pipefail

# --- Hardcoded settings ---------------------------------------------------------
CPRNC=/global/cfs/cdirs/e3sm/tools/cprnc/cprnc
BASELINE_CASE=TG_NLDAS2_5d_2000_baseline
FILE_TYPES=(elm.r elm.h0 elm.h1)   # restart first: it holds the whole model state

# --- Arguments and environment --------------------------------------------------
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi
CASE_ARG=$1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${2:-$SCRIPT_DIR/../run_scripts/config/${MACHINE_ENV:-pm-cpu}.env}"
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

if [[ "$CASE_ARG" = /* ]]; then
    NEW_DIR=${CASE_ARG%/}
else
    NEW_DIR=$OUTPUT_ROOT/$CASE_ARG
fi
NEW_CASE=$(basename "$NEW_DIR")
BASE_DIR=$OUTPUT_ROOT/$BASELINE_CASE

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

if [ "$NEW_CASE" = "$BASELINE_CASE" ]; then
    echo "The comparison case is the baseline itself: $NEW_CASE" >&2
    exit 1
fi

LOG_DIR=$NEW_DIR/cprnc
mkdir -p "$LOG_DIR"

echo "Baseline: $BASE_DIR"
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
        "$CPRNC" "$base_file" "$new_file" > "$log" 2>&1 || true
        # cprnc's summary ends with "files seem to be IDENTICAL" or "... DIFFERENT"
        if grep -q "IDENTICAL" "$log"; then
            echo "IDENTICAL  $label"
            n_same=$((n_same + 1))
        else
            echo "DIFFERENT  $label   -> $log"
            # Show the summary lines with field-level diff counts
            grep -E "diff_field|DIFFERENT|different" "$log" | tail -10 | sed 's/^/    /'
            n_diff=$((n_diff + 1))
        fi
    done
done

echo
echo "Summary: $n_same identical, $n_diff different, $n_missing missing"
echo "Full cprnc output: $LOG_DIR"
if [ $n_same -eq 0 ]; then
    echo "No files were compared." >&2
    exit 1
fi
[ $n_diff -eq 0 ] && [ $n_missing -eq 0 ]
