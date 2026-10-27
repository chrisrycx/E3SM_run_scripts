#! /bin/bash
module load python/3.10

export RES=ELM_USRDAT 
export COMPSET=IELMBC
export COMPILER=gnu
export MACH=pm-cpu
export CASE_NAME=TGUT_dynamic2

export domainPath=/global/cfs/cdirs/m4986/data/enrico_data/Tony_Grove_UT/
export domainFile=domain_TG_UT_0125_c250814.nc
export surfdataFile=surfdata_TG_UT_0125_c250814.nc



export output_dir=/global/cfs/cdirs/m4986/data/enrico_data/tgut_res/
export case_dir=/$output_dir/$CASE_NAME
export case_scripts_dir=/$case_dir/case_scripts

if [ -d "$case_dir" ]; then
# Take action if $DIR exists. #
echo "Delete the old folder"
rm -rf $case_dir
fi

 cd /global/homes/e/enricoz/E3SM_SHP/cime/scripts/
./create_newcase --compset ${COMPSET} --res ${RES} --case ${CASE_NAME} --script-root $case_scripts_dir --output-root ${output_dir} --compiler ${COMPILER} --mach ${MACH} --project m4986   
cd ${case_scripts_dir}


./xmlchange LND_DOMAIN_FILE=${domainFile} 
./xmlchange ATM_DOMAIN_FILE=${domainFile} 
./xmlchange LND_DOMAIN_PATH=${domainPath}
./xmlchange ATM_DOMAIN_PATH=${domainPath}


./xmlchange NTASKS=64,STOP_N=3,STOP_OPTION=nyears,JOB_WALLCLOCK_TIME="01:00:00",RUN_STARTDATE="2000-01-01",REST_N=1,REST_OPTION=nyears
./xmlchange DATM_MODE="CLMGSWP3v1",DATM_CLMNCEP_YR_START='2000',DATM_CLMNCEP_YR_END='2003'

cat >> user_nl_elm << EOF
fsurdat = '${domainPath}${surfdataFile}'
hist_mfilt = 1
hist_nhtfrq = -24
use_snicar_ad               = .true.
use_top_solar_rad           = .false.
use_dynamic_snow_shape      = .true.
EOF

./case.setup 
./case.build 
./case.submit

export RES=ELM_USRDAT 
export COMPSET=IELMBC
export COMPILER=gnu
export MACH=pm-cpu
export CASE_NAME=TGUT_sphere

export domainPath=/global/cfs/cdirs/m4986/data/enrico_data/Tony_Grove_UT/
export domainFile=domain_TG_UT_0125_c250814.nc
export surfdataFile=surfdata_TG_UT_0125_c250814.nc



export output_dir=/global/cfs/cdirs/m4986/data/enrico_data/tgut_res/
export case_dir=/$output_dir/$CASE_NAME
export case_scripts_dir=/$case_dir/case_scripts

if [ -d "$case_dir" ]; then
# Take action if $DIR exists. #
echo "Delete the old folder"
rm -rf $case_dir
fi

 cd /global/homes/e/enricoz/E3SM_SHP/cime/scripts/
./create_newcase --compset ${COMPSET} --res ${RES} --case ${CASE_NAME} --script-root $case_scripts_dir --output-root ${output_dir} --compiler ${COMPILER} --mach ${MACH} --project m4986   
cd ${case_scripts_dir}


./xmlchange LND_DOMAIN_FILE=${domainFile} 
./xmlchange ATM_DOMAIN_FILE=${domainFile} 
./xmlchange LND_DOMAIN_PATH=${domainPath}
./xmlchange ATM_DOMAIN_PATH=${domainPath}


./xmlchange NTASKS=64,STOP_N=3,STOP_OPTION=nyears,JOB_WALLCLOCK_TIME="01:00:00",RUN_STARTDATE="2000-01-01",REST_N=1,REST_OPTION=nyears
./xmlchange DATM_MODE="CLMGSWP3v1",DATM_CLMNCEP_YR_START='2000',DATM_CLMNCEP_YR_END='2003'

cat >> user_nl_elm << EOF
fsurdat = '${domainPath}${surfdataFile}'
hist_mfilt = 1
hist_nhtfrq = -24
use_snicar_ad               = .true.
use_top_solar_rad           = .false.
use_dynamic_snow_shape           = .false.
snow_shape = 'sphere'
EOF

./case.setup 
./case.build 
./case.submit


export RES=ELM_USRDAT 
export COMPSET=IELMBC
export COMPILER=gnu
export MACH=pm-cpu
export CASE_NAME=TGUT_koch

export domainPath=/global/cfs/cdirs/m4986/data/enrico_data/Tony_Grove_UT/
export domainFile=domain_TG_UT_0125_c250814.nc
export surfdataFile=surfdata_TG_UT_0125_c250814.nc


export output_dir=/global/cfs/cdirs/m4986/data/enrico_data/tgut_res/
export case_dir=/$output_dir/$CASE_NAME
export case_scripts_dir=/$case_dir/case_scripts

if [ -d "$case_dir" ]; then
# Take action if $DIR exists. #
echo "Delete the old folder"
rm -rf $case_dir
fi

 cd /global/homes/e/enricoz/E3SM_SHP/cime/scripts/
./create_newcase --compset ${COMPSET} --res ${RES} --case ${CASE_NAME} --script-root $case_scripts_dir --output-root ${output_dir} --compiler ${COMPILER} --mach ${MACH} --project m4986   
cd ${case_scripts_dir}


./xmlchange LND_DOMAIN_FILE=${domainFile} 
./xmlchange ATM_DOMAIN_FILE=${domainFile} 
./xmlchange LND_DOMAIN_PATH=${domainPath}
./xmlchange ATM_DOMAIN_PATH=${domainPath}


./xmlchange NTASKS=64,STOP_N=3,STOP_OPTION=nyears,JOB_WALLCLOCK_TIME="01:00:00",RUN_STARTDATE="2000-01-01",REST_N=1,REST_OPTION=nyears
./xmlchange DATM_MODE="CLMGSWP3v1",DATM_CLMNCEP_YR_START='2000',DATM_CLMNCEP_YR_END='2003'

cat >> user_nl_elm << EOF
fsurdat = '${domainPath}${surfdataFile}'
hist_mfilt = 1
hist_nhtfrq = -24
use_snicar_ad               = .true.
use_top_solar_rad           = .false.
use_dynamic_snow_shape           = .false.
snow_shape = 'koch_snowflake'
EOF

./case.setup 
./case.build 
./case.submit
