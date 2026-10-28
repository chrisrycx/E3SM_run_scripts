#!/bin/sh

RES=ELMMOS_USRDAT
COMPSET=20TR_DATM%GSWP3v1_ELM%SPBC_SICE_SOCN_MOSART_SGLC_SWAV
MACH=pm-cpu
COMPILER=gnu
PROJECT=m3780

FORCING=gfdl-esm4
SCENARIO=historical

SRC_DIR=/global/homes/d/donghui/e3sm_surface_water
CASE_DIR=${SRC_DIR}/cime/scripts

cd ${SRC_DIR}

GIT_HASH=`git log -n 1 --format=%h`
CASE_NAME=GLOBE_Surface_Water_Projection_cal12_fmax_${FORCING}_${SCENARIO}_${GIT_HASH}.`date "+%Y-%m-%d-%H%M%S"`

cd ${SRC_DIR}/cime/scripts

./create_newcase -case ${CASE_DIR}/${CASE_NAME} \
-res ${RES} -mach ${MACH} -compiler ${COMPILER} -compset ${COMPSET} --project ${PROJECT}


cd ${CASE_DIR}/${CASE_NAME}

./xmlchange -file env_run.xml -id DOUT_S             -val FALSE
./xmlchange -file env_run.xml -id INFO_DBUG          -val 2

./xmlchange DATM_MODE=CLMGSWP3v1
./xmlchange CLM_USRDAT_NAME=test_r05_r05
./xmlchange LND_DOMAIN_FILE=domain_lnd_GLOBE_1d.nc
./xmlchange ATM_DOMAIN_FILE=domain_lnd_GLOBE_1d.nc
./xmlchange LND_DOMAIN_PATH=/global/cfs/projectdirs/m3780/donghui/Global-Surface-Water-Dynamics-Projection/inputdata
./xmlchange ATM_DOMAIN_PATH=/global/cfs/projectdirs/m3780/donghui/Global-Surface-Water-Dynamics-Projection/inputdata
./xmlchange CIME_OUTPUT_ROOT=/global/cfs/projectdirs/m3780/donghui/Global-Surface-Water-Dynamics-Projection/scripts/cal12_fmax/outputs

./xmlchange -file env_run.xml -id DATM_CLMNCEP_YR_END -val 2014
./xmlchange -file env_run.xml -id DATM_CLMNCEP_YR_START -val 1951
./xmlchange -file env_run.xml -id DATM_CLMNCEP_YR_ALIGN -val 1951

./xmlchange ELM_CO2_TYPE='diagnostic',CCSM_BGC='CO2A'
./xmlchange RUN_STARTDATE=1951-01-01

./xmlchange PIO_BUFFER_SIZE_LIMIT=67108864
./xmlchange STOP_N=64,STOP_OPTION=nyears
./xmlchange JOB_QUEUE=regular
./xmlchange NTASKS=384
./xmlchange JOB_WALLCLOCK_TIME=24:00:00

./preview_namelists

cat >> user_nl_mosart << EOF
frivinp_rtm = '/global/cfs/projectdirs/m3780/donghui/Global-Surface-Water-Dynamics-Projection/inputdata/MOSART_GLOBE_1d_c230915.nc'
inundflag = .true.
opt_elevprof = 1
routingmethod = 2
EOF

cat >> user_nl_elm << EOF
fsurdat = '/global/cfs/projectdirs/m3780/donghui/Global-Surface-Water-Dynamics-Projection/inputdata/surfdata_GLOBE_1d_calibrated_12_fmax.nc'
flanduse_timeseries = '/global/cfs/projectdirs/m3780/donghui/Global-Surface-Water-Dynamics-Projection/inputdata/landuse.timeseries_0.5x0.5_HIST_simyr1850-2015_GLOBAL_1d_c240229.nc'
check_dynpft_consistency = .false.
use_modified_infil = .true.
EOF

cat >> user_nl_datm << EOF
tintalgo = 'coszen', 'nearest', 'linear', 'linear', 'lower'
dtlimit=2.0e0,2.0e0,2.0e0,2.0e0,2.0e0
streams = "datm.streams.txt.CLMGSWP3v1.Solar 1951 1951 2014",
      "datm.streams.txt.CLMGSWP3v1.Precip 1951 1951 2014",
      "datm.streams.txt.CLMGSWP3v1.TPQW 1951 1951 2014",
      "datm.streams.txt.presaero.trans_1850-2000 1849 1849 2015",
      "datm.streams.txt.topo.observed 1 1 1",
      "datm.streams.txt.co2tseries.20tr 1750 1750 2014"
