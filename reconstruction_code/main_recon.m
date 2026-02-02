clc; clear; close all;
% Some parameters also need to be set in load_mat function
%% Key Settings
settings = struct();
settings.ifRGB = 0; % 1 for RGB, 0 for monochrome
% Main control switches
settings.ifsAIKK = 1;      % 1 for sAIKK, 0 for normal FP
settings.lambda_rgb = [0.597 0.52 0.43]*1e-6; % RGB wavelengths
settings.mono_lambda = 0.52*1e-6;
% Data loading
settings.data_direc = '';

% settings.data_folder = 'Mate70_Open_data';
% settings.offsetX = 80;     % X offset
% settings.offsetY = 0;      % Y offset

settings.data_folder = 'Mate70_data';
settings.offsetX = -20;     % X offset
settings.offsetY = 15;      % Y offset

% Image processing settings
settings.totalWidth = 1536*2;  % Original image total width
settings.totalHeight = 1024*2; % Original image total height
settings.crop_horizontal_size = 150; % Input image width, crop size on acquired image
settings.crop_vertical_size = 150;   % Input image height

settings.numImg = 36;     % Number of images to read
settings.layer = 2;       % Number of outer rings
settings.loop = 80;

% Physical parameters
settings.NA = 0.240; % Numerical aperture
settings.mag = 5.2 + 0.5; % Magnification
settings.pixel_size_um = 2.4; % Pixel size of detector, unit is um
settings.zLED = (2.6 + 0.0)*1e-2; % Distance between sample and illumination source, unit is m
% Block processing settings
settings.block_size = min([150, settings.crop_horizontal_size, settings.crop_vertical_size]) ; % Size of each block in original resolution
settings.block_overlap = 0.2 ; % Overlap of adjacent blocks, instead of the spectrum
settings.block_center_size = 0.9; % Effective area ratio within each block
settings.upsam_factor = 3; % Upsampling factor
settings.block_strategy = 1 ; % 1 for using previous block pupil as input, 2 for using middle output pupil as input with parallel computing acceleration
settings.blend_method = 'cosine'; % 'gaussian', 'linear', 'cosine' - blending method for stitching
settings.show_blocks = 1; % Whether to display stitched image of all blocks
settings.block_display_downsample = 6; % Downsampling factor for block display (to avoid excessive memory)
settings.block_separator_width = 50; % Separator line width between blocks (pixels)
size_selfCal = min( 600, min(settings.crop_horizontal_size, settings.crop_vertical_size) ); % Size of self-calibration image doesn't need to be maximum, but should avoid input errors

idx_list = [1:18]; % Only use these images for final reconstruction
idx_list = [1:36];
settings.KK_used_in_index = [4,3,2,1];
%% Calculate block processing logic
block_centers = calculate_block_positions(settings.crop_horizontal_size, settings.crop_vertical_size, settings.block_size, settings.block_overlap);
block_number = size(block_centers, 1);
%% Generate stitching weight matrix
block_size_super = settings.block_size * settings.upsam_factor;
[X_w, Y_w] = meshgrid(1:block_size_super, 1:block_size_super);
center_w = round( (block_size_super + 1) / 2 );

switch settings.blend_method
    case 'linear'
        % Linear weights (Pyramidal) - edges to zero
        dist_x = 1 - abs(X_w - center_w) / (center_w - 1);
        dist_y = 1 - abs(Y_w - center_w) / (center_w - 1);
        weight_matrix = dist_x .* dist_y;
        weight_matrix(weight_matrix < 0) = 0;
    case 'cosine'
        % Cosine weights (Hanning window) - theoretically optimal at 50% overlap
        % Use sin^2 window function to ensure edges are 0 and complementary at 50% overlap
        wx = sin(pi * (X_w - 1) / (block_size_super - 1)).^2;
        wy = sin(pi * (Y_w - 1) / (block_size_super - 1)).^2;
        weight_matrix = wx .* wy;
    case 'gaussian'
        % Gaussian weights
        sigma = block_size_super / 6;
        weight_matrix = exp(-((X_w - center_w).^2 + (Y_w - center_w).^2) / (2 * sigma^2));
