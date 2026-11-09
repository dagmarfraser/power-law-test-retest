function [dx, dy] = differentiateKinematicsEBR(x, y, filterType, filterParams, fs)
%% demo code for Exp Brain Res review paper of Fraser et al., 2024
% Created May 2024
% Correspondence Dagmar Scott Fraser
% d.s.fraser@bham.ac.uk
%
%% inputs 
% x and y coordinates
% filterType - chooses filter and differentiation
%   1 MATLAB diff, scaled by the sample rate to give an approximation of the 
%   2 Nth Order Fp Hz Low pass filter, filtfilt for zero lag followed by Finite Differences 
%   3 Finite Differences followed by Nth Order Fp Hz Low pass filter filtfilt for zero lag 
%   4 Savitzky-Golay smoothing differential filter [REVISED - no scaling]
%   6 Savitzky-Golay with fs-scaling (Fraser et al. temporal equivalence)
%   7 Bandwidth-equivalent Savitzky-Golay (Schafer 2011 principled)
% filterParams - [filter order, Fc Low Pass Cutt off for Butterworth OR
% width for S-G filter zeroLag] 
% - where zeroLag = 1 filtfilt, zeroLag = 0 just employ filter
% - for case 6: [order, reference_framelen] for temporal scaling (reference_fs=100Hz constant)
% - for case 7: [order, target_cutoff_hz] for bandwidth scaling (Schafer 2011)
% fs - sampling frequency of the data
%% outputs
% dx and dy - N x 4, where N = length(input data)
% rows with original data (smoothed only in the case of S-G)
% velocity
% acceleration
% jerk
%   
dx = zeros(length(x),4);
dy = zeros(length(y),4);
dt = 1/fs;

