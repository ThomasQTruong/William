% MATLAB code for calculating the midline of the tube in motion
% Read video.
video = VideoReader("william.mp4");
% Get video properties
timestamp = datestr(now, 'yyyymmdd_HHMMSS');
videoWriter = VideoWriter(['./output/meow_', timestamp]);
videoWriter.FrameRate = video.FrameRate;
open(videoWriter);

global failed_left_most_column;
failed_left_most_column = 9999;

global failed_right_most_column;
failed_right_most_column = -9999;

% Main function. [✔]
while hasFrame(video)
   [gray_image] = Grayscale_Video(video);
   [enhanced_image] = Enhancement(gray_image);
   [midline_x, midline_y, midline_points] = Midline(enhanced_image);
   [frameWithMidline] = MidlineFrame(midline_x, midline_y, enhanced_image);
   writeVideo(videoWriter, frameWithMidline);
end
close(videoWriter);


% Converts to grayscale. [✔]
function [gray_image] = Grayscale_Video(video)
   % Read each frame
   % Convert to grayscale
   % Erode image to leave pixels of tube
   frame = readFrame(video);
   grayFrame = rgb2gray(frame);
   SE = strel('disk',2,0);
   k1 = imerode(grayFrame,SE);
   gray_image = grayFrame-k1;
end


% Enhances image. [✔]
function [enhanced_image] = Enhancement(gray_image)
   % Define the region to "remove" (set to 0)
   % Remove watermark
   rowsToRemove = 670:720; 
   colsToRemove = 1025:1280; 
   gray_image(rowsToRemove, colsToRemove) = 0;
   img_flattened = gray_image(:);  % This converts the matrix to a column vector
   img_no_zeros = nonzeros(img_flattened);  % This function returns all non-zero values
   percentile_80 = prctile(img_no_zeros, 80);
   gray_image(gray_image < 100) = 0;  % Set pixels below 80th percentile to zero
   enhanced_image = gray_image;
end


% Calculates the midpoints for the midline. [╰（‵□′）╯]
function [midline_x, midline_y, midline_points] = Midline(enhanced_image)
    % Initialize arrays to store midline positions
    midline_x = [];
    midline_y = [];
    midline_points = [];

    % Size of the frame
    [row_indices, col_indices] = find(enhanced_image);

    threshold_factor = 2.5;
    threshold_value = 100;
    distances = [];

    % Grab all distances for each row.
    for row = 1:size(enhanced_image, 1)
        rowCols = col_indices(row_indices == row);
        if ~isempty(rowCols)
            % Get the leftmost and rightmost non-zero pixels
            leftMost = min(rowCols);     % First non-zero pixel (left most)
            rightMost = max(rowCols);    % Last non-zero pixel (right most)
            current_distance = rightMost - leftMost;
            distances = [distances, current_distance];
        end
    end

    % Remove outliers using percentiles
    percentile_40 = prctile(distances, 40);
    percentile_60 = prctile(distances, 60);

    % Remove distances that are outside the bounds
    valid_distances = distances(distances >= percentile_40 & distances <= percentile_60);

    % Calculate the average of the valid distances
    avg_distance = round(mean(valid_distances));

    columns_scanned = [];
    % For every row of the image.
    for row = 1:size(enhanced_image, 1)
        rowCols = col_indices(row_indices == row);
        count = countJumps(rowCols);
        if count == 0  % No jumps (blank), skip.
            continue;
        elseif count == 1  % Only one jump.
            % Get the left-most and right-most values.
            [leftVal, rightVal] = pixelJump(rowCols);

            current_distance = abs(leftVal - rightVal);
            if current_distance >= (avg_distance / (threshold_factor)) && ...
                        current_distance <= (avg_distance * threshold_factor)
                midPoint = round((leftVal + rightVal) / 2);

                midline_x = [midline_x, midPoint];
                midline_y = [midline_y, row];
            end
        else  % countJumps > 1: failed.
            % Get the left-most and right-most values.
            [leftVal, rightVal] = pixelJump(rowCols);
            if (isnan(leftVal) || isnan(rightVal))
                continue;
            end

            % For each column within the failed region.
            for column = leftVal:rightVal
                % Already scanned.
                if (ismember(column, columns_scanned))
                    continue;
                end

                colRows = row_indices(col_indices == column);
                [topVal, bottomVal] = pixelJump(colRows);
                % No boundary exists, skip.
                if (isnan(topVal) || isnan(bottomVal))
                    continue;
                end

                % Calculate the vertical distance between the top-most and bottommost pixels
                current_distance = abs(bottomVal - topVal);
            
                % Apply the vertical distance check
                if current_distance >= (avg_distance / (threshold_factor)) && ...
                            current_distance <= (avg_distance * threshold_factor)
                    % Calculate midpoint between topmost and next wall
                    midPoint = round((topVal + bottomVal) / 2);

                    % Store the midline (column and row)
                    midline_x = [midline_x, column];
                    midline_y = [midline_y, midPoint];
                    columns_scanned = [columns_scanned, column];
                end
            end
        end
    end
    
    % Sort points: First by Y (top to bottom), then by X (right to left)
    [midline_y, sorted_idx] = sort(midline_y); % Sort by Y (top to bottom)
    midline_x = midline_x(sorted_idx);  % Sort corresponding X

    % Now, sort by X (right to left) for rows with the same Y-value
    [midline_x, sorted_idx] = sort(midline_x, 'descend'); % Right to left sort
    midline_y = midline_y(sorted_idx);  % Maintain order for Y-values

    % Example of storing points in midline_points
    midline_points = [midline_x; midline_y];  % 2 x N matrix
end


% Create the video. [✔]
function [frameWithMidline] = MidlineFrame(midline_x, midline_y, enhanced_image)
   persistent ax;  % Use a persistent variable to store the axis
   if isempty(ax)
       % Only create the axis once if it doesn't exist
       fig = figure('Visible', 'off');  % Invisible figure to hold the axis
       ax = axes(fig);  % Create axes in the figure
   end
   imshow(enhanced_image, []);  % Display the processed image
   hold on;
  
   % Plot the midline as a red line connecting the midline points
   if ~isempty(midline_x) && ~isempty(midline_y)  % Ensure midline points are valid
       plot(midline_x, midline_y, 'r-', 'LineWidth', 2, 'Parent', ax);  % Red line for midline
   end
   hold off;
  
   % Capture the frame as an image (this will be the image with the midline)
   frameWithMidline = getframe(ax);  % Get the current figure as a frame
end


function [edge1, edge2] = pixelJump(indexes)
    if (isempty(indexes))
        return
    end

    edge1 = indexes(1);
    edge2 = NaN;
    
    % For each value in the column rows except first.
    for val = 2:length(indexes)
        % Is not an increment of 1.
        if (edge1 + 1 ~= indexes(val))
            edge2 = indexes(val);
            break;
        end
        edge1 = indexes(val);
    end
    return
end


function [count] = countJumps(indexes)
    count = 0;
    if (isempty(indexes))
        return
    end

    previous = indexes(1);

    % For each value in indexes except for the first.
    for val = 2:length(indexes)
        % Is not an increment of 1.
        if (previous + 1 ~= indexes(val))
            count = count + 1;
        end
        previous = indexes(val);
    end

    return
end