 %%%%% Illumination Calibration Script %%%%%
function out = self_calib_Laura(selfCal, wavelength_um)
addpath('Utilities')
% *** Imaging system parameters *** %
% Define:
%   I: image stack, NxNxM (for M images)
%   NA: objective NA                      
%   mag: total magnification
%   dpix_c: pixel size (um)
%   lambda: imaging wavelength (um)
%   freqUV: expected spatial frequency of illumination (1/um), Mx2, ('x' in
%           column 1, 'y' in column 2)
I=selfCal.I;
NA=selfCal.objective.na;
mag=selfCal.objective.mag*selfCal.objective.system_mag;
dpix_c=selfCal.camera.pixel_size_um*1e-6;
lambda=wavelength_um;
freqUV=selfCal.source_list.na_design/lambda;

% *** Controls for removing outliers *** %
removeOut=1; %Whether you want to remove outliers and extend to darkfield (generally a good idea)
method='rigidScale'; %Option for transformation from original guess to new
%guess, used to remove outliers that do not fit that transformation.
%Possibilities are: 'rigid' (rotation and shift),'rigidScale' (rotation, shift, & scale),
%'affine'(rotation, shift, scale, & shear), 'projective'\
alpha=2; %Multiplier by stdev to get outliers (usually 2-3)
scale=0.5; %Value between 0.01 and 0.99; what the weight of suspected outliers is multiplied by at each iteration
tol=0.05; %Level where we consider something an outlier (should be low, ~0.05)

% *** Controls for circle-finding *** %
rScan=[5 0.5]; %[+/- to scan, delta(r)] %Radius scan boundaries and granularity
%Row #1 = radius estimation, row #2 = center estimation
thScan=[10 1; 5  0.5]; %Theta scan boundaries and granularity
dScan=[20 1; 5 0.5]; %Distance scan boundaries and granularity
calRad=0; %Whether or not to calibrate the radius (recommended to do so)
%% Define system
%Set up space
imSz=size(I);
N=imSz(1:2);
numImg=imSz(3);
imSz(3)=[];

tic;

%Define the coordinates in frequency space in terms of pixels and k-space
%(u,v); convert pixel coord to polar (centD, theta); get the conversion
%factor from k-space to pixels (con)
[ freqXY, con, radP, xI, yI, uI, vI, XYmid ] = calCoord(freqUV,imSz,dpix_c,mag, NA, lambda );

%Convert to distance (pixels), theta (degrees) of circle center from center frequency
freqDTh=cart2Pol(freqXY, XYmid);

%Get Fourier space amplitude images that will be processed
sigmaG=2; %Amount of blurring to use in a Gaussian filter (generally = 2 gives good results)
[FIdiv, FIdivG, FI, w_2NA] = calFI(I, xI, yI, XYmid, radP, sigmaG);
%% Identify darkfield
[ DFI ] = calDF( FI, XYmid );

%Print number of brightfield and darkfield images
fprintf('%i BF, %i DF\n',sum(~DFI),sum(DFI))

%% Find circles
%Find circles for the brightfield images only
[ freqDTh3, rad_cal] = calCircEdge(FIdivG(:,:,~DFI), I(:,:,~DFI), radP, freqDTh(~DFI,:), XYmid, xI, yI, sigmaG, rScan, thScan, dScan, calRad, con, lambda);

freqDTh2=freqDTh;
freqDTh2(~DFI,:)=freqDTh3; %Replace the brightfield values only

freqXY_noRemoveOut=pol2Cart(freqDTh2,XYmid); %Save the result before removing outliers to compare

if removeOut

    [ freqDTh2 ] = removeOutliers(freqDTh, freqDTh2, XYmid, method,alpha, scale, tol, DFI);
    %When include DFI, it doesn't use the darkfield to fit but it does
    %replaces darkfield with fit values (if you don't include the DFI
    %variable, it does not extend to darkfield)

end

freqXY2 = pol2Cart(freqDTh2,XYmid);

%% Format output & save
%Convert back to k-space values
freqUV_cal=(freqXY2-repmat(XYmid,[numImg 1]))./con;
freqUV_noRemoveOut=(freqXY_noRemoveOut-repmat(XYmid,[numImg 1]))./con;
NA_cal=(rad_cal./con).*lambda;
w_NA_cal=double(sqrt(uI.^2 + vI.^2)<rad_cal);

illumNA=lambda.*sqrt(freqUV_cal(:,1).^2 + freqUV_cal(:,2).^2);
[illumNAsorted,illumIdx]=sort(illumNA);
t_cal=toc;

% Save values
out.source_list.na_design=freqUV.*lambda;
out.source_list.na_calib=freqUV_cal.*lambda;
out.source_list.na_nRO=freqUV_noRemoveOut.*lambda;

out.self_cal.na_cal=NA_cal;
out.self_cal.time_cal_s=t_cal;
out.self_cal.DFI=DFI;
% 
out.rad_cal = rad_cal;
% 
%% Display results
figure('Position', [100 100 600 550], 'Color', 'w'); 
ax = gca;
hold on;

color_original = [0.00, 0.45, 0.74]; 
color_calib = [0.85, 0.33, 0.10];  
color_line = [0.5, 0.5, 0.5];   

% 
plot([freqUV(:,1), freqUV_cal(:,1)]', [freqUV(:,2), freqUV_cal(:,2)]', ...
    '-', 'Color', color_line, 'LineWidth', 1.0, 'HandleVisibility', 'off');

% 
h1 = plot(freqUV(:,1), freqUV(:,2), 'o', ...
    'MarkerSize', 8, 'MarkerEdgeColor', color_original, ...
    'MarkerFaceColor', color_original, 'LineWidth', 1.5, ...
    'DisplayName', 'Original');
h2 = plot(freqUV_cal(:,1), freqUV_cal(:,2), 's', ...
    'MarkerSize', 7, 'MarkerEdgeColor', color_calib, ...
    'MarkerFaceColor', color_calib, 'LineWidth', 1.5, ...
    'DisplayName', 'Self-Calib');

% 
lgd = legend([h1, h2], 'Location', 'best');
lgd.FontName = 'Arial';
lgd.FontSize = 15;
lgd.FontWeight = 'bold';
lgd.Color = 'w';
lgd.TextColor = 'k';
lgd.Box = 'off';

% 
axis equal;
grid on;
ax.GridLineStyle = ':';
ax.GridAlpha = 0.3;
ax.FontName = 'Arial';
ax.FontSize = 15;
ax.FontWeight = 'bold';
ax.XColor = 'k';
ax.YColor = 'k';
ax.LineWidth = 1.5;
ax.Box = 'on';

% 
ax.XLim = [-1, 1];
ax.YLim = [-1, 1];
ax.XTick = min(ax.XLim):0.5:max(ax.XLim);
ax.YTick = min(ax.YLim):0.5:max(ax.YLim);

hold off;

% sliderDisplayImVC2(abs(FI(:,:,~DFI)), cat(3,[freqXY(~DFI,:) radP.*ones(sum(~DFI),1)],[freqXY2(~DFI,:) rad_cal.*ones(sum(~DFI),1)]),{'caxis([0 1e6])','title(''Brightfield Only: (red) Uncalibrated, (green) Calibrated'')'});
sliderDisplayImVC2(abs(FI), cat(3, [freqXY radP.*ones(numImg,1)], [freqXY2 rad_cal.*ones(numImg,1)]),{'caxis([0 1e6])','title(''All Images: (red) Uncalibrated, (green) Calibrated'')'});
end