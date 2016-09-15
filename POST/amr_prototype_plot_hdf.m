function main
    % AMR prototype - plotscript
    clear all
    close all
    clc
    h=figure
    
    case_name = '../'; %'test'
    %case_name = 'gauss_one_block_correct';
    %case_name = 'gauss_4_blocks';
    %case_name = 'gauss_64_blocks';
    %case_name = 'gauss_bs17_maxlevel6';
    %case_name = 'wavelet_opt';
    
    switch case_name
        case '../'
            dirname = '../';
            Bs = 17;
            g = 4;
        case 'gauss_one_block_correct'
            dirname = '../data/gauss_one_block_correct/';
            Bs = 513;
            g = 4;  
        case 'gauss_4_blocks'
            dirname = '../data/gauss_4_blocks/';
            Bs = 257;
            g = 4; 
        case 'gauss_64_blocks'
            dirname = '../data/gauss_64_blocks/';
            Bs = 257;
            g = 4; 
        case 'gauss_bs17_maxlevel6'
            dirname = '../data/gauss_bs17_maxlevel6/';
            Bs = 17;
            g = 4;
        case 'test'
            dirname = '../data/wavelet_test_IV/';
            Bs = 17;
            g = 4;
        case 'wavelet_opt'
            dirname = '../data/gauss_bs17_maxlevel6_wavelet_opt/';
            Bs = 17;
            g = 4;
    end  
  
    files = dir([dirname 'data_*.h5']);
    
    % loop over files
    for k = 1:length(files)
        
        if (k==300)
            k = k;
        end
        
        % get filename
        filename = [dirname files(k).name];
        % read the file
        [data, time, error, nblocks, detail] = read_wabbit_hdf( filename );
        
        % errors, ...
        errors(k) = error;
        t(k) = time;
        blocks(k) = nblocks;

        %------------
        % plotting
        %------------
        clf
        hold on    
        for j=1:length(data)
            coord_x = data(j).coord_x;
            coord_y = data(j).coord_y;
            
            datafield = data(j).field(g+1:Bs+g,g+1:Bs+g);

            % no plotting for block points in positive axis direction (overlap with neigbor block)
            [X,Y] = meshgrid( coord_x, coord_y );
            pcolor(X,Y,datafield)

            line([ coord_x(1) coord_x(1) ],[ coord_y(1) coord_y(end)],'color','w')
            line([ coord_x(end) coord_x(end) ],[ coord_y(1) coord_y(end)],'color','w')

            line([ coord_x(1) coord_x(end) ],[ coord_y(1) coord_y(1)],'color','w')
            line([ coord_x(1) coord_x(end) ],[ coord_y(end) coord_y(end)],'color','w')

        end

        % detail plotting
%         for j=1:length(data)
%             coord_x = data(j).coord_x;
%             coord_y = data(j).coord_y;
%             
%             datafield = data(j).field(g+1:Bs+g,g+1:Bs+g);
%             %if data(j).detail >= 1e-3 %1e-2
%                 datafield = 0.*datafield + data(j).detail;
%             %else
%             %    datafield = 0.*datafield;
%             %end
% 
%             % no plotting for block points in positive axis direction (overlap with neigbor block)
%             [X,Y] = meshgrid( coord_x, coord_y );
%             pcolor(X,Y,datafield)
% 
%             line([ coord_x(1) coord_x(1) ],[ coord_y(1) coord_y(end)],'color','w')
%             line([ coord_x(end) coord_x(end) ],[ coord_y(1) coord_y(end)],'color','w')
% 
%             line([ coord_x(1) coord_x(end) ],[ coord_y(1) coord_y(1)],'color','w')
%             line([ coord_x(1) coord_x(end) ],[ coord_y(end) coord_y(end)],'color','w')
% 
%         end

        shading flat
        
        colorbar
        
        axis equal
        %title(filename)
        title(['step ' num2str(k-1)])
        caxis([0 1e-3])
        
        drawnow
        %saveas(h,sprintf('FIG%d.png',k));
    

    end
    
    % error plot
    figure
    semilogy(t, errors)
    title('error')
    
    % block number plot
    figure
    plot(t, blocks)
    title('number of blocks')
    ylim([30 80])
    
end

function [data, time, error, nblocks, detail] = read_wabbit_hdf( filename )
    %% [data, time] = read_wabbit_hdf( filename )
    % read in a block-based adaptive mesh, as generated by WABBIT code.
    % the struct 'data' will contain the elements 'data.field', 'data.coord_y',
    % 'data.coord_y'

    % open file in read-only mode
    file_id = H5F.open( filename, 'H5F_ACC_RDWR','H5P_DEFAULT');

    % determine how many blocks we have in the file
    group_id = H5G.open( file_id, '/');
    info = H5G.get_info(group_id);
    nblocks = info.nlinks;
    fprintf('file %s contains %i blocks\n',filename, nblocks)

    % now we know how many blocks (datasets) we found in the file, and we
    % will loop over all of them
    for i = 1 : nblocks
        dsetname = H5L.get_name_by_idx ( file_id, '/', 'H5_INDEX_NAME','H5_ITER_INC', i-1, 'H5P_DEFAULT');
        % read the block from the file (we now know its name)
        [field, coord_x, coord_y, time, error, detail] = read_block_HDF5( file_id, dsetname );
        % copy data to structure (slow; since data list is not preallocated)
        data(i).field = field;
        data(i).coord_x = coord_x;
        data(i).coord_y = coord_y;
        data(i).detail = detail;
    end

    H5G.close(group_id)
    H5F.close(file_id)

end

function [field, coord_x, coord_y, time, error, detail] = read_block_HDF5( file_id, dsetname )

    % open the dataset in the file
    dset_id = H5D.open( file_id, dsetname);

    attr_id = H5A.open( dset_id, 'coord_x');
    coord_x = H5A.read( attr_id );
    H5A.close(attr_id);

    attr_id = H5A.open( dset_id, 'coord_y');
    coord_y = H5A.read( attr_id );
    H5A.close(attr_id);

    % fetch time from the dataset
    attr_id = H5A.open( dset_id, 'time');
    time = H5A.read( attr_id );
    H5A.close(attr_id);

    % error
    attr_id = H5A.open( dset_id, 'errors');
    error = H5A.read( attr_id );
    H5A.close(attr_id);    
    
    % detail
    attr_id = H5A.open( dset_id, 'detail');
    detail = H5A.read( attr_id );
    H5A.close(attr_id);  

    % read file
    field = H5D.read( dset_id,'H5ML_DEFAULT', ...  ) % format in memory hier
        'H5S_ALL',... MEMORY
        'H5S_ALL',... DISK
        'H5P_DEFAULT');


    % close remaining HDF5 objects
    H5D.close(dset_id)

    field=double(field);
end