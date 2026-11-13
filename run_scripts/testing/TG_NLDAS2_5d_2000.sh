#!/bin/bash
# ELM at Tony Grove RS SNOTEL (UT), forced with NLDAS2: 5-day test run starting 2000-01-01
# Short-run copy of TG_NLDAS2_2000-2002.sh, for checking setup on an interactive node.
#
# Usage: [TAG=<tag>] [FSCA=<value>] ./TG_NLDAS2_5d_2000.sh [path/to/machine.env]
#   Defaults to ../config/${MACHINE_ENV:-pm-cpu}.env
#   TAG   case-name suffix (default: quicktest). The case is TG_NLDAS2_5d_2000_<TAG>,
#         and an existing case with that name is deleted first.
#   FSCA  snow_fsca_param value (default: SL12). Give it bare: the script adds the
#         quotes for strings. Valid values depend on the E3SM commit you build:
#           fsca branch (fe85f116b9 and later): SL12, SL12_legacy, NY07, Helbig21, CZ26
#           older ez/fsca commits (e.g. edcbdcd34c): integer 0 (SL12), 1 (NY07), 2 (Helbig21)
#
# Regression check (two commits, same settings otherwise):
#   (E3SM_ROOT at edcbdcd34c)  TAG=baseline FSCA=0           ./TG_NLDAS2_5d_2000.sh
#   (E3SM_ROOT at fe85f116b9)  TAG=new      FSCA=SL12_legacy ./TG_NLDAS2_5d_2000.sh
#   then compare run/*.elm.r.*.nc and run/*.elm.h1.*.nc of the two cases with cprnc.
#
# Interactive run on Perlmutter (see https://docs.nersc.gov/jobs/interactive/):
#   1. Get a compute node (interactive QOS: up to 4 h, up to 4 nodes):
#        salloc --nodes 1 --qos interactive --time 01:00:00 --constraint cpu --account m4986
#   2. Run this script on that node. It creates and builds the case, then, because
#      SLURM_JOB_ID is set, runs the model directly with `case.submit --no-batch`.
#      If you run it on a login node, it builds the case and stops, and you can submit later.
#   3. Iterate in the same allocation without rebuilding. Changes to user_nl_elm,
#      STOP_N or the history settings don't need a rebuild:
#        module load python/3.13   # needed in the salloc shell, or srun's args break
#        cd $OUTPUT_ROOT/TG_NLDAS2_5d_2000_<TAG>/case_scripts
#        vi user_nl_elm && ./preview_namelists
#        ./case.submit --no-batch
#      NTASKS, compset or source code changes need ./case.build first.
#      Note: case_scripts/E3SM_COMMIT.txt records the E3SM commit at the time this
#      script built the case. A manual ./case.build after checking out another commit
#      makes it stale, so for a new commit, make a new case (one case = one commit).
#   Check:  tail case_scripts/CaseStatus   ("case.run success" or "case.run error")
#   Logs:   $OUTPUT_ROOT/TG_NLDAS2_5d_2000_<TAG>/run/{lnd,cpl,e3sm}.log.*  (gzipped on success)
#   Output: $OUTPUT_ROOT/TG_NLDAS2_5d_2000_<TAG>/run/*.elm.h{0,1}.*.nc, restart *.elm.r.*.nc
#
# Without an allocation, plain ./case.submit sends the job to the debug queue (30 min max).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${1:-$SCRIPT_DIR/../config/${MACHINE_ENV:-pm-cpu}.env}"

if [ ! -f "$ENV_FILE" ]; then
    echo "Env file not found: $ENV_FILE" >&2
    exit 1
fi
set -a; source "$ENV_FILE"; set +a

: "${E3SM_ROOT:?must be set in $ENV_FILE}"
: "${DATA_ROOT:?must be set in $ENV_FILE}"
: "${OUTPUT_ROOT:?must be set in $ENV_FILE}"

module load python/3.13

# --- E3SM source version --------------------------------------------------------
# The case compiles whatever is in E3SM_ROOT, including uncommitted edits. Then
# the commit hash alone doesn't describe the build, so mark it "-dirty" and warn.
# Untracked files are listed in E3SM_COMMIT.txt but don't count as dirty.
E3SM_COMMIT=$(git -C "$E3SM_ROOT" rev-parse HEAD)
E3SM_BRANCH=$(git -C "$E3SM_ROOT" branch --show-current)
if [ -n "$(git -C "$E3SM_ROOT" status --porcelain --untracked-files=no)" ]; then
    E3SM_COMMIT="${E3SM_COMMIT}-dirty"
    echo "WARNING: $E3SM_ROOT has uncommitted changes; recording commit as ${E3SM_COMMIT:0:10}...-dirty." >&2
    echo "         Don't use this case as a regression baseline." >&2
fi
echo "Building from E3SM commit $E3SM_COMMIT (branch: ${E3SM_BRANCH:-detached HEAD})"

# --- Experiment ---------------------------------------------------------------
# Case name follows <region>_<forcing>_<N>d_<start>[_<tag>], same as the script name; set TAG for variants
REGION=TG
FORCING=NLDAS2
YEAR_START=2000
YEAR_END=2000   # inclusive; forcing years available to DATM
TAG="${TAG:-quicktest}"
STOP_DAYS=5     # run length in days

# snow_fsca_param: integers go into the namelist as-is, strings get quoted
FSCA="${FSCA:-SL12}"
if [[ "$FSCA" =~ ^[0-9]+$ ]]; then
    FSCA_NML="$FSCA"
else
    FSCA_NML="'$FSCA'"
fi

CASE_NAME="${REGION}_${FORCING}_${STOP_DAYS}d_${YEAR_START}${TAG:+_$TAG}"

