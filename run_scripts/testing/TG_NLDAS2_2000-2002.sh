#!/bin/bash
# ELM at Tony Grove RS SNOTEL (UT), forced with NLDAS2, 2000-2002
#
# Usage: ./TG_NLDAS2_2000-2002.sh [path/to/machine.env]
#   Defaults to ../config/${MACHINE_ENV:-pm-cpu}.env
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

module load python/3.10

# --- Experiment ---------------------------------------------------------------
# Case name follows <region>_<forcing>_<start>-<end>[_<tag>]; set TAG for variants
REGION=TG
FORCING=NLDAS2
YEAR_START=2000
YEAR_END=2002   # inclusive
TAG=""

CASE_NAME="${REGION}_${FORCING}_${YEAR_START}-${YEAR_END}${TAG:+_$TAG}"
NYEARS=$(( YEAR_END - YEAR_START + 1 ))

# --- Fixed at case creation ---------------------------------------------------
RES=ELM_USRDAT
COMPSET=IELMBC
MACH=${MACH:-pm-cpu}
COMPILER=${COMPILER:-gnu}
PROJECT=${PROJECT:-m4986}

# --- Site input data ----------------------------------------------------------
domainPath=$DATA_ROOT/tonygrovers/
domainFile=domain_TG_UT_0125_c261028.nc
surfdataFile=surfdata_TG_UT_0125_c261028.nc

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
./xmlchange RUN_STARTDATE="${YEAR_START}-01-01",STOP_OPTION=nyears,STOP_N=$NYEARS
./xmlchange REST_OPTION=nyears,REST_N=1
./xmlchange JOB_WALLCLOCK_TIME="01:00:00"

# --- Forcing: model year YEAR_START uses forcing year YEAR_START --------------
# NLDAS2: hourly, 0.125 deg, CONUS only (25-53N, 235-293E), years 1980-2018
./xmlchange DATM_MODE=CLMNLDAS2
./xmlchange DATM_CLMNCEP_YR_START=$YEAR_START,DATM_CLMNCEP_YR_END=$YEAR_END
./xmlchange DATM_CLMNCEP_YR_ALIGN=$YEAR_START

# --- ELM namelist -------------------------------------------------------------
# History: only the fields below, on tape 1 monthly (12 per file) and tape 2
# daily (365 per file). List available fields with tools/list_hist_fields.py.
# snow_fsca_param requires the ez/fsca branch of E3SM
SNOW_FIELDS="'FSNO','FSNO_EFF','H2OSNO','SNOWDP','SNOW_DEPTH','QSNOMELT','SNORDSL','SNOTTOPL'"
MET_FIELDS="'SNOW','RAIN','TBOT','FSDS','FSR','FSA','FSH','EFLX_LH_TOT','QRUNOFF','TG'"
HIST_FIELDS="${SNOW_FIELDS},${MET_FIELDS}"

cat >> user_nl_elm <<EOF
fsurdat           = '${domainPath}${surfdataFile}'
hist_empty_htapes = .true.
hist_fincl1       = ${HIST_FIELDS}
hist_fincl2       = ${HIST_FIELDS}
hist_mfilt        = 12, 365
hist_nhtfrq       = 0, -24
use_snicar_ad     = .true.
use_top_solar_rad = .false.
snow_fsca_param   = 'SL12'
EOF

./case.setup
./preview_namelists   # fails early on invalid namelist options
./case.build
./case.submit
