function block_centers = calculate_block_positions(img_width, img_height, block_size, block_overlap)
% Calculate image block positions (sorted from center outward by "ring" and angle)

    overlap_size = round(block_size * block_overlap);
    step = block_size - overlap_size;  % Actual step size
    
    % Image center coordinates
    img_center_x = round((img_width + 1) / 2);
    img_center_y = round((img_height + 1) / 2);

    % Starting position of center block (align block center with image center)
    center_x1 = img_center_x - round( (block_size + 1) / 2 );
    center_y1 = img_center_y - round( (block_size + 1) / 2 );
    
    % Calculate number of blocks to expand in each direction
    blocks_left = ceil((center_x1 - 1) / step);
    blocks_right = ceil((img_width - center_x1 - block_size) / step);
    blocks_up = ceil((center_y1 - 1) / step);
    blocks_down = ceil((img_height - center_y1 - block_size) / step);
    
    num_blocks_x = blocks_left + 1 + blocks_right;
    num_blocks_y = blocks_up + 1 + blocks_down;
    
    % Output parameter information
    fprintf('Input image: %d x %d\n', img_height, img_width);
    fprintf('Block settings: %d x %d blocks, block size %d x %d\n', num_blocks_y, num_blocks_x, block_size, block_size);
    
    % Vectorized grid index generation
    total_blocks = num_blocks_y * num_blocks_x;
    [J, I] = meshgrid(-blocks_left:blocks_right, -blocks_up:blocks_down);
    I = I(:);
    J = J(:);
    
    % Vectorized calculation of top-left corner coordinates for all blocks
    x1_all = round(center_x1 + J * step);
    y1_all = round(center_y1 + I * step);
    
    % Vectorized boundary check and correction
    x1_all = max(1, min(x1_all, img_width - block_size + 1)); % Avoid being less than 1 or exceeding right boundary
    y1_all = max(1, min(y1_all, img_height - block_size + 1));
    
    % Calculate bottom-right corner coordinates and block centers
    x2_all = x1_all + block_size - 1;
    y2_all = y1_all + block_size - 1;
    center_x_all = round((x1_all + x2_all) / 2);
    center_y_all = round((y1_all + y2_all) / 2);
    
    % Calculate sorting criteria: ring level and angle
    ring_levels = max(abs(I), abs(J));
    dx = center_x_all - img_center_x;
    dy = center_y_all - img_center_y;
    angles = mod(atan2d(dx, -dy) + 360, 360);
    
    % Sort by "ring" level (primary) and clockwise angle (secondary)
    [~, sort_idx] = sortrows([ring_levels, angles], [1, 2]);
    
    block_positions = [x1_all(sort_idx), y1_all(sort_idx), x2_all(sort_idx), y2_all(sort_idx)];
    block_centers = [center_x_all(sort_idx), center_y_all(sort_idx)];
    
    fprintf('Total %d blocks, sorted from center outward in "ring" order\n', total_blocks);
    fprintf('Block 1 center: (%.1f, %.1f), Image center: (%.1f, %.1f)\n', ...
             block_centers(1,1), block_centers(1,2), img_center_x, img_center_y);
    
    % Call visualization function
    visualize_blocks(img_width, img_height, block_positions, block_centers);
end


function visualize_blocks(img_width, img_height, block_positions, block_centers)
% Visualize block positions and sequence numbers

    figure('Name', 'Block Visualization');
    hold on;
    axis equal;
    set(gca, 'YDir', 'reverse');  % Y-axis downward
    
    % Draw image boundary
    rectangle('Position', [0, 0, img_width, img_height], ...
              'EdgeColor', 'k', 'LineWidth', 2);
    
    num_blocks = size(block_positions, 1);
    colors = jet(num_blocks);  % Color mapping: from blue (center) to red (periphery)
    
    % Draw each block
    for i = 1:num_blocks
        x1 = block_positions(i, 1);
        y1 = block_positions(i, 2);
        x2 = block_positions(i, 3);
        y2 = block_positions(i, 4);
        
        width = x2 - x1 + 1;
        height = y2 - y1 + 1;
        
        % Draw rectangle
        rectangle('Position', [x1-0.5, y1-0.5, width, height], ...
                  'EdgeColor', colors(i, :), 'LineWidth', 1.5);
        
        % Label sequence number
        center_x = block_centers(i, 1);
        center_y = block_centers(i, 2);
        text(center_x, center_y, num2str(i), ...
             'HorizontalAlignment', 'center', ...
             'FontSize', 10, 'FontWeight', 'bold', ...
             'Color', colors(i, :));
    end
    
    % Mark image center
    img_center_x = round( (img_width + 1) / 2 );
    img_center_y = round( (img_height + 1) / 2 );
    plot(img_center_x, img_center_y, 'r+', 'MarkerSize', 15, 'LineWidth', 2);
    text(img_center_x, img_center_y - 30, 'Image Center', ...
         'HorizontalAlignment', 'center', 'FontSize', 12, 'Color', 'r');
    
    title(sprintf('Block Visualization, Total %d Blocks', num_blocks));
    xlabel('X / Pixels');
    ylabel('Y / Pixels');
    grid on;
    hold off;
end