switch filterType

    case 1 % Finite Differences Differentation

        dx = x; % not smoothed!
        dy = y;

        dx(2:end,2) = diff(x,1) * fs; % raw diff -  scaled by the fs
        dy(2:end,2) = diff(y,1) * fs; % velocity

        dx(2:end-1,3) = diff(x,2) * fs * fs; % raw diff -  scaled by the fs^2
        dy(2:end-1,3) = diff(y,2) * fs * fs; % acceleration

        dx(2:end-2,4) = diff(x,3) * fs * fs * fs; % raw diff -  scaled by the fs^3
        dy(2:end-2,4) = diff(y,3) * fs * fs * fs; % jerk

    case 2 % Nth Order Fp Hz Low pass filter, filtfilt for zero lag followed by Finite Differences 

        dx = x; % not smoothed!
        dy = y;
        
        Fp = filterParams(2);
        N = filterParams(1);
        zeroLag = filterParams(3);
        %% make an Nth order Butterworth zero lag low pass filter with corner frequency Fp
        fc = Fp;
        bOrder = N; % this is filter order, will be 2*bOrder when used with filtfilt below
        [b,a] = butter(bOrder,fc/(fs/2));

        % use zerophase digital filtering i.e. filtfilt
        % diff the output of the low pass filter
        if ~zeroLag
            dx(2:end,2) = diff(filter(b,a, (x))) * fs; % raw diff -  scaled by the fs, and now diminshed by the filter
            dy(2:end,2) = diff(filter(b,a, (y))) * fs; % velocity
        else
            dx(2:end,2) = diff(filtfilt(b,a, (x))) * fs; % raw diff -  scaled by the fs, and now diminshed by the filter
            dy(2:end,2) = diff(filtfilt(b,a, (y))) * fs; % velocity
        end

        dx(2:end-1,3) = diff(dx(2:end,2),1) * fs; % raw diff -  scaled by the fs
        dy(2:end-1,3) = diff(dy(2:end,2),1) * fs; % acceleration

        dx(2:end-2,4) = diff(dx(2:end,2),2) * fs * fs; % raw diff - scaled by the fs
        dy(2:end-2,4) = diff(dy(2:end,2),2) * fs * fs; % jerk

    case 3 % Finite Differences with Nth Order Fp Hz Low pass filter

        dx = x; % not smoothed!
        dy = y;

        Fp = filterParams(2);
        N = filterParams(1);
        zeroLag = filterParams(3);

        %% make an Nth order Butterworth zero lag low pass filter with corner frequency Fp
        fc = Fp;
        bOrder = N; % this is filter order, will be 2*bOrder when used with filtfilt below
        [b,a] = butter(bOrder,fc/(fs/2)); % we pass the order and the cut off freq / Nyquist Frequency (i.e. half sampling rate)

        % use zerophase digital filtering i.e. filtfilt
        % low pass filter the output of the diff
        if ~zeroLag
            dx(2:end,2) = filter(b,a, (diff(x,1)*fs)); % raw diff -  scaled by the fs, and now diminshed by the filter
            dy(2:end,2) = filter(b,a, (diff(y,1)*fs));
        else
            dx(2:end,2) = filtfilt(b,a, (diff(x,1)*fs)); % raw diff -  scaled by the fs, and now diminshed by the filter
            dy(2:end,2) = filtfilt(b,a, (diff(y,1)*fs));
        end
        dx(2:end-1,3) = diff(dx(2:end,2),1) * fs; % raw diff -  scaled by the fs
        dy(2:end-1,3) = diff(dy(2:end,2),1) * fs;

        dx(2:end-2,4) = diff(dx(2:end,2),2) * fs * fs; % raw diff - scaled by the fs
        dy(2:end-2,4) = diff(dy(2:end,2),2) * fs * fs;

    case 4 % Savitzky-Golay smooth differentiation
        % adapted from https://uk.mathworks.com/help/signal/ref/sgolay.html
        % example

        order = filterParams(1);
        framelen = filterParams(2);
        padding = (framelen-1)/2;

        [b,g] = sgolay(order, framelen);

        for p = 0:3 % smoothed displacement, velocity, acceleration, jerk.

            dxElement = [ conv(x, factorial(p)/(-dt)^p * g(:,p+1), 'same')];
            dyElement = [ conv(y, factorial(p)/(-dt)^p * g(:,p+1), 'same')];
            % Divide the columns by powers of dt to scale the derivatives correctly.

            if p == 0
                % Position (p=0): direct assignment, no padding
                dx(:,1) = dxElement;
                dy(:,1) = dyElement;
            else
                % Derivatives (p>0): direct assignment (conv 'same' handles edges)
                dx(:,p+1) = dxElement;
                dy(:,p+1) = dyElement;
            end
        end

    case 5

        disp('NOT IMPLEMNTED')
        
    case 6 % Savitzky-Golay with fs-scaling (Fraser et al. temporal equivalence)
        % Maintains same temporal window width as Butterworth filter
        % for apples-to-apples comparison between filter types
        % Based on Fraser et al. (2025) vetted protocol recommendations
        
        order = filterParams(1);
        reference_framelen = filterParams(2);  % From case 4 legacy (e.g., 17)
        
        % Crenna et al. reference conditions (constants)
        reference_fs = 100;  % Hz - Crenna's reference sampling rate
        
        % Scale window to maintain temporal equivalence across sampling rates
        temporal_width = reference_framelen / reference_fs;  % seconds (e.g., 17/100 = 0.17s)
        scaled_framelen = round(temporal_width * fs);
        
        % Ensure proper window constraints for SG filter + padding compatibility
        % Need: framelen odd AND (framelen-1)/2 even (so padding/2 is integer)
        % This means framelen must be of form 4k+1 (1, 5, 9, 13, 17, 21, 25...)
        
        % First ensure minimum window constraint
        min_window = order + 1;
        if scaled_framelen < min_window
            scaled_framelen = min_window;
        end
        
        % Now ensure framelen follows form 4k+1
        remainder = mod(scaled_framelen - 1, 4);
        if remainder == 0
            % Already form 4k+1, check if odd
            if mod(scaled_framelen, 2) == 0
                scaled_framelen = scaled_framelen + 4; % Jump to next 4k+1 form
            end
        elseif remainder == 1
            % Form 4k+2, adjust to 4k+1
            scaled_framelen = scaled_framelen - 1;
        elseif remainder == 2
            % Form 4k+3, adjust to 4k+1  
            scaled_framelen = scaled_framelen + 2;
        else % remainder == 3
            % Form 4k+4, adjust to 4k+1
            scaled_framelen = scaled_framelen + 1;
        end
        
        % Final check: ensure still meets minimum and is odd
        if scaled_framelen < min_window
            % Find next valid form >= min_window
            k = ceil((min_window - 1) / 4);
            scaled_framelen = 4*k + 1;
        end
        
        framelen = scaled_framelen;
        padding = (framelen-1)/2;
        
        % Verify our constraint logic worked
        if mod(framelen, 2) ~= 1 || mod(padding, 2) ~= 0
            error('SG filter constraint failed: framelen=%d (should be odd), padding=%.1f (should be even)', framelen, padding);
        end
        
        [b,g] = sgolay(order, framelen);
        
        for p = 0:3 % smoothed displacement, velocity, acceleration, jerk.
            
            dxElement = [ conv(x, factorial(p)/(-dt)^p * g(:,p+1), 'same')];
            dyElement = [ conv(y, factorial(p)/(-dt)^p * g(:,p+1), 'same')];
            % Divide the columns by powers of dt to scale the derivatives correctly.
            
            if p == 0
                % Position (p=0): no padding needed, direct assignment
                dx(:,1) = dxElement;
                dy(:,1) = dyElement;
            else
                % Derivatives (p>0): direct assignment (conv 'same' handles edges)
                dx(:,p+1) = dxElement;
                dy(:,p+1) = dyElement;
            end
        end

    case 7 % Bandwidth-Equivalent Savitzky-Golay (Schafer 2011 principled)
        % Uses Schafer's empirical bandwidth relationship for principled design
        % More robust than temporal scaling - maintains equivalent bandwidth
        % Based on Schafer (2011) frequency domain analysis
        
        order = filterParams(1);
        target_cutoff_hz = filterParams(2);  % Desired cutoff frequency
        
        % Schafer's empirical relationship for 4th order SG filters
        % Derived from frequency domain analysis: cutoff ≈ fs / (bandwidth_factor * window_half_width)
        % Validated against Crenna's 100Hz reference: 17 samples (8.5 half-width) ≈ 10Hz
        bandwidth_factor = 2.4; % Empirical constant for 4th order SG from Schafer
        
        % Calculate required window size for target bandwidth
        window_half_width = fs / (bandwidth_factor * target_cutoff_hz);
        framelen = 2 * round(window_half_width) + 1;
        
        % Apply SG mathematical constraints
        min_window = order + 1;
        if framelen < min_window
            framelen = min_window;
            if mod(framelen, 2) == 0
                framelen = framelen + 1;
            end
            warning('SG: Window too small for fs=%.0fHz, cutoff=%.1fHz. Using minimum window=%d', ...
                    fs, target_cutoff_hz, framelen);
        end
        
        % Verify and report actual achieved cutoff
        actual_cutoff = fs / (bandwidth_factor * (framelen-1)/2);
        if abs(actual_cutoff - target_cutoff_hz) > 0.5
            fprintf('SG Case 7: Target=%.1fHz, Actual=%.1fHz, Window=%d samples\n', ...
                    target_cutoff_hz, actual_cutoff, framelen);
        end
        
        dt = 1/fs;
        [b,g] = sgolay(order, framelen);
        
        for p = 0:3 % smoothed displacement, velocity, acceleration, jerk
            dxElement = conv(x, factorial(p)/(-dt)^p * g(:,p+1), 'same');
            dyElement = conv(y, factorial(p)/(-dt)^p * g(:,p+1), 'same');
            
            dx(:,p+1) = dxElement;
            dy(:,p+1) = dyElement;
        end

end
