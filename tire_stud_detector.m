%% TIRE STUD DETECTOR (v2: High-Accuracy)
%
% This script implements a high-accuracy, feature-detection-based
% pipeline to detect and count metal studs on tires.
%
% This upgraded pipeline uses two specialized functions:
% 1. imtophat: To isolate small, bright features and
%    suppress uneven background illumination.
% 2. imfindcircles: To directly detect circular objects
%    (the studs) using the Circular Hough Transform.
%
% This method is more accurate and robust than a simple
% segmentation/classification pipeline.
%
clear;
clc;
close all;

% Define the set of images to process
imageFiles = {'studded_tire.jpg', 'summer_tire.jpg'};

% Loop over each image
for i = 1:numel(imageFiles)
    
    % =====================================================================
    % STAGE 1: Image Ingestion and Standardization (Unchanged)
    % =====================================================================
    
    % ---------- 1) Read & resize ----------
    I = imread(imageFiles{i});
    % Operating on native resolution is most accurate

    % ---------- 2) Convert to grayscale ----------
    % Use im2gray as it handles both RGB and grayscale [1, 2]
    Igray_u8 = im2gray(I);
    Igray = im2double(Igray_u8); % Convert to  for processing [3]

    % =====================================================================
    % STAGE 2: Adaptive Segmentation of the Tire ROI (Unchanged)
    % =====================================================================
    
    % ---------- 3) Create tire mask ----------
    % This mask is our Region of Interest (ROI)
    % Use Otsu's method for high-contrast bimodal images [3, 4, 5]
    T_tire = graythresh(Igray);
    tireMask_raw = Igray < T_tire;
    
    % Fill holes (sipes, studs) in the mask [6]
    tireMask_filled = imfill(tireMask_raw, 'holes');
    
    % Remove small noise objects [7]
    tireMask = bwareaopen(tireMask_filled, 1000);

    % Calculate the total area for the density metric
    stats_tire = regionprops(tireMask, 'Area'); % [8]
    if isempty(stats_tire)
        warning('Tire mask segmentation failed. Skipping image: %s', imageFiles{i});
        continue;
    end
    tireArea = max([stats_tire.Area]);

    % =====================================================================
    % STAGE 3: Background Suppression (High-Accuracy Method)
    % =====================================================================
    
    % ---------- 4) Candidate Isolation (via Top-Hat) ----------
    %
    % UPGRADE: Use Morphological Top-Hat Filtering.
    % This is ideal for finding small, bright objects on a
    % dark, *uneven* background.
    
    % 1. Create a structuring element (se) that is
    %    *larger* than the studs we want to find.
    se_tophat = strel('disk', 12);

    % 2. Apply the top-hat filter.
    %    I_tophat = I_original - imopen(I_original)
    I_tophat = imtophat(Igray, se_tophat); %

    % 3. Mask the top-hat image to our ROI
    %    This gives a high-contrast image of *only*
    %    studs/features *inside* the tire.
    I_tophat_masked = I_tophat.* tireMask;
    
    % =====================================================================
    % STAGE 4: Feature Detection & Filtering (High-Accuracy Method)
    % =====================================================================

    % ---------- 5 & 6) Direct Detection & Filtering ----------
    %
    % UPGRADE: Replace bwconncomp/regionprops with imfindcircles.
    % This directly finds circular objects.

    % 1. Define detection parameters
    Rmin = 4;       % Min stud radius (pixels)
    Rmax = 8;       % Max stud radius (pixels)
    Sensitivity = 0.90; % Detection threshold
    EdgeThresh = 0.1;   % Edge gradient threshold

    % 2. Run the Circular Hough Transform detector
    [centers_all, radii_all, metrics_all] = imfindcircles(I_tophat_masked,...
        [Rmin Rmax],...
        'ObjectPolarity', 'bright',...
        'Sensitivity', Sensitivity,...
        'EdgeThreshold', EdgeThresh); %

    % 3. Filter detections by the tireMask
    %    We must ensure the center of each detected circle
    %    is truly inside our valid tireMask.
    studCount = 0;
    if isempty(centers_all)
        % No circles found
        centers_valid = []; % <-- CORRECTED SYNTAX
        radii_valid = [];   % <-- CORRECTED SYNTAX
    else
        % Convert (x,y) centers to linear indices for fast lookup
        sz = size(Igray);
        ctr_x = round(centers_all(:,1));
        ctr_y = round(centers_all(:,2));
        
        % Clamp indices to be within image bounds
        ctr_x(ctr_x < 1) = 1;
        ctr_y(ctr_y < 1) = 1;
        ctr_x(ctr_x > sz(2)) = sz(2);
        ctr_y(ctr_y > sz(1)) = sz(1);
        
        linear_indices = sub2ind(sz, ctr_y, ctr_x);
        
        % Find which of these linear indices are 'true' in the tireMask
        is_inside = tireMask(linear_indices);
        
        % Keep only the valid circles
        centers_valid = centers_all(is_inside, :);
        radii_valid = radii_all(is_inside);
        studCount = numel(radii_valid);
    end

    % =====================================================================
    % STAGE 5: Final Decision Logic and Visualization
    % =====================================================================
    
    % ---------- 7) Decision rule ----------
    % The density metric (studCount / tireArea) remains the
    % most robust, scale-invariant decision rule.
    if tireArea == 0
        studDensity = 0; % Avoid division by zero
    else
        studDensity = studCount / tireArea;
    end
    
    studDensityThreshold = 0.0001; % 1 stud per 10,000 tire pixels
    isStudded = (studDensity > studDensityThreshold);

    % ---------- 8) Visualization ----------
    figure('Position', [100 100 1600 600]);
    sgtitle(sprintf('High-Accuracy Analysis: %s', imageFiles{i}), 'Interpreter', 'none', 'FontSize', 14, 'FontWeight', 'bold');

    % Plot 1: Original Image
    subplot(1,3,1);
    imshow(I);
    title('Input Image');

    % Plot 2: Top-Hat Filtered Image
    % This plot is the key to this method.
    % It shows how the background is suppressed,
    % leaving only the bright stud features.
    subplot(1,3,2);
    imshow(I_tophat_masked);
    title('Top-Hat Filtered (Background Suppressed)');

    % Plot 3: Final Detection
    subplot(1,3,3);
    imshow(I);
    hold on;
    % Overlay the valid circles using viscircles
    viscircles(centers_valid, radii_valid, 'Color', 'g', 'LineWidth', 0.7); %
    hold off;

    % Create the final title based on the classification
    if isStudded
        titleStr = sprintf('STUDDED TIRE (Count: %d, Density: %.5f)',...
                           studCount, studDensity);
    else
        titleStr = sprintf('NON-STUDDED TIRE (Count: %d, Density: %.5f)',...
                           studCount, studDensity);
    end
    title(titleStr, 'FontSize', 11);

end % end image loop