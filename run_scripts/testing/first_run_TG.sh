#!/bin/bash
# An initial test of ELM at Tony Grove RS SNOTEL
#
# Usage: ./first_run_TG.sh [path/to/machine.env]
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

export RES=ELM_USRDAT 
export COMPSET=IELMBC
export COMPILER=gnu
export MACH=pm-cpu

CASE_NAME=TGUT_first_test

domainPath=$DATA_ROOT/tonygrovers/
domainFile=domain_TG_UT_0125_c261028.nc
surfdataFile=surfdata_TG_UT_0125_c261028.nc
NL_TEMPLATE=$SCRIPT_DIR/../config/user_nl_elm_TG

if [ ! -f "$NL_TEMPLATE" ]; then
    echo "Namelist template not found: $NL_TEMPLATE" >&2
    exit 1
fi

case_dir=$OUTPUT_ROOT/$CASE_NAME
case_scripts_dir=$case_dir/case_scripts

if [ -d "$case_dir" ]; then
    echo "Deleting old case directory: $case_dir"
    rm -rf "$case_dir"
fi

cd "$E3SM_ROOT/cime/scripts"
./create_newcase --compset "$COMPSET" --res "$RES" --case "$CASE_NAME" \
    --script-root "$case_scripts_dir" --output-root "$OUTPUT_ROOT" \
    --compiler "$COMPILER" --mach "$MACH" --project m4986
cd "$case_scripts_dir"

./xmlchange LND_DOMAIN_FILE="$domainFile"
./xmlchange ATM_DOMAIN_FILE="$domainFile"
./xmlchange LND_DOMAIN_PATH="$domainPath"
./xmlchange ATM_DOMAIN_PATH="$domainPath"

./xmlchange NTASKS=64,STOP_N=3,STOP_OPTION=nyears,JOB_WALLCLOCK_TIME="01:00:00",RUN_STARTDATE="2000-01-01",REST_N=1,REST_OPTION=nyears
./xmlchange DATM_MODE="CLMGSWP3v1",DATM_CLMNCEP_YR_START='2000',DATM_CLMNCEP_YR_END='2003'

# Namelist settings come from the template; only the machine-dependent path is added here
cat "$NL_TEMPLATE" >> user_nl_elm
echo "fsurdat = '${domainPath}${surfdataFile}'" >> user_nl_elm

./case.setup
./case.build
./case.submit
