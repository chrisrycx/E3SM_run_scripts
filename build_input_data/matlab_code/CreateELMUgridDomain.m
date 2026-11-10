% +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
% Creates an unstructured domain netCDF file for CLM45.
%
% INPUT:
%       lon_region = Vector containing longitude @ cell-center.
%       lat_region = Vector containing latitude @ cell-center.
%       lonv_region = Vector containing longitude @ cell-vertex.
%       latv_region = Vector containing latitude @ cell-vertex.
%       clm_gridded_domain_filename = Default CLM domain file name
%       out_netcdf_dir = Directory where CLM surface dataset will be saved
%       clm_usrdat_name = User defined name for CLM dataset
%
% Gautam Bisht (gbisht@lbl.gov)
% 01-02-2014
% +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

function fname_out = CreateELMUgridDomain(lat_region, lon_region, ...
    latv_region, lonv_region, ...
    clm_gridded_domain_filename, ...
    out_netcdf_dir, ...
    clm_usrdat_name)


fname_out = sprintf('%s/domain_%s_%s.nc',out_netcdf_dir,clm_usrdat_name,datestr(now, 'cyymmdd'));
disp(['  domain: ' fname_out])

% Check if the file is available
% [s,~]=system(['ls ' clm_gridded_domain_filename]);
%
% if (s ~= 0)
%    error(['File not found: ' clm_gridded_domain_filename]);
% end

ncid_inp = netcdf.open(clm_gridded_domain_filename,'NC_NOWRITE');
ncid_out = netcdf.create(fname_out,'NC_CLOBBER');

info_inp = ncinfo(clm_gridded_domain_filename);

[ndims,nvars,ngatts,unlimdimid] = netcdf.inq(ncid_inp);

% +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
%
%                           Define dimensions
%
% +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
nv = size(lonv_region,1);
ni = size(lonv_region,2);
nj = size(lonv_region,3);

for ii = 1:ndims
    [dimname, ndim] = netcdf.inqDim(ncid_inp,ii-1);
    switch dimname
        case 'ni'
            ndim = ni;
        case 'nj'
            ndim = nj;
        case 'nv'
            ndim = nv;
    end
    dimid(ii) = netcdf.defDim(ncid_out,dimname,ndim);
end

% +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
%
%                           Define variables
%
% +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
for ivar = 1:nvars
    [varname,xtype,dimids,natts] = netcdf.inqVar(ncid_inp,ivar-1);
    varid(ivar) = netcdf.defVar(ncid_out,varname,xtype,dimids);
    varnames{ivar} = varname;
    
    for iatt = 1:natts
        attname = netcdf.inqAttName(ncid_inp,ivar-1,iatt-1);
        attvalue = netcdf.getAtt(ncid_inp,ivar-1,attname);
        
        netcdf.putAtt(ncid_out,ivar-1,attname,attvalue);
    end
    
end

varid = netcdf.getConstant('GLOBAL');
[~,user_name]=system('echo $USER');
netcdf.putAtt(ncid_out,varid,'Created_by' ,user_name(1:end-1));
netcdf.putAtt(ncid_out,varid,'Created_on' ,datestr(now,'ddd mmm dd HH:MM:SS yyyy '))

netcdf.endDef(ncid_out);


% allocate memoery
ii_idx = zeros(size(lon_region));
jj_idx = zeros(size(lon_region));

% Get Lat/Lon for global 2D grid.
for ivar = 1:length(varnames)
    if(strcmp(varnames{ivar},'yc'))
        latixy = netcdf.getVar(ncid_inp,ivar-1);
    end
    if(strcmp(varnames{ivar},'xc'))
        longxy = netcdf.getVar(ncid_inp,ivar-1);
    end
end

% find the index
for ii=1:size(lon_region,1)
    for jj=1:size(lon_region,2)
        
        %% revised by dalei hao
        dlong = abs(longxy - lon_region(ii,jj));
        dlong(dlong>180) = 360 -  dlong(dlong>180);
        %%%%%%%%%%%%%%%%%%%
        
        dist = dlong.^2 + (latixy - lat_region(ii,jj)).^2;
        [nearest_cell_i_idx, nearest_cell_j_idx] = find( dist == min(min(dist)));
        
        
        if (length(nearest_cell_i_idx) > 1)
            disp(['  WARNING: Site with (lat,lon) = (' sprintf('%f',lat_region(ii,jj)) ...
                sprintf(',%f',lon_region(ii,jj)) ') has more than one cells ' ...
                'that are equidistant.' char(10) ...
                '           Picking the first closest grid cell.']);
            for kk = 1:length(nearest_cell_i_idx)
                disp(sprintf('\t\tPossible grid cells: %f %f', ...
                    latixy(nearest_cell_i_idx(kk),nearest_cell_j_idx(kk)), ...
                    longxy(nearest_cell_i_idx(kk),nearest_cell_j_idx(kk))));
            end
        end
        ii_idx(ii,jj) = nearest_cell_i_idx(1);
        jj_idx(ii,jj) = nearest_cell_j_idx(1);
    end
end


% +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
%
%                           Copy variables
%
% +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
for ivar = 1:nvars
    
    data = netcdf.getVar(ncid_inp,ivar-1);
    [varname,vartype,vardimids,varnatts] = netcdf.inqVar(ncid_inp,ivar-1);
    
    switch varname
        case 'xc'
            data = lon_region;
        case 'yc'
            data = lat_region;
        case 'xv'
            data = lonv_region;
        case 'yv'
            data = latv_region;
        case 'mask'
            %data = ones(size(lon_region, 1),size(lon_region, 2));
            data_2d = zeros(size(lon_region));
            for ii=1:size(lon_region,1)
                for jj=1:size(lon_region,2)
                    data_2d(ii,jj) = data(ii_idx(ii,jj),jj_idx(ii,jj));
                end
            end
            data = data_2d;
        case 'frac'
            data = ones(size(lon_region, 1),size(lon_region, 2));
        case 'area'
            % ELM reads 'area' in radian^2 (steradians) and multiplies by
            % re^2 to get km^2 (surfrdMod.F90, surfrd_get_grid). The
            % original code returned deg^2, e.g. 0.015625 for a 0.125 deg
            % cell, which ELM turned into ~634,000 km^2.
            d2r = pi/180;
            if (size(lonv_region,1) == 3)
                ax = lonv_region(1, :,:);
                ay = latv_region(1,:,:);
                bx = lonv_region(2, :,:);
                by = latv_region(2, :,:);
                cx = lonv_region(3, :,:);
                cy = latv_region(3,:,:);

                % planar area in deg^2, scaled by cos(lat) at the centroid
                % (fine for small cells)
                data = abs(0.5*(ax.*(by-cy) + bx.*(cy-ay) + cx.*(ay-by))) ...
                    .* d2r^2 .* cos(d2r*(ay + by + cy)/3);
            elseif (size(lonv_region,1) == 4)
                % exact area of a lat-lon rectangle on the unit sphere:
                % dlon * (sin(lat_top) - sin(lat_bottom)), vertices
                % ordered as in xv/yv (1-2 along longitude, 1-3 across latitude)
                data = abs(d2r*(lonv_region(1, :,:) - lonv_region(2, :,:))) .* ...
                    abs(sin(d2r*latv_region(1, :,:)) - sin(d2r*latv_region(3, :,:)));
            else
                error('Added area computation')
            end
    end
    netcdf.putVar(ncid_out,ivar-1,data);
end

netcdf.close(ncid_inp);
netcdf.close(ncid_out);