end
%% Load data
if settings.ifRGB == 1
    % Pre-allocate metadata
    metadata = cell(1, 3);
    % RGB image loading
    for num = 1:3
        % Select different suffix based on loop index
        switch num
            case 1; current_data_folder = fullfile(settings.data_folder, 'r');
            case 2; current_data_folder = fullfile(settings.data_folder, 'g');
            case 3; current_data_folder = fullfile(settings.data_folder, 'b');
        end
        metadata{num} = load_mat(settings, current_data_folder);
    end
else
    % Monochrome mode data loading
    current_data_folder = fullfile(settings.data_folder);
    metadata = cell(1, 1);
    metadata{1} = load_mat(settings, current_data_folder);
end
%% Self-calibration to confirm image order
if settings.ifRGB == 1
    wavelength_um = settings.lambda_rgb(2)*1e6;
    temp = metadata{2};% For multi-color, use only G channel image for position calibration by default
    temp_Img = temp.I;
    temp_Img = center_crop(  size_selfCal, temp_Img);
    temp.I = temp_Img;
    output = self_calib_Laura(temp , wavelength_um);
else
    wavelength_um = settings.mono_lambda*1e6;
    temp = metadata{1};
    temp_Img = temp.I;
    temp_Img = center_crop(  size_selfCal, temp_Img);
    temp.I = temp_Img;
    output = self_calib_Laura(temp, wavelength_um);
end

% Merge calibration information into metadata of each color channel
num_image_stacks = length(metadata);
for i = 1:num_image_stacks
    metadata{i}.source_list = output.source_list;
    metadata{i}.self_cal = output.self_cal;
    metadata{i}.rad_cal = output.rad_cal;
end
clear output; clear temp_Img; clear temp; % Clean up temporary variables

%% Reconstruction image selection
new_metadata = metadata; 
for i = 1:num_image_stacks
    % Filter images
    new_metadata{i}.I = new_metadata{i}.I(:, :, idx_list);
    new_metadata{i}.bk = new_metadata{i}.bk(:, idx_list);
    
    % Filter calibration information
    sl = new_metadata{i}.source_list;
    if isfield(sl, 'na_design'), sl.na_design = sl.na_design(idx_list, :); end
    if isfield(sl, 'na_calib'),  sl.na_calib  = sl.na_calib(idx_list, :);  end
    if isfield(sl, 'na_nRO'),    sl.na_nRO    = sl.na_nRO(idx_list, :);    end
    new_metadata{i}.source_list = sl;
    
    sc = new_metadata{i}.self_cal;
    if isfield(sc, 'DFI'), sc.DFI = sc.DFI(idx_list, :); end
    new_metadata{i}.self_cal = sc;
end
clear metadata;
%% Reconstruct by color and blocks
% Initialize full field-of-view matrix (after super-resolution)
recon_x = settings.crop_horizontal_size * settings.upsam_factor;
recon_y = settings.crop_vertical_size * settings.upsam_factor;

% Pre-allocate final results
if settings.ifRGB == 1
    sAIKK_full_FOV = zeros(recon_y, recon_x, 3);
    AIKK_full_FOV = zeros(recon_y, recon_x, 3);
    color_num = 3;
else
    sAIKK_full_FOV = zeros(recon_y, recon_x);
    AIKK_full_FOV = zeros(recon_y, recon_x);
    color_num = 1;
end

% Initialize block collection
if settings.show_blocks
    % Calculate actual grid size
    block_centers_sorted_x = unique(block_centers(:,1));
    block_centers_sorted_y = unique(block_centers(:,2));
    block_grid_x = length(block_centers_sorted_x);
    block_grid_y = length(block_centers_sorted_y);
    
    display_size = settings.block_size * settings.upsam_factor / settings.block_display_downsample;
    sep = settings.block_separator_width;
    total_height = block_grid_y * display_size + (block_grid_y + 1) * sep;
    total_width = block_grid_x * display_size + (block_grid_x + 1) * sep;
    if settings.ifRGB == 2
        blocks_collection = ones(total_height, total_width, 3);
    else
        blocks_collection = ones(total_height, total_width);
    end
