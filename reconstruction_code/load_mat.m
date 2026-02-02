function metadata = load_mat(settings, folder2)
%% Parameters
folder1 = settings.data_direc;
m1 = settings.crop_vertical_size;
n1 = settings.crop_horizontal_size;
overlap_ratio = [0.5, 0.4];
num_Img =settings.numImg;
layer =settings.layer;
NA = settings.NA;
spsize =settings.pixel_size_um;
LED_height = settings.zLED;% Phone-to-sample distance
mag =settings.mag;
total_width = settings.totalWidth;      total_height =settings.totalHeight;

noise_threshold_factor = 20;   % Noise threshold factor (smaller value detects more points)
ifUseBackImage = 1;
useStray = 0;
elimi_dark_current = 1;
%% Load images
if contains(folder2, '-')
    spacing = extractBefore(folder2, '-');
else
    spacing = folder2;
end
spacing = str2double(spacing);
spacing = 5.7;
fprintf('Spacing: %.2f mm\n', spacing);
folder = fullfile(folder1, folder2);

offsetx = settings.offsetX;    offsety = settings.offsetY;

ystart = round( (total_height + 1) / 2 ) - round( (m1 + 1) / 2) + 1 + offsety;
yendd = ystart + m1 - 1;
xstart = round( (total_width + 1) / 2 ) - round( (n1 + 1) / 2) + 1 + offsetx;
xendd = xstart + n1 - 1;

raw_images = zeros(m1, n1, num_Img); % If all images exist
fprintf('Preprocessing images from "%s"...\n', folder);
for i = 1:num_Img
       baseFilename = sprintf('%d', i); % e.g., "1 (1)", "1 (2)"
        filenameWithExt = [baseFilename, '.tiff']; % Add extension
        filename = fullfile(folder, filenameWithExt);
    if exist(filename, 'file')
        imagesss = imread(filename);  % Read colored image
        if size(imagesss, 3) == 3;  imagesss = rgb2gray(imagesss);  end
        imagesss = double( imagesss(ystart:yendd, xstart:xendd) );  % Convert to double type
        raw_images(:,:,i) = imagesss;
    else
        fprintf('File %s does not exist.\n', filename);
    end
end
I = raw_images; % Ensure type
%% Apply 3×3 convolution to smooth noise (fixed bad pixel correction)
kernel = ones(3,3);      % 3x3 all-ones kernel
kernel(2,2) = 0;         % Exclude center point

if ifUseBackImage == 1
    backgroundImage = double( imread(fullfile(folder, 'back.tiff')) );
    backgroundImage = backgroundImage(ystart:yendd, xstart:xendd);
    
    % Detect fixed bad pixel positions in background image
    threshold = mean(backgroundImage(:)) + noise_threshold_factor*std(backgroundImage(:));
    mask = backgroundImage > threshold;
    
    % Apply neighborhood mean correction at fixed bad pixel positions for all images
    for num = 1:num_Img
        temp = I(:, :, num);
        neighbor_sum = conv2(temp, kernel, 'same');
        neighbor_count = conv2(ones(size(temp)), kernel, 'same');
        mean_neighbor = neighbor_sum ./ neighbor_count;
        temp(mask) = mean_neighbor(mask);
        temp(temp<0.01) = 0.01;
        temp = temp/(2^1);
        I(:,:, num) = temp;
    end
    
    % Mask visualization
    figure;
    index = 10;
    subplot(1,3,1); imshow(raw_images(:,:,index), []); title('Original');axis square;
    subplot(1,3,2); imshow(mask, []); title('Fixed Bad Pixel Mask');axis square;
    subplot(1,3,3); imshow(I(:,:,index), []); title('After Bad Pixel Correction');axis square;
else
    mask = ones(m1, n1);
end
%%  Stray light removal (Data preprocessing methods for robust Fourier ptychographic microscopy, 2017)
if ifUseBackImage == 1
    temp = backgroundImage;
    neighbor_sum = conv2(backgroundImage, kernel, 'same');
    neighbor_count = conv2(ones(size(backgroundImage)), kernel, 'same');
    mean_neighbor = neighbor_sum ./ neighbor_count;
    temp(mask) = mean_neighbor(mask);
    temp(temp<0.01) = 0.01;
    temp = temp/(2^1);
    backgroundImage = temp;
