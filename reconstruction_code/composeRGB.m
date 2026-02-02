function rgb_image = composeRGB(rgb_results)

if ~isreal(rgb_results)
    r = double(abs(rgb_results(:,:,1)));
    g = double(abs(rgb_results(:,:,2)));
    b = double(abs(rgb_results(:,:,3)));
else
    r = double(rgb_results(:,:,1));
    g = double(rgb_results(:,:,2));
    b = double(rgb_results(:,:,3));
end

% ============================================================
% Registration
% ============================================================
fprintf('Performing RGB channel registration...\n');

[H, W] = size(g);
crop_h = round(H * 0.6);
crop_w = round(W * 0.6);
y_start = round((H - crop_h) / 2);
x_start = round((W - crop_w) / 2);
g_crop = g(y_start:y_start+crop_h, x_start:x_start+crop_w);
r_crop = r(y_start:y_start+crop_h, x_start:x_start+crop_w);
b_crop = b(y_start:y_start+crop_h, x_start:x_start+crop_w);

%Align Red to Green
[dy_r, dx_r, ~] = phaseCorrShift(g_crop, r_crop);
if abs(dx_r) <= 50 && abs(dy_r) <= 50
    r = imtranslate(r, [dx_r, dy_r], 'cubic', 'FillValues', 0);
    fprintf('  Red channel shift: dx=%.2f, dy=%.2f\n', dx_r, dy_r);
else
    fprintf('  Red channel shift too large or invalid, skipped.\n');
end

% Align Blue to Green
[dy_b, dx_b, ~] = phaseCorrShift(g_crop, b_crop);
if abs(dx_b) <= 50 && abs(dy_b) <= 50
    b = imtranslate(b, [dx_b, dy_b], 'cubic', 'FillValues', 0);
    fprintf('  Blue channel shift: dx=%.2f, dy=%.2f\n', dx_b, dy_b);
else
    fprintf('  Blue channel shift too large or invalid, skipped.\n');
end

clear g_crop r_crop b_crop;

% ============================================================
% Inpainting
% ============================================================
r = removeOutliersInpaint(r, [7 7], 3.0); 
g = removeOutliersInpaint(g, [7 7], 3.0);
b = removeOutliersInpaint(b, [7 7], 3.0);

r = medfilt2(r, [3 3]);
g = medfilt2(g, [3 3]);
b = medfilt2(b, [3 3]);

r = robustNormalize(r, 0.0, 99.5);
g = robustNormalize(g, 0.0, 99.5);
b = robustNormalize(b, 0.0, 99.5);

% Align R and B histograms to G
r = histogramMatchCDF(r, g);
b = histogramMatchCDF(b, g);

% 4) Compose RGB image
rgb_image = cat(3, r, g, b);
rgb_image = min(max(rgb_image, 0), 1);
end

function clean_channel = removeOutliersInpaint(channel, k_size, sigma_thresh)
    
    bg_est = medfilt2(channel, k_size, 'symmetric');
    diff_map = channel - bg_est;
    
    mad_val = median(abs(diff_map(:) - median(diff_map(:))));
    sigma_est = 1.4826 * mad_val;
    limit = max(sigma_thresh * sigma_est, 1e-4); 
    
    mask = diff_map > limit;
    
    se = strel('disk', 2); 
    mask_dilated = imdilate(mask, se);
    
    clean_channel = regionfill(channel, mask_dilated);
    
end

function im_norm = robustNormalize(im, low_p, high_p)
    v_low  = prctile(im(:), low_p);
    v_high = prctile(im(:), high_p);
    if v_high <= v_low, im_norm = im; return; end
    im_norm = (im - v_low) / (v_high - v_low);
    im_norm = min(max(im_norm, 0), 1);
end

