function [part_sAIKK, part_AIKK, pupil] = sAIKK_single_color(metadata, block_centers, settings, color_i, pupil)
F      = @(x) ifftshift(fft2(fftshift(x))); %Fourier Transform
iF     = @(x) ifftshift(ifft2(fftshift(x))); %Inverse Fourier Transform
logamp = @(x) log(abs(x));
%% Key settings
ifsAIKK = settings.ifsAIKK;%1 for sAIKK, 0 for normal FP
if settings.ifRGB == 1
    lambda = settings.lambda_rgb(color_i);
else
    lambda = settings.mono_lambda;
end
%% Load data
KK_used_in_index = settings.KK_used_in_index;
mag = settings.mag;
NA_obj = settings.NA;
dpix_c = settings.pixel_size_um;
zLED = settings.zLED;
k = 2*pi/(lambda);

I = metadata.I; 
NsampR=size(I);
numImg = NsampR(3);
% Select frequency domain coordinates
freqUV_noCal = metadata.source_list.na_design;
freqUV_Cal = metadata.source_list.na_calib;
freqUV_used = freqUV_noCal;
freqUV_used = freqUV_Cal;
% rad_cal = metadata.rad_cal;

loop = settings.loop;% Iteration
%% Crop original image
m1_want =settings.block_size;
temp = I;

% Calculate crop region boundaries
crop_x_start = round( block_centers(1) - m1_want/2 );
crop_x_end = round( block_centers(1) + m1_want/2 - 1 );
crop_y_start = round( block_centers(2) - m1_want/2 );
crop_y_end = round( block_centers(2) + m1_want/2 - 1);

I = ones(m1_want,m1_want,numImg);
for v = 1:numImg
    I(:,:,v) = temp(crop_y_start:crop_y_end, crop_x_start:crop_x_end, v);
end
m1 = m1_want;
n1 = m1;
%% Set radius
esize = dpix_c/mag*1e-6;
cutoff_f = NA_obj*k;
kmax = pi/(esize);
[kxm,kym] = meshgrid(-kmax : kmax / ( (n1-1) / 2 ) : kmax, -kmax : kmax / ( (m1-1) / 2 ) : kmax);
CTF = ( (kxm.^2+kym.^2)<=cutoff_f^2 );

[m, n] = size(CTF);
center_row = floor(m/2)+1;
center_col = floor(n/2)+1;
% Count the number of 1s in the center row
diameter = sum(CTF(center_row, :));
radius = diameter / 2;

radi = round( radius*1.0);
%% Calculate NA offset for each block (theoretical value, based on geometric relationship)
X = block_centers(1) - settings.crop_horizontal_size/2;
Y = block_centers(2) - settings.crop_vertical_size/2;
% Object plane coordinates (meters)
x_o = X * esize;
y_o = Y * esize;
kx_real = -sin(atan2(-x_o, zLED));
ky_real = -sin(atan2(-y_o, zLED));
% NA offset for each block
if_NA_offset = 0;
NA_offset_block = 2*if_NA_offset .* [ +kx_real, ky_real ];   % B×2  multiply by coefficient for correction
freqUV_used = freqUV_used + NA_offset_block;
%% Load images
upsample_ratio = settings.upsam_factor;        % upsampling ratio
fsize       = esize/upsample_ratio; % pixel size of high-res image on sample plane, in m
m = m1*upsample_ratio;n = m1*upsample_ratio;