end

if useStray == 1
    % Display an image for manual region selection
    figure; imshow(I(:,:,14), []); title('Please manually select two regions: R1 and R2');

    disp('Please select the first region R1 on the image');
    roi_R1 = drawrectangle('Label', 'R1', 'Color', 'r');
    wait(roi_R1);
    mask_R1 = createMask(roi_R1);
    disp('Please select the second region R2 on the image');
    roi_R2 = drawrectangle('Label', 'R2', 'Color', 'g');
    wait(roi_R2);
    mask_R2 = createMask(roi_R2);
    alapa = zeros(1, num_Img);
    for num = 5:num_Img
        % Calculate weight factor based on two regions
        I_measured = I(:,:,num);
        % Calculate weight factor using R1 region
        numerator = mean([sum(sum(I_measured .* backgroundImage .* mask_R1)), sum(sum(I_measured .* backgroundImage .* mask_R2))]);
        denominator = mean([sum(sum((backgroundImage.^2) .* mask_R1)), sum(sum((backgroundImage.^2) .* mask_R2)) ]);
        alapa(num) = numerator / denominator;
        % Apply removal (similar to Equation 4 in the paper)
        I(:,:,num) = I(:,:,num) - alapa(num) * backgroundImage;
    end
    temp = alapa(5:num_Img);
    temp = mean(temp(:));
    for num = 1:25
        I(:,:, num) = I(:, :, num) - temp*backgroundImage;
    end
    % Show a comparison result before and after processing
    figure('Name', 'Weighted Background Subtraction');
    subplot(1,2,1); imshow(raw_images(:,:,14), []); title('Before Processing');
    subplot(1,2,2); imshow(I(:,:,14), []); title('After Processing');
    fprintf('Processing completed');
end
clear raw_images; % No longer need original unprocessed data
%% Dark current removal
if elimi_dark_current == 1
% Calculate maximum value of each image
for num = 1: num_Img
    I_max(num) = max(max(I(:,:,num))); % Find maximum value for each image
end
I_maxx = sum(I_max)/num_Img;
for num = 1: num_Img
    temp = I(:,:,num);
    I_std(num) = std(temp(:)); % Find maximum value for each image
end
I_stdd = sum(I_std)/num_Img;
I_threshold = (I_maxx - I_stdd)/12;
% I_threshold = 4.345934204778260e+02;
for num = 1:num_Img
    temp = I(:,:,num);
    temp(temp < I_threshold) = 0.01;
    I(:,:, num) = temp;
end
end
 %% Generate distance based on overlap ratio
spacing = spacing*1e-3; % Convert to meters (standard unit)

% Calculate theta angle corresponding to overlap ratio (through numerical solution)
theta = zeros(size(overlap_ratio));
for i = 1:length(overlap_ratio)
    % Use fzero to solve equation: overlap_ratio(i) = (2*theta - sin(2*theta))/pi
    fun = @(t) (2*t - sin(2*t))/pi - overlap_ratio(i);
    theta(i) = fzero(fun, [0, pi]); % Solve in [0,pi] range
end

% Calculate inter-ring spacing based on theta
R = 2*spacing*cos(theta);

% Calculate each ring radius
R1 = R(1) + spacing;
R2 = R1 + R(2);

ring_radius = [R1 R2];
point_spacing = [R(1), R(2)];

% Sparse ring point count, round first then ensure even number
ring_npoints = round(2*pi*ring_radius ./ point_spacing);
ring_npoints = arrayfun(@(x) x + mod(x,2), ring_npoints); % Ensure even number

xlocation = [];
ylocation = [];

    % Multi-ring generation (inner multiple rings + outer sparse rings)
% 1. Removed center point initialization (x=0, y=0)
    for k = 1:1
    r = 2 * spacing/2;  % Keep original radius calculation logic
    % 1. Right (Right)
    xlocation(end+1) = r;
    ylocation(end+1) = 0;
    % 2. Bottom (Bottom)
    xlocation(end+1) = 0;
    ylocation(end+1) = -r;
    % 3. Left (Left)
    xlocation(end+1) = -r;
    ylocation(end+1) = 0;
    % 4. Top (Top)
    xlocation(end+1) = 0;
    ylocation(end+1) = r;
