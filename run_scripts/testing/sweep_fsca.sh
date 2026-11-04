#!/bin/bash
# fSCA sweep at Tony Grove: one snow season for each snow_fsca_param scheme.
# Builds the base case if needed (TG_NLDAS2_WY20XX.sh), then makes and runs one clone
# per variant (clone_variant.sh), with no further builds. See notes/test_workflow.md, tier 3.
#
# Usage: [WY=<year>] [BASE_TAG=<tag>] [RERUN=<tags>|all] ./sweep_fsca.sh [path/to/machine.env]
#   WY        water year (default: 2012)
#   BASE_TAG  base case tag (default: base). The base case is TG_NLDAS2_WY<WY>_<BASE_TAG>,
#             and the variants are TG_NLDAS2_WY<WY>_<BASE_TAG>_<TAG>. Use a new BASE_TAG
#             for a new E3SM commit (e.g. after a bug fix), so the old sweep is kept.
#   RERUN     variants to redo even if finished or still marked running, e.g.
#             RERUN="NY07 CZ26", or RERUN=all
#
# Rerunning this script is safe and cheap. It:
#   - builds the base case only if it doesn't have a successful build. An existing base
#     case is never deleted, because the clones use its executable.
#   - skips a variant that finished (case.run success) with the same settings
#   - skips a variant that is queued or running, so a batch job isn't deleted under it
#   - redoes a variant that failed, never ran, or whose settings below have changed
# So to add a variant, add a line below and rerun.
#
# Inside salloc, the base case (if built now) and the variants run one after another
# (20 min build + 10 min per run). On a login node, the base case is only built, and
# each variant is submitted as a batch job.
set -uo pipefail   # no -e: one failed variant shouldn't stop the others

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${1:-$SCRIPT_DIR/../config/${MACHINE_ENV:-pm-cpu}.env}"

if [ ! -f "$ENV_FILE" ]; then
    echo "Env file not found: $ENV_FILE" >&2
    exit 1
fi
set -a; source "$ENV_FILE"; set +a
: "${E3SM_ROOT:?must be set in $ENV_FILE}"
: "${OUTPUT_ROOT:?must be set in $ENV_FILE}"

# --- Sweep definition -----------------------------------------------------------
WY="${WY:-2012}"
BASE_TAG="${BASE_TAG:-base}"
BASE_FSCA=SL12   # the base case is itself the SL12 run, so SL12 isn't a variant

# variant <TAG> <FSCA> [<EXTRA_NML>]   FSCA "" keeps the base case's value
TAGS=(); FSCAS=(); EXTRAS=()
variant() { TAGS+=("$1"); FSCAS+=("$2"); EXTRAS+=("${3:-}"); }

variant SL12_legacy SL12_legacy
variant NY07        NY07
variant Helbig21    Helbig21
variant CZ26        CZ26

# --- Base case ------------------------------------------------------------------
BASE="TG_NLDAS2_WY${WY}_${BASE_TAG}"
base_scripts_dir=$OUTPUT_ROOT/$BASE/case_scripts

if grep -q "case.build success" "$base_scripts_dir/CaseStatus" 2>/dev/null; then
    echo "Base case $BASE is built; not rebuilding."
    # The clones use the base case's executable, whatever E3SM_ROOT holds now
    base_commit=$(sed -n 's/^commit: //p' "$base_scripts_dir/E3SM_COMMIT.txt")
    head_commit=$(git -C "$E3SM_ROOT" rev-parse HEAD)
    if [ "${base_commit%-dirty}" != "$head_commit" ]; then
        echo "WARNING: $BASE was built from ${base_commit:0:10}, but E3SM_ROOT is at ${head_commit:0:10}." >&2
        echo "         The variants use the base case's build. For the new code, use a new BASE_TAG." >&2
    fi
else
    echo "Building base case $BASE (FSCA=$BASE_FSCA)"
    if ! WY=$WY TAG=$BASE_TAG FSCA=$BASE_FSCA FINIDAT= EXTRA_NML= \
            "$SCRIPT_DIR/TG_NLDAS2_WY20XX.sh" "$ENV_FILE"; then
        echo "Base case build failed; no variants run." >&2
        exit 1
    fi
    # Outside salloc the base script stops after the build, so check that it built
    if ! grep -q "case.build success" "$base_scripts_dir/CaseStatus" 2>/dev/null; then
        echo "Base case $BASE didn't build; no variants run." >&2
        exit 1
    fi
fi

# --- Variants -------------------------------------------------------------------
# Run status of a case, from the last case.run line in its CaseStatus
run_status() {
    local status_file=$1/CaseStatus last
    [ -f "$status_file" ] || { echo none; return; }
    last=$(grep -E "case\.run (starting|success|error)" "$status_file" | tail -1)
    case "$last" in
        *"case.run success"*)  echo done ;;
        *"case.run error"*)    echo failed ;;
        *"case.run starting"*) echo running ;;
        *) if grep -q "case.submit success" "$status_file"; then echo queued; else echo none; fi ;;
    esac
}

wants_rerun() {
    [ "${RERUN:-}" = all ] || [[ " ${RERUN:-} " == *" $1 "* ]]
}

done_tags=(); started_tags=(); skipped_tags=(); failed_tags=()
for i in "${!TAGS[@]}"; do
    tag=${TAGS[$i]}; fsca=${FSCAS[$i]}; extra=${EXTRAS[$i]}
    case_name="${BASE}_${tag}"
    clone_dir=$OUTPUT_ROOT/clones/$case_name
    # The variant's settings, saved in the clone to notice when they change
    signature=$(printf 'FSCA=%s\nEXTRA_NML=%s\n' "$fsca" "$extra")
    status=$(run_status "$clone_dir")
    old_signature=$(cat "$clone_dir/sweep_variant.txt" 2>/dev/null)

    echo
    echo "=== $case_name: $status"
    if ! wants_rerun "$tag"; then
        if [ "$status" = queued ] || [ "$status" = running ]; then
            echo "Skipping: $status. If its job is gone (check squeue), rerun with RERUN=$tag."
            skipped_tags+=("$tag"); continue
        fi
        if [ "$status" = done ] && [ "$signature" = "$old_signature" ]; then
            echo "Skipping: finished with the same settings."
            done_tags+=("$tag"); continue
        fi
        [ "$status" = done ] && echo "Settings changed; redoing it."
    fi

    if TAG=$tag FSCA=$fsca EXTRA_NML=$extra BASE=$BASE \
            "$SCRIPT_DIR/clone_variant.sh" "$ENV_FILE"; then
        printf '%s' "$signature" > "$clone_dir/sweep_variant.txt"
        started_tags+=("$tag")
    else
        echo "FAILED: $case_name (see the output above)" >&2
        failed_tags+=("$tag")
    fi
done

# --- Summary --------------------------------------------------------------------
echo
echo "Sweep $BASE: ${#TAGS[@]} variants"
echo "  already finished:  ${done_tags[*]:-}"
echo "  run or submitted:  ${started_tags[*]:-}"
echo "  queued or running: ${skipped_tags[*]:-}"
echo "  failed:            ${failed_tags[*]:-}"
echo "Run status per case: tail $OUTPUT_ROOT/clones/${BASE}_*/CaseStatus"
[ ${#failed_tags[@]} -eq 0 ]
