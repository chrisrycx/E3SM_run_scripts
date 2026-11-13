#!/bin/bash
# Make a sweep variant of a built case without rebuilding: clone it with
# `create_clone --keepexe`, change the ELM namelist, then run.
#
# Usage: TAG=<tag> [FSCA=<value>] [EXTRA_NML=<lines>] [BASE=<case>] \
#            ./clone_variant.sh [path/to/machine.env]
#   BASE      built case to clone (default: TG_NLDAS2_WY2012_base), found at
#             $OUTPUT_ROOT/$BASE/case_scripts
#   TAG       required. New case is <BASE>_<TAG>, e.g. TG_NLDAS2_WY2012_base_NY07,
#             so the name shows which build (base case) it used. An existing case with
#             that name is deleted first.
#   FSCA      optional new snow_fsca_param (bare, quotes added for strings, as in
#             TG_NLDAS2_WY20XX.sh). Unset = keep the base case's value.
#   EXTRA_NML optional user_nl_elm lines (newlines allowed). Any variable set here
#             replaces that variable's line from the base case.
#
# Sweep examples:
#   for f in NY07 Helbig21 CZ26; do TAG=$f FSCA=$f ./clone_variant.sh; done
#   TAG=spheroid EXTRA_NML="snow_shape = 'spheroid'" ./clone_variant.sh
#
# Run: inside salloc, runs now with `case.submit --no-batch` (one after another in a
# loop). On a login node, submits a batch job (debug queue, set in the base case),
# so a loop queues all variants at once. NOSUBMIT=1 only creates the case.
#
# How --keepexe works (CIME/case/case_clone.py): the clone's EXEROOT points to the
# base case's bld/ directory and BUILD_COMPLETE=TRUE, so there's no build. That means:
#   - Only run-time changes are allowed: user_nl_elm, and env_run.xml settings
#     (STOP_N, history, ...). Anything that needs a build (NTASKS, compset, source
#     code) needs a new base case.
#   - The clones share the base executable. Don't delete or rebuild the base case
#     (rerunning TG_NLDAS2_WY20XX.sh with TAG=base deletes it) while clones still need it.
#   - create_clone takes the clone's case name from the last part of its directory
#     path, so its case scripts can't go in <case>/case_scripts like the base case's
#     (the case would be named "case_scripts"). Instead the case directory is
#     $OUTPUT_ROOT/<case> itself, with the run dir inside it:
#       case scripts: $OUTPUT_ROOT/<case>/
#       run dir:      $OUTPUT_ROOT/<case>/run/   (same place as for base cases)
#     and no bld/, since the clone uses the base case's.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${1:-$SCRIPT_DIR/../config/${MACHINE_ENV:-pm-cpu}.env}"

if [ ! -f "$ENV_FILE" ]; then
    echo "Env file not found: $ENV_FILE" >&2
    exit 1
fi
set -a; source "$ENV_FILE"; set +a

: "${E3SM_ROOT:?must be set in $ENV_FILE}"
: "${OUTPUT_ROOT:?must be set in $ENV_FILE}"
: "${TAG:?set TAG for the new case, e.g. TAG=NY07}"

module load python/3.13

# --- Cases --------------------------------------------------------------------
BASE="${BASE:-TG_NLDAS2_WY2012_base}"
base_scripts_dir=$OUTPUT_ROOT/$BASE/case_scripts
if [ ! -d "$base_scripts_dir" ]; then
    echo "Base case not found: $base_scripts_dir" >&2
    exit 1
fi
if ! grep -q "case.build success" "$base_scripts_dir/CaseStatus"; then
    echo "Base case $BASE hasn't built successfully; build it first." >&2
    exit 1
fi

CASE_NAME="${BASE}_${TAG}"
case_scripts_dir=$OUTPUT_ROOT/$CASE_NAME
run_dir=$case_scripts_dir/run

# also clears the older layout, which kept the case scripts in $OUTPUT_ROOT/clones/
for d in "$case_scripts_dir" "$OUTPUT_ROOT/clones/$CASE_NAME"; do
    if [ -d "$d" ]; then
        echo "Deleting old case directory: $d"
        rm -rf "$d"
    fi
done

# --- Clone --------------------------------------------------------------------
"$E3SM_ROOT/cime/scripts/create_clone" --clone "$base_scripts_dir" \
    --case "$case_scripts_dir" --keepexe --cime-output-root "$OUTPUT_ROOT"
cd "$case_scripts_dir"
./xmlchange RUNDIR="$run_dir"

# --- ELM namelist: start from the base case's user_nl_elm (copied by create_clone) ---
# Remove a variable's line(s) from user_nl_elm, so a new value doesn't duplicate it
drop_nml_var() {
    sed -i "/^[[:space:]]*$1[[:space:]]*=/d" user_nl_elm
}

FSCA="${FSCA:-}"
if [ -n "$FSCA" ]; then
    if [[ "$FSCA" =~ ^[0-9]+$ ]]; then FSCA_NML="$FSCA"; else FSCA_NML="'$FSCA'"; fi
    drop_nml_var snow_fsca_param
    echo "snow_fsca_param   = ${FSCA_NML}" >> user_nl_elm
fi

EXTRA_NML="${EXTRA_NML:-}"
if [ -n "$EXTRA_NML" ]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*([A-Za-z0-9_]+)[[:space:]]*= ]]; then
            drop_nml_var "${BASH_REMATCH[1]}"
        fi
    done <<< "$EXTRA_NML"
    printf '%s\n' "$EXTRA_NML" >> user_nl_elm
fi

./case.setup
./preview_namelists   # fails early on invalid namelist options

# Provenance: the base case's record (same executable) plus what this clone changed
{
    cat "$base_scripts_dir/E3SM_COMMIT.txt"
    echo
    echo "# clone (create_clone --keepexe, no rebuild)"
    echo "cloned from: $base_scripts_dir"
    echo "EXEROOT: $(./xmlquery --value EXEROOT)"
    echo "date: $(date -Iseconds)"
    echo "TAG: $TAG"
    echo "FSCA: ${FSCA:-(base value)}"
    echo "EXTRA_NML: ${EXTRA_NML:-(none)}"
} > E3SM_COMMIT.txt

echo
echo "user_nl_elm for $CASE_NAME:"
cat user_nl_elm

# --- Run ----------------------------------------------------------------------
if [ -n "${NOSUBMIT:-}" ]; then
    echo "Case ready (not submitted): $case_scripts_dir"
elif [ -n "${SLURM_JOB_ID:-}" ]; then
    ./case.submit --no-batch
else
    ./case.submit
fi