end

    % Keep original outer sparse ring logic, starting from rightmost point, clockwise
    for j = 1:layer
        r = ring_radius(j);
        nn = ring_npoints(j);
        for i = 1:nn
            theta = 2*pi*(i-1)/nn; % 0 is rightmost, clockwise
            xlocation(end+1) = r * cos(-theta);
            ylocation(end+1) = r * sin(-theta);
        end
    end


xlocation = xlocation';
ylocation = ylocation';
%% 
v = [-xlocation, -ylocation, LED_height * ones(size(xlocation))];
kx_relative = v(:,1)./vecnorm(v,2,2);
ky_relative = v(:,2)./vecnorm(v,2,2);

naaa_design = [( +kx_relative), -( ky_relative)];% for normal phone+phone lens
% naaa_design = naaa_design(1:size(I , 3), :);
%% Reorder
radius_limit = sqrt(  (naaa_design(:,1).^2 + naaa_design(:,2).^2)  ) < NA*1.05;
all_radius = sqrt(xlocation.^2 + ylocation.^2);
DFI_mask = ( all_radius <= (radius_limit + eps) ); % Add small value to prevent error
DFI = logical(DFI_mask);
DFI = ~DFI;
DFI = DFI(1: size(I , 3));
%% Visualization
figure('Color','k'); 
set(gca,'Color','k', 'XTick', [], 'YTick', []); 
axis off; colormap gray; hold on; axis square;

Nimg = size(I,3);
active_x = xlocation(1:Nimg); 
active_y = ylocation(1:Nimg);

% Directly set image display size (data coordinate system)
total_range_x = range(active_x);
total_range_y = range(active_y);
max_range = max(total_range_x, total_range_y);

% Make image size 1/8 to 1/6 of total range, so it's clear without too much overlap
scalef = max_range /20;  % Can adjust this denominator: smaller value = larger image
if scalef < 1e-9, scalef = 0.1; end

% Display images
display_size = min(300, min(size(I,1), size(I,2))); % Reduce resolution for speed
% Add a selection array before displaying images
% selected_images = [ 22 ,18, 14 ,10]; % Fill in the image indices you want to display
selected_images = [1:num_Img];
% Modify loop
for idx = 1:length(selected_images)
    i = selected_images(idx); % Get actual image index
    img_resized = imresize(I(:,:,i), [display_size, display_size]);
    
    % Manually normalize image to simulate imshow([], ) effect
    img_min = min(img_resized(:));
    img_max = max(img_resized(:));
    if img_max > img_min
        img_normalized = (img_resized - img_min) / (img_max - img_min);
    else
        img_normalized = img_resized; % Avoid division by zero error
    end
    
    % Display image
    X0 = active_x(i) - scalef/2;
    Y0 = active_y(i) - scalef/2;
    
    h = imagesc([X0, X0+scalef], [Y0, Y0+scalef], img_normalized);
    set(h, 'AlphaData', 0.9);
    
    % Text label
    text(active_x(i), active_y(i) , num2str(i), ...
        'Color','w', 'FontSize',12, 'HorizontalAlignment','center', ...
        'VerticalAlignment','top', 'FontWeight','bold');
end
set(gca, 'Color', 'k');axis square;
hold off;
    %% Save as mat file
    metadata.I = I;
    metadata.objective.system_mag = 1;
    metadata.objective.na = NA;
    metadata.objective.mag = mag;
    metadata.camera.pixel_size_um = spsize*1e6;
    metadata.camera.is_color = 0;
    metadata.illumination.device_name = 'Dont care';
    metadata.illumination.z_distance_mm = LED_height*1000;
    metadata.type = 'FP';
    metadata.file_header = folder2;
    metadata.source_list.na_design = naaa_design;
    metadata.source_list.na_init = naaa_design;
    metadata.self_cal.na_cal = NA;
    metadata.self_cal.time_cal_s = 1;
    metadata.self_cal.DFI = DFI;  % Convert to column vector
    metadata.bk = zeros(2,num_Img);
end