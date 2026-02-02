function out = center_crop(dimen,I)
    [row, column, ~] = size(I);

    center_x = ((column + 1) / 2);
    center_y = ((row + 1) / 2);
    
    x_start = round(center_x - (dimen - 1)/2);
    x_end = round(center_x + (dimen - 1)/2);
    
    y_start = round(center_y - (dimen - 1)/2);
    y_end = round(center_y + (dimen - 1)/2);

    out = I(y_start:y_end, x_start:x_end, :);
end