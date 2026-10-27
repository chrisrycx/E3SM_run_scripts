#!/bin/bash
# This was a first run trying to create a single grid cell case for testing purposes.
export RES=1x1_brazil #This is a single grid cell
export COMPSET=IELMBC
export COMPILER=gnu
export MACH=pm-cpu
export CASE_NAME=${RES}.${COMPSET}.${COMPILER}
 
../create_newcase --case ${CASE_NAME} --compset ${COMPSET} -res ${RES} --compiler ${COMPILER} --mach ${MACH} --project m4986
 
cd ${CASE_NAME}
./xmlchange NTASKS=1,STOP_N=1,STOP_OPTION=nmonths,JOB_WALLCLOCK_TIME="00:10:00",RUN_STARTDATE="2000-01-01",REST_N=1,REST_OPTION=nmonths
./xmlchange DATM_MODE=" CLMGSWP3v1",DATM_CLMNCEP_YR_START='2000',DATM_CLMNCEP_YR_END='2000'
 
./case.setup
./case.build
./case.submit