end

tic;
for color_i = 1:color_num
    if settings.ifRGB == 1; color_index = color_i;
    else; color_index = 1;end
    
    % Initialize single channel accumulator (use double, and allocate only one channel per loop)
    sAIKK_phase_acc = zeros(recon_y, recon_x);
    sAIKK_amp_acc = zeros(recon_y, recon_x);
    AIKK_phase_acc = zeros(recon_y, recon_x);
    AIKK_amp_acc = zeros(recon_y, recon_x);
    weight_acc = zeros(recon_y, recon_x);
    
    for num = 1 : block_number
        fprintf('\rProcessing: Color %d/%d, Block %d/%d', color_index, color_num, num, block_number);
        pupil = 1;
        [part_sAIKK, part_AIKK, pupil] = sAIKK_single_color(new_metadata{color_index}, block_centers(num, :) , settings, color_index, pupil);
        
        % Collect blocks for display
        if settings.show_blocks
            block_display = imresize(abs(part_sAIKK), 1/settings.block_display_downsample);
            % Calculate grid position based on block center coordinates
            [~, grid_x] = min(abs(block_centers_sorted_x - block_centers(num, 1)));
            [~, grid_y] = min(abs(block_centers_sorted_y - block_centers(num, 2)));
            
            y_pos = grid_y * sep + (grid_y - 1) * display_size + 1;
            x_pos = grid_x * sep + (grid_x - 1) * display_size + 1;
            y_end_pos = min(y_pos + display_size - 1, size(blocks_collection, 1));
            x_end_pos = min(x_pos + display_size - 1, size(blocks_collection, 2));
            actual_h = min(display_size, y_end_pos - y_pos + 1);
            actual_w = min(display_size, x_end_pos - x_pos + 1);
            if settings.ifRGB == 2
                blocks_collection(y_pos:y_pos+actual_h-1, x_pos:x_pos+actual_w-1, color_i) = block_display(1:actual_h, 1:actual_w);
            else
                blocks_collection(y_pos:y_pos+actual_h-1, x_pos:x_pos+actual_w-1) = block_display(1:actual_h, 1:actual_w);
            end
        end
        
        % Block boundaries in original resolution
        block_center_orig = block_centers(num, :);
        block_size_orig = settings.block_size;
        x_start_orig = round(block_center_orig(1) - block_size_orig/2);
        x_end_orig = round(block_center_orig(1) + block_size_orig/2 - 1);
        y_start_orig = round(block_center_orig(2) - block_size_orig/2);
        y_end_orig = round(block_center_orig(2) + block_size_orig/2 - 1);
        % Map to super-resolution coordinates (multiply directly by magnification factor)
        x_start = (x_start_orig - 1) * settings.upsam_factor + 1;
        x_end = x_end_orig * settings.upsam_factor;
        y_start = (y_start_orig - 1) * settings.upsam_factor + 1;
        y_end = y_end_orig * settings.upsam_factor;
        
        % Use pre-computed weight matrix
        weight = weight_matrix;
        
        % Accumulate phase field (directly accumulate phase values)
        sAIKK_phase_acc(y_start:y_end, x_start:x_end) = sAIKK_phase_acc(y_start:y_end, x_start:x_end) + angle(part_sAIKK) .* weight;
        AIKK_phase_acc(y_start:y_end, x_start:x_end) = AIKK_phase_acc(y_start:y_end, x_start:x_end) + angle(part_AIKK) .* weight;
        
        % Accumulate amplitude field
        sAIKK_amp_acc(y_start:y_end, x_start:x_end) = sAIKK_amp_acc(y_start:y_end, x_start:x_end) + abs(part_sAIKK) .* weight;
        AIKK_amp_acc(y_start:y_end, x_start:x_end) = AIKK_amp_acc(y_start:y_end, x_start:x_end) + abs(part_AIKK) .* weight;
        
        weight_acc(y_start:y_end, x_start:x_end) = weight_acc(y_start:y_end, x_start:x_end) + weight;
    end
    
    % Single color channel processing completed, immediately calculate and release accumulator memory
    % Calculate average amplitude
    amp_sAIKK = sAIKK_amp_acc ./ (weight_acc + eps);
    amp_AIKK = AIKK_amp_acc ./ (weight_acc + eps);
    
    % Calculate average phase
    phase_sAIKK = sAIKK_phase_acc ./ (weight_acc + eps);
    phase_AIKK = AIKK_phase_acc ./ (weight_acc + eps);
    
    % Merge and store in final results
    if settings.ifRGB == 1
        sAIKK_full_FOV(:,:,color_index) = amp_sAIKK .* exp(1j * phase_sAIKK);
        AIKK_full_FOV(:,:,color_index) = amp_AIKK .* exp(1j * phase_AIKK);
    else
        sAIKK_full_FOV = amp_sAIKK .* exp(1j * phase_sAIKK);
        AIKK_full_FOV = amp_AIKK .* exp(1j * phase_AIKK);
    end
    
    % Clean up temporary variables
    clear sAIKK_phase_acc sAIKK_amp_acc AIKK_phase_acc AIKK_amp_acc weight_acc amp_sAIKK amp_AIKK phase_sAIKK phase_AIKK;
