%% define directory
originalDir = '/';
cfg.clm_gridded_domain_filename = [originalDir '/global/cfs/cdirs/e3sm/inputdata/share/domains/domain.lnd.r05_gx1v6.191014.nc'];
cfg.clm_gridded_surfdata_filename = [originalDir '/global/cfs/cdirs/e3sm/inputdata/lnd/clm2/surfdata_map/surfdata_0.5x0.5_simyr2010_c230922_with_TOP.nc'];

topDir = '/';
cfg.clm_gridded_topodata_filename = [topDir '/global/cfs/cdirs/e3sm/inputdata/lnd/clm2/surfdata_map/surfdata_0.5x0.5_simyr2010_c230922_with_TOP.nc'];

fscaDir = '/';
%% cfg.clm_gridded_topfsca_filename = [topDir '/global/cfs/cdirs/m4986/data/enrico_data/topo_fsca_125_v2.nc'];
cfg.clm_gridded_topfsca_filename = [fscaDir '/global/cfs/cdirs/m4986/data/enrico_data/topo_fsca_125.nc'];


cfg.out_netcdf_dir = "/global/cfs/cdirs/m4986/data/enrico_data/Tony_Grove_UT_FSCA/";

if ~exist(cfg.out_netcdf_dir, 'dir')
    mkdir(cfg.out_netcdf_dir)
end

cfg.set_natural_veg_frac_to_one = 0;
%% define parameter

cfg.res_h = 0.125;
cfg.res_v = 0.125;

lat_tops = [42.5];
lat_bottoms = [41.0];
lon_lefts = [248.0];
lon_rights = [249.0];

for i = 1:1
    cfg.lat_top = lat_tops(i);
    cfg.lat_bottom = lat_bottoms(i);
    cfg.lon_left = lon_lefts(i);
    cfg.lon_right = lon_rights(i);
    cfg.is_0_360 = 1;
    cfg.clm_usrdat_name = 'TG_UT_0125';
    
    ELMSparseGridDriver(cfg)
end



