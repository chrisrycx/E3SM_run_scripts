#! /bin/bash
module load python/3.10

export domainPath=/global/cfs/cdirs/m4986/data/enrico_data/WUS_surface_data/
export domainFile=domain_WUS_0125_c220106.nc
export surfdataFile=surfdata_with_top_WUS_0125_c220106.nc
export RES=ELM_USRDAT 
export COMPSET=IELMBC
export COMPILER=gnu
export MACH=pm-cpu
export CASE_NAME=spinup_WUS_dyn_shape
export output_dir=/global/cfs/cdirs/m4986/data/enrico_data/spinup_WUS_res/
export case_dir=/$output_dir/$CASE_NAME
export case_scripts_dir=/$case_dir/case_scripts
 cd /global/homes/e/enricoz/E3SM_SHP/cime/scripts/
./create_newcase -compset ${COMPSET} -res ${RES} -case ${CASE_NAME} -compiler ${COMPILER} -mach ${MACH} -project m4986 
cd ${case_scripts_dir}
./xmlchange LND_DOMAIN_FILE=${domainFile} 
./xmlchange ATM_DOMAIN_FILE=${domainFile} 
./xmlchange LND_DOMAIN_PATH=${domainPath}
./xmlchange ATM_DOMAIN_PATH=${domainPath}
./xmlchange NTASKS=512,STOP_N=5,STOP_OPTION=nyears,JOB_WALLCLOCK_TIME="10:00:00",RUN_STARTDATE="1979-01-01",REST_N=1,REST_OPTION=nyears,RESUBMIT=4
./xmlchange DATM_MODE=CLMMOSARTTEST,DATM_CLMNCEP_YR_START='1979',DATM_CLMNCEP_YR_END='2010'
# finidat = '${initPath}${initFile}'
# fsnowoptics = '${domainPath}snicar_optics_5bnd_mam_c211006.nc'
cat >> user_nl_elm << EOF
fsurdat = '${domainPath}${surfdataFile}'
use_top_solar_rad           = .false.
hist_empty_htapes           = .true.
hist_fincl1                 = 'FSA','FSH','EFLX_LH_TOT','FSNO','SNOWDP','H2OSNO','SNORDSL', 'SNO_GS','SNO_DEN','SNO_SPH'
hist_nhtfrq                 = 0
hist_mfilt                  = 12
snow_shape_defined          = 1
use_snicar_ad               = .true.
use_snicar_frc              = .true.
is_dust_internal_mixing		= .false.
is_BC_internal_mixing		= .true.
snicar_atm_type				= 1
use_dynamic_snow_shape      = .false.
EOF
./case.setup 
./case.build 
./case.submit
