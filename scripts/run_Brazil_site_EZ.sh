#! /bin/bash
module load python/3.10

export RES=1x1_brazil #This is a single grid cell
export COMPSET=IELMBC
export COMPILER=gnu
export MACH=pm-cpu
# export CASE_NAME=${RES}.${COMPSET}.${COMPILER}
export CASE_NAME=Brazil_test

# export output_dir=/global/u2/e/enricoz/results/
# export case_dir=/$output_dir/$CASE_NAME
# export case_scripts_dir=/$case_dir/case_scripts



export output_dir=/global/cfs/cdirs/m4986/data/enrico_data/Brazil_1x1_res/
mkdir -p $output_dir
export case_dir=/$output_dir/$CASE_NAME
export case_scripts_dir=/$case_dir/case_scripts

if [ -d "$case_dir" ]; then
# Take action if $DIR exists. #
echo "Delete the old folder"
rm -rf $case_dir
fi



# If an old case build already exists, might want to run 'case.build --clean' before building
# cd ${CASE_NAME}
# ./case.build --clean 

 
 # cd /global/homes/e/enricoz/E3SM/cime/scripts/
 cd /global/homes/e/enricoz/E3SM_master/cime/scripts/
./create_newcase --case ${CASE_NAME} --compset ${COMPSET} -res ${RES}  --script-root $case_scripts_dir --output-root ${output_dir} --compiler ${COMPILER} --mach ${MACH} --project m4986 

cd ${case_scripts_dir}

# cd ${CASE_NAME}
 
./xmlchange NTASKS=1,STOP_N=1,STOP_OPTION=nyears,JOB_WALLCLOCK_TIME="00:30:00",RUN_STARTDATE="2000-01-01",REST_N=1,REST_OPTION=nyears
./xmlchange DATM_MODE="CLMGSWP3v1",DATM_CLMNCEP_YR_START='2000',DATM_CLMNCEP_YR_END='2001'


cat >> user_nl_elm << EOF
hist_mfilt = 1
hist_nhtfrq = -24
use_snicar_ad               = .true.
use_top_solar_rad           = .false.
snow_shape = 'koch_snowflake'
hist_fincl1 = 'SNO_GS','SNO_DEN','SNO_SPH'
EOF

# use_dynamic_snow_shape = .true.

# ./case.build --clean

 
./case.setup
./case.build
./case.submit