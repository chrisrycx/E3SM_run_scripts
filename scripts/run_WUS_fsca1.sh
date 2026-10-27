#! /bin/bash
module load python/3.10

export RES=ELM_USRDAT 
export COMPSET=IELMBC
export COMPILER=gnu
export MACH=pm-cpu
export CASE_NAME=WUS_fsca_helbig21

export domainPath=/global/cfs/cdirs/m4986/data/enrico_data/WUS_surface_data_FSCA/
export domainFile=domain_WUS_0125_c260113.nc
export surfdataFile=surfdata_WUS_0125_c260113_merged.nc

export output_dir=/global/cfs/cdirs/m4986/data/enrico_data/WUS_res_fsca/
export case_dir=/$output_dir/$CASE_NAME
export case_scripts_dir=/$case_dir/case_scripts

if [ -d "$case_dir" ]; then
# Take action if $DIR exists. #
echo "Delete the old folder"
rm -rf $case_dir
fi

 cd /global/homes/e/enricoz/E3SM_FSCA/cime/scripts/
./create_newcase --compset ${COMPSET} --res ${RES} --case ${CASE_NAME} --script-root $case_scripts_dir --output-root ${output_dir} --compiler ${COMPILER} --mach ${MACH} --project m4986   
cd ${case_scripts_dir}


./xmlchange LND_DOMAIN_FILE=${domainFile} 
./xmlchange ATM_DOMAIN_FILE=${domainFile} 
./xmlchange LND_DOMAIN_PATH=${domainPath}
./xmlchange ATM_DOMAIN_PATH=${domainPath}


./xmlchange NTASKS=128,STOP_N=1,STOP_OPTION=nyears,JOB_WALLCLOCK_TIME="02:00:00",RUN_STARTDATE="2000-01-01",REST_N=1,REST_OPTION=nyears,RESUBMIT=1
./xmlchange DATM_MODE="CLMNLDAS2",DATM_CLMNCEP_YR_START='2000',DATM_CLMNCEP_YR_END='2001'

cat >> user_nl_elm << EOF
fsurdat = '${domainPath}${surfdataFile}'
hist_empty_htapes = .true.
hist_mfilt = 12, 30
hist_nhtfrq = 0, -24
use_snicar_ad               = .true.
use_top_solar_rad           = .false.
snow_fsca_param = 2
hist_fincl1 = 'HELBIG_SNOWDEPTH_MAX', 'HELBIG_SNOWDEPTH_MIN', 'HELBIG_SWE_MAX','HELBIG_SWE_MIN', 'FSNO_EFF', 'FSNO', 'H2OSNO', 'SNOW_DEPTH', 'HELBIG_STDV_ELEV', 'HELBIG_SLOPE_MU'
EOF

./case.setup 
./case.build 
./case.submit