EOF

./case.setup
# ---------------------------------------------------------------------------- #
# **************************************************************************** #
# ---------------------------------------------------------------------------- #
files1=""
for i in {1951..2014}
do
   for j in {1..12}
   do
      if [ $j -lt 10 ]
      then
         files1="${files1}clmforc.${FORCING}.${SCENARIO}.c2107.0.5x0.5.Prec.$i-0$j.nc\n"
      else
         if [ $i == 2014 ] && [ $j == 12 ]
         then
             files1="${files1}clmforc.${FORCING}.${SCENARIO}.c2107.0.5x0.5.Prec.$i-$j.nc"
         else
             files1="${files1}clmforc.${FORCING}.${SCENARIO}.c2107.0.5x0.5.Prec.$i-$j.nc\n"
         fi
      fi
   done
done

cp ${CASE_DIR}/${CASE_NAME}/CaseDocs/datm.streams.txt.CLMGSWP3v1.Precip ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Precip2
chmod +rw ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Precip2
sed '30,796d' ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Precip2 > ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Precip
rm ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Precip2
chmod +rw ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Precip

perl -w -i -p -e "s@/global/cfs/cdirs/e3sm/inputdata/atm/datm7/atm_forcing.datm7.GSWP3.0.5d.v1.c170516/Precip@/global/cfs/projectdirs/m3780/donghui/data/forcings/${FORCING}/${SCENARIO}/Prec@" ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Precip
perl -w -i -p -e "s@/global/cfs/cdirs/e3sm/inputdata/atm/datm7/atm_forcing.datm7.GSWP3.0.5d.v1.c170516@/global/cfs/projectdirs/m3780/donghui/Runoff_Projection_Uncertainty/inputdata@" ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Precip
perl -w -i -p -e "s@domain.lnd.360x720_gswp3.0v1.c170606.nc@domain.lnd.360x720_isimip.3b.c211109.nc@" ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Precip
perl -w -i -p -e "s@clmforc.GSWP3.c2011.0.5x0.5.Prec.1951-01.nc@${files1}@" ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Precip
sed -i '/ZBOT/d' ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Precip
# ---------------------------------------------------------------------------- #
# **************************************************************************** #
# ---------------------------------------------------------------------------- #
files2=""
for i in {1951..2014}
do
   for j in {1..12}
   do
      if [ $j -lt 10 ]
      then
         files2="${files2}clmforc.${FORCING}.${SCENARIO}.c2107.0.5x0.5.Solr.$i-0$j.nc\n"
      else
         if [ $i == 2014 ] && [ $j == 12 ]
         then
             files2="${files2}clmforc.${FORCING}.${SCENARIO}.c2107.0.5x0.5.Solr.$i-$j.nc"
         else
             files2="${files2}clmforc.${FORCING}.${SCENARIO}.c2107.0.5x0.5.Solr.$i-$j.nc\n"
         fi
      fi
   done
done

cp ${CASE_DIR}/${CASE_NAME}/CaseDocs/datm.streams.txt.CLMGSWP3v1.Solar ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Solar2
chmod +rw ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Solar2
sed '30,796d' ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Solar2 > ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Solar
rm ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Solar2
chmod +rw ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Solar

perl -w -i -p -e "s@/global/cfs/cdirs/e3sm/inputdata/atm/datm7/atm_forcing.datm7.GSWP3.0.5d.v1.c170516/Solar@/global/cfs/projectdirs/m3780/donghui/data/forcings/${FORCING}/${SCENARIO}/Solr@" ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Solar
perl -w -i -p -e "s@/global/cfs/cdirs/e3sm/inputdata/atm/datm7/atm_forcing.datm7.GSWP3.0.5d.v1.c170516@/global/cfs/projectdirs/m3780/donghui/Runoff_Projection_Uncertainty/inputdata@" ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Solar
perl -w -i -p -e "s@domain.lnd.360x720_gswp3.0v1.c170606.nc@domain.lnd.360x720_isimip.3b.c211109.nc@" ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Solar
perl -w -i -p -e "s@clmforc.GSWP3.c2011.0.5x0.5.Solr.1951-01.nc@${files2}@" ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Solar
sed -i '/ZBOT/d' ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.Solar
# ---------------------------------------------------------------------------- #
# **************************************************************************** #
# ---------------------------------------------------------------------------- #
files3=""
for i in {1951..2014}
do
   for j in {1..12}
   do
      if [ $j -lt 10 ]
      then
         files3="${files3}clmforc.${FORCING}.${SCENARIO}.c2107.0.5x0.5.TPQWL.$i-0$j.nc\n"
      else
         if [ $i == 2014 ] && [ $j == 12 ]
         then
             files3="${files3}clmforc.${FORCING}.${SCENARIO}.c2107.0.5x0.5.TPQWL.$i-$j.nc"
         else
             files3="${files3}clmforc.${FORCING}.${SCENARIO}.c2107.0.5x0.5.TPQWL.$i-$j.nc\n"
         fi
      fi
   done