end
end_time = toc;
fprintf('\nAll processing completed, time elapsed: %d s\n', end_time);

% Display stitched result of all blocks
if settings.show_blocks
    figure('Name', 'All stitched blocks');    imshow(blocks_collection, []);
end
%% Display results
if settings.ifRGB == 1
    figure('Name','sAIKK');
    subplot(2,3,1); imshow(abs( sAIKK_full_FOV(:,:,1) ), []); title('sAIKK-r-amp');
    subplot(2,3,2); imshow(abs( sAIKK_full_FOV(:,:,2) ), []); title('sAIKK-g-amp');
    subplot(2,3,3); imshow(abs( sAIKK_full_FOV(:,:,3) ), []); title('sAIKK-b-amp');
    subplot(2,3,4); imshow(angle(sAIKK_full_FOV(:,:,1) ), []); title('sAIKK-r-phase');
    subplot(2,3,5); imshow(angle( sAIKK_full_FOV(:,:,2) ), []); title('sAIKK-g-phase');
    subplot(2,3,6); imshow(angle( sAIKK_full_FOV(:,:,3) ), []); title('sAIKK-b-phase');
    figure('Name','AIKK');
    subplot(2,3,1); imshow(abs( AIKK_full_FOV(:,:,1) ), []); title('AIKK-r-amp');
    subplot(2,3,2); imshow(abs( AIKK_full_FOV(:,:,2) ), []); title('AIKK-g-amp');
    subplot(2,3,3); imshow(abs( AIKK_full_FOV(:,:,3) ), []); title('AIKK-b-amp');
    subplot(2,3,4); imshow(angle(AIKK_full_FOV(:,:,1) ), []); title('AIKK-r-phase');
    subplot(2,3,5); imshow(angle( AIKK_full_FOV(:,:,2) ), []); title('AIKK-g-phase');
    subplot(2,3,6); imshow(angle( AIKK_full_FOV(:,:,3) ), []); title('AIKK-b-phase');

    rgb_sAIKK = composeRGB(sAIKK_full_FOV);
    rgb_AIKK = composeRGB(AIKK_full_FOV);
    figure;
    subplot(1,2,1); imshow(rgb_sAIKK, []); title('sAIKK');
    subplot(1,2,2); imshow(rgb_AIKK, []); title('AIKK');
else
    figure('Name','Single color reconstruction');
    subplot(1,2,1); imshow(abs(sAIKK_full_FOV), []);
    % title('sAIKK-amp');
    temp =   (  angle(sAIKK_full_FOV));
    subplot(1,2,2); imshow(temp, []); title('sAIKK-phase');
    figure('Name','AIKK Single color');
    subplot(1,2,1); imshow(abs(AIKK_full_FOV), []); title('AIKK-amplitude');
    subplot(1,2,2); imshow(angle(AIKK_full_FOV), []); title('AIKK-phase');
end
%% Save results