# --- Fixed at case creation ---------------------------------------------------
RES=ELM_USRDAT
COMPSET=IELMBC
MACH=${MACH:-pm-cpu}
COMPILER=${COMPILER:-gnu}
PROJECT=${PROJECT:-m4986}

# --- Site input data ----------------------------------------------------------
domainPath=$DATA_ROOT/tonygrovers/
domainFile=domain_TG_UT_0125_c261028.nc
surfdataFile=surfdata_TG_UT_0125_c261028_merged.nc

# --- Create case --------------------------------------------------------------
case_dir=$OUTPUT_ROOT/$CASE_NAME
case_scripts_dir=$case_dir/case_scripts

if [ -d "$case_dir" ]; then
    echo "Deleting old case directory: $case_dir"
    rm -rf "$case_dir"
fi

cd "$E3SM_ROOT/cime/scripts"
./create_newcase --compset "$COMPSET" --res "$RES" --case "$CASE_NAME" \
    --script-root "$case_scripts_dir" --output-root "$OUTPUT_ROOT" \
    --compiler "$COMPILER" --mach "$MACH" --project "$PROJECT"
cd "$case_scripts_dir"

# --- Processor layout ---------------------------------------------------------
# ELM splits work by gridcell and aborts if NTASKS > land gridcells.
# TG domain is 12 x 8 = 96 cells, so 96 tasks gives 1 cell per task on one node.
./xmlchange NTASKS=96

# --- Site domain --------------------------------------------------------------
./xmlchange LND_DOMAIN_FILE="$domainFile",ATM_DOMAIN_FILE="$domainFile"
./xmlchange LND_DOMAIN_PATH="$domainPath",ATM_DOMAIN_PATH="$domainPath"

# --- Run control --------------------------------------------------------------
# Restart written at the end of the run, so a continue run can be tested too.
# JOB_QUEUE/JOB_WALLCLOCK_TIME only apply to batch submission; --no-batch ignores them.
./xmlchange RUN_STARTDATE="${YEAR_START}-01-01",STOP_OPTION=ndays,STOP_N=$STOP_DAYS
./xmlchange REST_OPTION=ndays,REST_N=$STOP_DAYS
./xmlchange JOB_QUEUE=debug,JOB_WALLCLOCK_TIME="00:30:00"
# No short-term archiving: logs and history files stay in run/ instead of moving
# to $OUTPUT_ROOT/archive/$CASE_NAME after the run
./xmlchange DOUT_S=FALSE

# --- Forcing: model year YEAR_START uses forcing year YEAR_START --------------
# NLDAS2: hourly, 0.125 deg, CONUS only (25-53N, 235-293E), years 1980-2018
./xmlchange DATM_MODE=CLMNLDAS2
./xmlchange DATM_CLMNCEP_YR_START=$YEAR_START,DATM_CLMNCEP_YR_END=$YEAR_END
./xmlchange DATM_CLMNCEP_YR_ALIGN=$YEAR_START

# --- ELM namelist -------------------------------------------------------------
# History: only the fields below, on tape 1 daily and tape 2 hourly. A monthly
# tape would stay empty in a 5-day run. List available fields with
# tools/list_hist_fields.py.
# snow_fsca_param requires the fsca branch of E3SM (set with FSCA, see Usage)
SNOW_FIELDS="'FSNO','FSNO_EFF','H2OSNO','SNOWDP','SNOW_DEPTH','QSNOMELT','SNORDSL','SNOTTOPL'"
MET_FIELDS="'SNOW','RAIN','TBOT','FSDS','FSR','FSA','FSH','EFLX_LH_TOT','QRUNOFF','TG'"
HIST_FIELDS="${SNOW_FIELDS},${MET_FIELDS}"

cat >> user_nl_elm <<EOF
fsurdat           = '${domainPath}${surfdataFile}'
hist_empty_htapes = .true.
hist_fincl1       = ${HIST_FIELDS}
hist_fincl2       = ${HIST_FIELDS}
hist_mfilt        = 365, 8760
hist_nhtfrq       = -24, -1
use_snicar_ad     = .true.
use_top_solar_rad = .false.
snow_fsca_param   = ${FSCA_NML}
EOF

./case.setup
./preview_namelists   # fails early on invalid namelist options

# Record the source version next to the case (written just before the build)
{
    echo "commit: $E3SM_COMMIT"
    echo "branch: ${E3SM_BRANCH:-detached HEAD}"
    echo "E3SM_ROOT: $E3SM_ROOT"
    echo "date: $(date -Iseconds)"
    echo "TAG: $TAG"
    echo "FSCA: $FSCA"
    echo
    echo "# git log -1"
    git -C "$E3SM_ROOT" log -1 --format='%H %an %ad%n    %s'
    echo
    echo "# git status --short (empty = clean)"
    git -C "$E3SM_ROOT" status --short
    echo
    echo "# git submodule status"
    git -C "$E3SM_ROOT" submodule status
} > E3SM_COMMIT.txt

./case.build

# --- Run ----------------------------------------------------------------------
if [ -n "${SLURM_JOB_ID:-}" ]; then
    # Inside salloc: run the model here, now
    ./case.submit --no-batch
else
    echo
    echo "Case built: $case_scripts_dir"
    echo "To run interactively:"
    echo "  salloc --nodes 1 --qos interactive --time 01:00:00 --constraint cpu --account $PROJECT"
    echo "  Load python module > 3.8 "
    echo "  cd $case_scripts_dir && ./case.submit --no-batch"
    echo "Or submit to the debug queue: cd $case_scripts_dir && ./case.submit"
fi
