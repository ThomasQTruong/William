% MATLAB code for calculating the midline of the tube in motion
% Read video.
video = VideoReader("william.mp4");

% Specify the target frame number
targetFrame = 78;

% Read frame 78 directly
frameNumber = targetFrame;

global failed_left_most_column;
failed_left_most_column = 9999;

global failed_right_most_column;
failed_right_most_column = -9999;

global failed_count;
failed_count = 0;

if frameNumber <= video.NumFrames
    % Read frame 78 directly
    frame = read(video, frameNumber);
    
    % Process the frame (Grayscale, Enhancement, Midline detection)
    gray_image = Grayscale_Video(frame);
    enhanced_image = Enhancement(gray_image);
    [midline_x, midline_y, midline_points] = Midline(enhanced_image);
    frameWithMidline = MidlineFrame(midline_x, midline_y, enhanced_image);
    
    % % Display the image (optional)
    imshow(frameWithMidline.cdata)  % Show the processed frame

    % disp("Fails: " + failed_count);
    % disp("Min: " + failed_left_most_column + " | Max: " + failed_right_most_column);
end


function [gray_image] = Grayscale_Video(frame)
   % Read each frame
   % Convert to grayscale
   % Erode image to leave pixels of tube
   %frame = readFrame(video);
   grayFrame = rgb2gray(frame);
   SE = strel('disk',2,0);
   k1 = imerode(grayFrame,SE);
   gray_image = grayFrame-k1;
end

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

function [midline_x, midline_y, midline_points] = Midline(enhanced_image)
    % Initialize arrays to store midline positions
    midline_x = [];
    midline_y = [];    
    failed_rows = [];
    midline_points = [];

    % Size of the frame
    [row_indices, col_indices] = find(enhanced_image);

    threshold_factor = 3;
    threshold_value = 100;
    distances = [];

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

    for row = 1:size(enhanced_image, 1)  % Loop through rows
        % Find the non-zero (foreground) pixels in the current row
        rowCols = col_indices(row_indices == row);

        if ~isempty(rowCols)
            leftMost = min(rowCols);     % First non-zero pixel (left most)
            rightMost = max(rowCols);    % Last non-zero pixel (right most)
            current_distance = abs(rightMost - leftMost);

            % Apply distance check to the entire row before searching for the next wall
            if current_distance >= (avg_distance / (threshold_factor)) && ...
               current_distance <= (avg_distance * threshold_factor)

                % Iterate over columns in the range [leftMost, rightMost]
                next_wall = NaN;
                for col = leftMost + 1:rightMost
                    if abs(col - rightMost) > (avg_distance / threshold_factor)
                        if enhanced_image(row, col) > threshold_value
                            next_wall = col;
                            break;  % Exit loop when the next wall is found
                        end
                    end
                end

                if ~isnan(next_wall)
                    % Calculate midpoint between leftmost and next wall
                    midPoint = round((next_wall + rightMost) / 2);

                    % Store the midline (column and row)
                    midline_x = [midline_x, midPoint];
                    midline_y = [midline_y, row];
                else
                    % If no next wall is found, store the leftmost wall as a failed point
                    failed_rows = [failed_rows, row];
                end
            else
                failed_rows = [failed_rows, row];
            end
        end
    end

    % For each failed row.
    for failed_idx = failed_rows
        % disp("Failed Index: " + failed_idx);
        global failed_count;
        failed_count = failed_count + 1;

        % Grab every column within the failed left-most and right-most.
        colRows = col_indices(row_indices == failed_idx);

        global failed_left_most_column;
        global failed_right_most_column;
        min_col = min(colRows);
        max_col = max(colRows);
        if (min_col < failed_left_most_column)
            failed_left_most_column = min_col;
        end
        if (max_col > failed_right_most_column)
            failed_right_most_column = max_col;
        end

        % disp("colRows: " + colRows)
    end

    % For each column within the failed region.
    for column = failed_left_most_column:failed_right_most_column
        colRows = row_indices(col_indices == column);
        disp("colRows2: " + colRows);
        [topVal, bottomVal] = pixelJump(colRows);
        disp(topVal + ", " + bottomVal);
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

function [frameWithMidline] = MidlineFrame(midline_x, midline_y, enhanced_image)
   persistent ax;  % Use a persistent variable to store the axis
   if isempty(ax)
       % Only create the axis once if it doesn't exist
       fig = figure('Visible', 'on');  % Invisible figure to hold the axis
       ax = axes(fig);  % Create axes in the figure
   end
   imshow(enhanced_image, []);  % % Display the processed image
   hold on;
  
   % Plot the midline as a red line connecting the midline points
   if ~isempty(midline_x) && ~isempty(midline_y)  % Ensure midline points are valid
       plot(midline_x, midline_y, 'r-', 'LineWidth', 2, 'Parent', ax);  % Red line for midline
   end
   hold off;
  
   % Capture the frame as an image (this will be the image with the midline)
   frameWithMidline = getframe(ax);  % Get the current figure as a frame
end

function [topVal, bottomVal] = pixelJump(colRows)
    topVal = colRows(1);
    bottomVal = -1;
    
    % For each value in the column rows except first.
    for val = 2:length(colRows)
        % Is not an increment of 1.
        if (topVal + 1 ~= colRows(val))
            bottomVal = colRows(val);
            break;
        end
        topVal = colRows(val);
    end
    return
end