kx = k*freqUV_used(:, 1); ky = k*freqUV_used(:, 2);
dkx = 2*pi/(fsize*n);dky = 2*pi/(fsize*m);
cutoff_f = NA_obj*k;
kmax = pi/(esize);
[kxm,kym] = meshgrid(-kmax : kmax / ( (n1-1) / 2 ) : kmax, -kmax : kmax / ( (m1-1) / 2 ) : kmax);
CTF = ( sqrt(kxm.^2+kym.^2)<=cutoff_f );
%% 1_up
X1=m1/2+radi;Y1=m1/2;
hologram = I(:,:, KK_used_in_index(1) );
temp     = hologram;
ref_FT = zeros(size(temp));
ref_FT(X1,Y1) = 6.0e+04 - 4.6e+03i;
ref_wave  = iF(ref_FT);
Re_X   = 1/2*(log(hologram)-log(abs(ref_wave).^2));
F_Re_X = F(Re_X);
J = ones(size(temp));
J((end/2+1):end,:)=-1;
J(end/2+1,:)=0;
Im_X      = -1i.*iF(J.*F_Re_X);
X         = Re_X+1i*Im_X;
recover_S1 = (exp(X)-1).*ref_wave;
%% 2_left
X2=m1/2;Y2=m1/2+radi;
hologram = I(:,:, KK_used_in_index(2) );
temp     = hologram;
ref_FT = zeros(size(temp));
ref_FT(X2,Y2) = 6.0e+04 - 4.6e+03i;
ref_wave  = iF(ref_FT);
Re_X   = 1/2*(log(hologram)-log(abs(ref_wave).^2));
F_Re_X = F(Re_X);
J = ones(size(temp));
J(:,(end/2+1):end)=-1;
J(:,end/2+1)=0;
Im_X      = -1i.*iF(J.*F_Re_X);
X         = Re_X+1i*Im_X;
recover_S2 = (exp(X)-1).*ref_wave;
%% 3_bottom
X3=m1/2-radi;Y3=m1/2;
hologram = I(:,:, KK_used_in_index(3) );
temp     = hologram;
ref_FT = zeros(size(temp));
ref_FT(X3,Y3) = 6.0e+04 - 4.6e+03i;
ref_wave  = iF(ref_FT);
Re_X   = 1/2*(log(hologram)-log(abs(ref_wave).^2));
F_Re_X = F(Re_X);
J = ones(size(temp));
J(1:end/2,:)=-1;
J(end/2+1,:)=0;
Im_X      = -1i.*iF(J.*F_Re_X);
X         = Re_X+1i*Im_X;
recover_S3 = (exp(X)-1).*ref_wave;
%% 4_right
X4=m1/2;Y4=m1/2-radi;
hologram = I(:,:, KK_used_in_index(4) );
temp     = hologram;
ref_FT = zeros(size(temp));
ref_FT(X4,Y4) = 6.0e+04 - 4.6e+03i;
ref_wave  = iF(ref_FT);
Re_X   = 1/2*(log(hologram)-log(abs(ref_wave).^2));
F_Re_X = F(Re_X);
J = ones(size(temp));
J(:,1:end/2)=-1;
J(:,end/2+1)=0;
Im_X      = -1i.*iF(J.*F_Re_X);
X         = Re_X+1i*Im_X;
recover_S4 = (exp(X)-1).*ref_wave;
%% stitch together
CTF_KK=zeros(m1);
for i=1:m1
    for j=1:m1
        if sqrt((i-m1/2)^2+(j-m1/2)^2)<=radi
            CTF_KK(i,j)=1;
        end
    end
end
temp1    = circshift(F(recover_S1).*CTF_KK,[m1/2-X1,m1/2-Y1]);
circ1    = circshift(CTF_KK,[m1/2-X1,m1/2-Y1]);
temp2    = circshift(F(recover_S2).*CTF_KK,[m1/2-X2,m1/2-Y2]);
circ2    = circshift(CTF_KK,[m1/2-X2,m1/2-Y2]);
temp3    = circshift(F(recover_S3).*CTF_KK,[m1/2-X3,m1/2-Y3]);
circ3    = circshift(CTF_KK,[m1/2-X3,m1/2-Y3]);
temp4    = circshift(F(recover_S4).*CTF_KK,[m1/2-X4,m1/2-Y4]);
circ4    = circshift(CTF_KK,[m1/2-X4,m1/2-Y4]);
tempall=temp1+temp2+temp3+temp4;
circall=circ1+circ2+circ3+circ4;
recoverFT=tempall./circall ; % Prevent division by zero
recoverFT(isnan(recoverFT)) = 0;
recoverFT=circshift(recoverFT,[1 1]);
scKK=iF(recoverFT);
%% Spectrum expansion
objectRecoverFT = F(ones(m,n));
if ifsAIKK ==1
    initial_guess = padarray(recoverFT, [(m - size(recoverFT, 1)) / 2, (n - size(recoverFT, 2)) / 2], 0, 'both');
    objectRecoverFT = initial_guess;
end

LED_correct_Index = ones(1,loop*numImg);
images_to_use = 1:numImg;

OP_alpha =0.8;
OP_beta = 0.8;

alphaO = 1;                                                             % the parameter of rPIE
alphaP = 1;                                                             % the parameter of rPIE
%% 重建算法的选择
run recon_FP;

pupil = exp(1i*angle(pupil));
part_sAIKK = out_obj;
part_AIKK = scKK;
part_AIKK = imresize(part_AIKK, size(part_AIKK)*upsample_ratio);
end