done

cp ${CASE_DIR}/${CASE_NAME}/CaseDocs/datm.streams.txt.CLMGSWP3v1.TPQW ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.TPQW2
chmod +rw ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.TPQW2
sed '27d' ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.TPQW2 > ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.TPQW3
rm ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.TPQW2
chmod +rw ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.TPQW3
sed '33,799d' ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.TPQW3 > ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.TPQW
rm ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.TPQW3
chmod +rw ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.TPQW

perl -w -i -p -e "s@/global/cfs/cdirs/e3sm/inputdata/atm/datm7/atm_forcing.datm7.GSWP3.0.5d.v1.c170516/TPHWL@/global/cfs/projectdirs/m3780/donghui/data/forcings/${FORCING}/${SCENARIO}/TPQWL@" ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.TPQW
perl -w -i -p -e "s@/global/cfs/cdirs/e3sm/inputdata/atm/datm7/atm_forcing.datm7.GSWP3.0.5d.v1.c170516@/global/cfs/projectdirs/m3780/donghui/Runoff_Projection_Uncertainty/inputdata@" ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.TPQW
perl -w -i -p -e "s@domain.lnd.360x720_gswp3.0v1.c170606.nc@domain.lnd.360x720_isimip.3b.c211109.nc@" ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.TPQW
perl -w -i -p -e "s@clmforc.GSWP3.c2011.0.5x0.5.TPQWL.1951-01.nc@${files3}@" ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.TPQW
sed -i '/ZBOT/d' ${CASE_DIR}/${CASE_NAME}/user_datm.streams.txt.CLMGSWP3v1.TPQW
# ---------------------------------------------------------------------------- #
# **************************************************************************** #
# ---------------------------------------------------------------------------- #

# ---------------------------------------------------------------------------- #
# **************************************************************************** #
# ---------------------------------------------------------------------------- #
cp ./CaseDocs/datm.streams.txt.co2tseries.20tr ./user_datm.streams.txt.co2tseries.20tr
chmod +rw ./user_datm.streams.txt.co2tseries.20tr
perl -w -i -p -e "s@/global/cfs/cdirs/e3sm/inputdata/atm/datm7/CO2@/global/cfs/cdirs/m3520/share/cesm_inputdata/co2@" ./user_datm.streams.txt.co2tseries.20tr
perl -w -i -p -e "s@fco2_datm_1765-2007_c100614.nc@fco2_datm_global_simyr_1750-2014_CMIP6_c180929.nc@" ./user_datm.streams.txt.co2tseries.20tr
sed -i '/ZBOT/d' ./user_datm.streams.txt.co2tseries.20tr

cp ./CaseDocs/datm.streams.txt.presaero.trans_1850-2000 ./user_datm.streams.txt.presaero.trans_1850-2000
chmod +rw ./user_datm.streams.txt.presaero.trans_1850-2000
perl -w -i -p -e "s@/global/cfs/cdirs/e3sm/inputdata/atm/cam/chem/trop_mozart_aero/aero@/global/cfs/cdirs/m3520/share/cesm_inputdata/aero_deposit_data@" ./user_datm.streams.txt.presaero.trans_1850-2000
perl -w -i -p -e "s@aerosoldep_monthly_1849-2006_1.9x2.5_c090803.nc@aerosoldep_monthly_1849-2015_0.9x1.25_CMIP6_c180924.nc@" ./user_datm.streams.txt.presaero.trans_1850-2000
sed -i '/ZBOT/d' ./user_datm.streams.txt.presaero.trans_1850-2000
# ---------------------------------------------------------------------------- #
# **************************************************************************** #
# ---------------------------------------------------------------------------- #

./case.setup

./case.build

./case.submit
