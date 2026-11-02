
% add variables in surfadata:
srcFile  = '/global/cfs/cdirs/m4986/data/enrico_data/WUS_surface_data_FSCA/topofsca_WUS_0125_c260113.nc';
destFile = '/global/cfs/cdirs/m4986/data/enrico_data/WUS_surface_data_FSCA/surfdata_WUS_0125_c260113_merged.nc';

srcID  = netcdf.open(srcFile,'NOWRITE');
destID = netcdf.open(destFile,'NC_WRITE');
netcdf.reDef(destID);


vars2copy = {'fsca_slope_mu', 'fsca_stddev_elev'};

for v = 1:numel(vars2copy)
    varName = vars2copy{v};

    % Get variable ID from source
    srcVarID = netcdf.inqVarID(srcID,varName);

    % Get variable info
    [~, xtype, dimIDs, natts] = netcdf.inqVar(srcID,srcVarID);
    disp(xtype)
    disp(dimIDs)
    disp(natts)

    % Define variable in destination
    destVarID = netcdf.defVar(destID,varName,xtype,flip(dimIDs)); % note: swap order of dimensions for consistency

    % Copy attributes
    for a = 0:natts-1
        attName = netcdf.inqAttName(srcID,srcVarID,a);
        netcdf.copyAtt(srcID,srcVarID,attName,destID,destVarID);
    end

    % Copy data
    netcdf.endDef(destID);
    data = netcdf.getVar(srcID,srcVarID);
    netcdf.putVar(destID,destVarID,data);
    netcdf.reDef(destID);
end

% Close files
netcdf.endDef(destID);
netcdf.close(srcID);
netcdf.close(destID);