function rgb_reg = registerRGB(rgb_in, refIdx)
    if nargin<2, refIdx = 2; end
    rgb_reg = rgb_in;
    ref = mat2gray(rgb_in(:,:,refIdx));
    for c = 1:3
        if c == refIdx, continue; end
        mov0 = mat2gray(rgb_in(:,:,c));
        [dy, dx, conf] = phaseCorrShift(ref, mov0);
        max_shift = 50;
            if abs(dx) > max_shift || abs(dy) > max_shift
                continue;
            end
        mov_aligned = imtranslate(mov0, [dx dy], 'cubic', 'FillValues', 0);
        rgb_reg(:,:,c) = mov_aligned;
    end
end

function [dy, dx, confidence] = phaseCorrShift(A, B)
    A = double(A); B = double(B);
    A = A - mean(A(:)); B = B - mean(B(:));
    win = hann(size(A,1)) * hann(size(A,2))';
    A = A .* win; B = B .* win;
    FA = fft2(A); FB = fft2(B);
    R = FA .* conj(FB);
    R = R ./ max(abs(R), eps);
    r = ifft2(R);
    [~, idx] = max(r(:));
    [ypeak, xpeak] = ind2sub(size(r), idx);
    [H, W] = size(r);
    if ypeak > H/2, ypeak = ypeak - H; end
    if xpeak > W/2, xpeak = xpeak - W; end
    dy_sub = quadInterp1D(r, ypeak, xpeak, 1);
    dx_sub = quadInterp1D(r, ypeak, xpeak, 2);
    dy = ypeak + dy_sub;
    dx = xpeak + dx_sub;
    r_abs = abs(r);
    peak_val = max(r_abs(:));
    r_sorted = sort(r_abs(:), 'descend');
    second_peak = r_sorted(2);
    confidence = peak_val / (second_peak + eps); 
    if confidence < 1.5, dy = 0; dx = 0; return; end
    end
    
    function d = quadInterp1D(r, y0, x0, dim)
    [h,w] = size(r);
    y = y0; x = x0;
        if dim==1
            y1 = wrap(y-1, h); y2 = wrap(y, h); y3 = wrap(y+1, h);
            c1 = r(y1, wrap(x,w)); c2 = r(y2, wrap(x,w)); c3 = r(y3, wrap(x,w));
        else
            x1 = wrap(x-1, w); x2 = wrap(x, w); x3 = wrap(x+1, w);
            c1 = r(wrap(y,h), x1); c2 = r(wrap(y,h), x2); c3 = r(wrap(y,h), x3);
        end
    den = c1 - 2*c2 + c3;
        if abs(den) < 1e-9
            d = 0;
        else
            d = 0.5 * (c1 - c3) / den; 
            d = max(min(d, 0.5), -0.5);
        end
    end
    
    function idx = wrap(i, n)
    idx = i;
    idx(idx < 1) = idx(idx < 1) + n;
    idx(idx > n) = idx(idx > n) - n;
end

function matched = histogramMatchCDF(source, reference)

    [counts_src, edges_src] = histcounts(source(:), 256, 'BinLimits', [0 1]);
    [counts_ref, edges_ref] = histcounts(reference(:), 256, 'BinLimits', [0 1]);
    
    cdf_src = cumsum(counts_src) / numel(source);
    cdf_ref = cumsum(counts_ref) / numel(reference);
    
    bin_centers_src = (edges_src(1:end-1) + edges_src(2:end)) / 2;
    bin_centers_ref = (edges_ref(1:end-1) + edges_ref(2:end)) / 2;
    
    [cdf_ref_unique, idx_unique] = unique(cdf_ref);
    bin_centers_ref_unique = bin_centers_ref(idx_unique);
    
    cdf_src_vals = interp1(bin_centers_src, cdf_src, source(:), 'linear', 'extrap');
    matched = interp1(cdf_ref_unique, bin_centers_ref_unique, cdf_src_vals, 'linear', 'extrap');
    matched = reshape(matched, size(source));
    matched = min(max(matched, 0), 1);
end