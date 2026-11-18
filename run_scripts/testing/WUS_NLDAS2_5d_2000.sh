#!/bin/bash
# ELM over the Western US (WUS, 0.125 deg, 168 x 144, 21872 land cells), forced with
# NLDAS2: 5-day test run starting 2000-01-01. Regional copy of TG_NLDAS2_5d_2000.sh,
# for checking the WUS setup (input files, decomposition, memory, output) before
# running WUS_NLDAS2_WY20XX.sh. Input data from ezdemo/run_WUS_fsca.sh (c260113).
#
# Usage: [TAG=<tag>] [FSCA=<value>] [NTASKS=<n>] ./WUS_NLDAS2_5d_2000.sh [path/to/machine.env]
#   Defaults to ../config/${MACHINE_ENV:-pm-cpu}.env
#   TAG     case-name suffix (default: quicktest). The case is WUS_NLDAS2_5d_2000_<TAG>,
#           and an existing case with that name is deleted first.
#   NTASKS  MPI tasks (default: 512 = 4 pm-cpu nodes, ~43 land cells per task).
#           Use the same value as the season run, so this test checks that layout.
#           4 nodes is the interactive-QOS maximum.
#   FSCA    snow_fsca_param value (default: SL12). Give it bare: the script adds the
#           quotes for strings. Valid values depend on the E3SM commit you build:
#             fsca branch (fe85f116b9 and later): SL12, SL12_legacy, NY07, Helbig21, CZ26
#             older ez/fsca commits (e.g. edcbdcd34c): integer 0 (SL12), 1 (NY07), 2 (Helbig21)
#
# What to check after the run:
#   - CaseStatus says "case.run success"
#   - timing/e3sm_timing.*: "seconds/mday" times 273 estimates the season run's
#     length; set JOB_WALLCLOCK_TIME in WUS_NLDAS2_WY20XX.sh from it
#   - h0/h1 files: FSNO, H2OSNO look sensible across the domain (snow in the
#     mountains in January, none in the low deserts)
#
# Interactive run on Perlmutter (see https://docs.nersc.gov/jobs/interactive/):
#   1. Get compute nodes (interactive QOS: up to 4 h, up to 4 nodes; 128 tasks/node):
#        salloc --nodes 4 --qos interactive --time 01:00:00 --constraint cpu --account m4986
#   2. Run this script on that node. It creates and builds the case, then, because
#      SLURM_JOB_ID is set, runs the model directly with `case.submit --no-batch`.
#      If you run it on a login node, it builds the case and stops, and you can submit later.
#   3. Iterate in the same allocation without rebuilding. Changes to user_nl_elm,
#      STOP_N or the history settings don't need a rebuild:
#        module load python/3.13   # needed in the salloc shell, or srun's args break
#        cd $OUTPUT_ROOT/WUS_NLDAS2_5d_2000_<TAG>/case_scripts
#        vi user_nl_elm && ./preview_namelists
#        ./case.submit --no-batch
#      NTASKS, compset or source code changes need ./case.build first.
#      Note: case_scripts/E3SM_COMMIT.txt records the E3SM commit at the time this
#      script built the case. A manual ./case.build after checking out another commit
#      makes it stale, so for a new commit, make a new case (one case = one commit).
#   Check:  tail case_scripts/CaseStatus   ("case.run success" or "case.run error")
#   Logs:   $OUTPUT_ROOT/WUS_NLDAS2_5d_2000_<TAG>/run/{lnd,cpl,e3sm}.log.*  (gzipped on success)
#   Output: $OUTPUT_ROOT/WUS_NLDAS2_5d_2000_<TAG>/run/*.elm.h{0,1}.*.nc, restart *.elm.r.*.nc
#
# Without an allocation, plain ./case.submit sends the job to the debug queue (30 min max,
# up to 8 nodes).
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
REGION=WUS
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

# Processor layout (see the section below); nodes needed at 128 MPI tasks per node
LAND_CELLS=21872   # land cells (mask = 1) in the WUS domain file
NTASKS="${NTASKS:-512}"
if ! [[ "$NTASKS" =~ ^[0-9]+$ ]] || (( NTASKS < 1 || NTASKS > LAND_CELLS )); then
    echo "NTASKS must be 1-$LAND_CELLS (ELM needs at least one land cell per task), got: $NTASKS" >&2
    exit 1
fi
NODES=$(( (NTASKS + 127) / 128 ))
if [ -n "${SLURM_JOB_ID:-}" ] && (( ${SLURM_NNODES:-1} < NODES )); then
    echo "NTASKS=$NTASKS needs $NODES nodes, but this allocation has ${SLURM_NNODES:-1}." >&2
    echo "Use salloc --nodes $NODES, or set NTASKS=$(( ${SLURM_NNODES:-1} * 128 ))." >&2
    exit 1
fi

# --- Fixed at case creation ---------------------------------------------------
RES=ELM_USRDAT
COMPSET=IELMBC
MACH=${MACH:-pm-cpu}
COMPILER=${COMPILER:-gnu}
PROJECT=${PROJECT:-m4986}

# --- Site input data ----------------------------------------------------------
# Copied from Enrico's WUS_surface_data_FSCA/ (see ezdemo/run_WUS_fsca.sh).
# 0.125 deg, 235-256E, 32-50N: inside the NLDAS2 domain.
domainPath=$DATA_ROOT/WUS/
domainFile=domain_WUS_0125_c260113_areafix.nc   # area fixed to radian^2 (orig. had deg^2)
surfdataFile=surfdata_WUS_0125_c260113_merged.nc

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
# WUS has 21872 land cells; the default 512 tasks (4 nodes) gives ~43 cells per task.
# All components (DATM, ELM, coupler) share the same tasks, as in the TG cases.
./xmlchange NTASKS=$NTASKS

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
# History: only the fields below, on tape 1 daily and tape 2 hourly (~0.2 GB for
# WUS). A monthly tape would stay empty in a 5-day run. List available fields with
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
    echo "NTASKS: $NTASKS"
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
    echo "  salloc --nodes $NODES --qos interactive --time 01:00:00 --constraint cpu --account $PROJECT"
    echo "  module load python/3.13"
    echo "  cd $case_scripts_dir && ./case.submit --no-batch"
    echo "Or submit to the debug queue: cd $case_scripts_dir && ./case.submit"
fi
