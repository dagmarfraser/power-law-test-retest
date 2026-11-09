function results = calculatePowerLaw(x, y, t, fs, strokeId)
% calculatePowerLaw - Calculate velocity-curvature power law parameters
%
% Based on Fraser et al. (2025) vetted protocol
%
% All SIX pipeline combinations are computed: {BW, SG6} x {Linear, LMLS, IRLS}.
% (analysis_2025 computed only 3 of these -- BW+Linear, SG6+LMLS, SG6+IRLS --
% having pre-specified SG6+IRLS as the confirmatory method. Analysis_2026
% computes all 6 so the champion method's advantage stays auditable against
% the full grid, not just the 2 comparators previously chosen.)
%
% INPUTS:
%   x, y   - trajectory coordinates (column vectors, mm)
%   t      - time vector (seconds), derived from the digitiser sample index;
%            uniform at 1/fs while the pen is down
%   fs     - sampling frequency in Hz (e.g. 240 for iPad Pro)
%   strokeId - OPTIONAL vector, same length as x: contiguous pen-down stroke
%            label (1,1,...,2,2,...). Samples either side of a pen lift must
%            carry different labels, so that nothing is differentiated across
%            the lift. Defaults to a single stroke (all ones), which
%            reproduces the pre-2026-07 behaviour exactly. Built by
%            detectPenLifts() in runAnalysis_2026.
%
% OUTPUTS:
%   results - struct with fields:
%       Power law (6 methods): for each Filter in {BW, SG6}, Method in {Linear, LMLS, IRLS}:
%         .Beta_{Filter}_{Method}, .VGF_{Filter}_{Method}, .FitCorr_{Filter}_{Method}
%         (FitCorr = Pearson r in log-log space; not R2 -- see computeFitCorrelation)
%       Kinematics (2 differentiation methods):
%         .MeanVelocity_BW, .MedianVelocity_BW, .PeakVelocity_BW, .MeanAcceleration_BW, etc.
%         .MeanVelocity_SG, .MedianVelocity_SG, .PeakVelocity_SG, .MeanAcceleration_SG, etc.
%         (Median added for the student-dataset export -- see exportStudentDataset_2026.m)
%       Metadata:
%         .NumPoints, .NumPoints_Regress_BW, .NumPoints_Regress_SG, .SamplingFrequency
%         .NumStrokes, .NumSamplesDropped

% Ensure column vectors
x = x(:); y = y(:); t = t(:);

if nargin < 5 || isempty(strokeId)
    strokeId = ones(numel(x), 1);   % single stroke = pre-2026-07 behaviour
end
strokeId = strokeId(:);
if numel(strokeId) ~= numel(x)
    error('calculatePowerLaw:strokeIdLength', '%s', ...
        'strokeId must be the same length as x and y');
end

% NOTE on the removed fs guard. This function used to check
%   fs_estimated = 1/mean(diff(t)) against fs, warning 'dropped samples?'.
% That check could never fire: t is synthesised upstream as touch_index/fs,
% so diff(t) is always exactly 1/fs and the estimate always exactly fs --
% including on Cursive trials where up to 0.79 s of pen-up time really had
% been dropped. The guard was real and correct but blinded by its input. It
% is replaced by the per-stroke uniformity assertion in the loop below,
% which tests the assumption the filters actually depend on.

% Initialize results
results = struct();
results.SamplingFrequency = fs;

% Regression type codes (regressDataEBR.m): 3=Linear(OLS,+intercept), 4=LMLS, 5=IRLS
regressionMethods = {'Linear', 3; 'LMLS', 4; 'IRLS', 5};
filterPaths = {'BW', 'Butterworth'; 'SG6', 'Savitzky-Golay'};

%% Filter parameters
bwFilterParams = [2, 10, 1];  % [order, cutoffHz, zeroLag]
sgFilterParams = [4, 17];     % [order, refFramelen] - scaled internally for fs

% SG boundary pad. Computed before differentiation because it also sets the
% minimum usable stroke length.
%
% Derivation: temporal_width = 17/100 = 0.17 s  ->  scaled_framelen = 41
% at 240 Hz after 4k+1 constraint  ->  sgPad = (41-1)/2 = 20 samples.
% Computed dynamically so it tracks any future change to sgFilterParams.
reference_fs_sg = 100;
temporal_width_sg = sgFilterParams(2) / reference_fs_sg;
scaled_sg = round(temporal_width_sg * fs);
if mod(scaled_sg, 2) == 0, scaled_sg = scaled_sg + 1; end  % ensure odd
% apply 4k+1 form (must match differentiateKinematicsEBR case 6 logic)
rem4 = mod(scaled_sg - 1, 4);
if     rem4 == 1, scaled_sg = scaled_sg - 1;
elseif rem4 == 2, scaled_sg = scaled_sg + 2;
elseif rem4 == 3, scaled_sg = scaled_sg + 1;
end
sgPad = (scaled_sg - 1) / 2;  % = 20 at 240 Hz with [4,17]
minStrokeLen = scaled_sg;     % shorter than the SG window = no usable interior

%% Differentiation, one pen-down stroke at a time
% Both filters assume uniform sampling. That holds WITHIN a stroke (the
% digitiser samples at fs while the pen is on the glass) but NOT across a
% pen lift, where an unknown number of samples is missing and the recorded
% samples either side are spatially far apart. Differentiating across a lift
% turns that hop into a step discontinuity: on Cursive, a 653 px (67 mm) hop
% treated as 1/240 s produced a 16,097 mm/s finite-difference spike, which
% the SG window then smeared into a ~1000 mm/s peak. Filtering each stroke
% independently means nothing is ever differentiated across a lift.
%
% Templated shapes are single continuous strokes, so strokes == 1 and this
% loop reduces to exactly the previous single-pass behaviour.
strokes = unique(strokeId, 'stable');
nStrokes = numel(strokes);
nSamples = numel(x);
dxBW = nan(nSamples, 4);  dyBW = nan(nSamples, 4);
dxSG = nan(nSamples, 4);  dySG = nan(nSamples, 4);
nDropped = 0;

for sIdx = 1:nStrokes
    seg = find(strokeId == strokes(sIdx));

    % Assert the uniformity the filters depend on (replaces the old,
    % unfireable fsMismatch check -- see note above).
    if numel(seg) >= 2
        dtStroke = diff(t(seg));
        if any(abs(dtStroke - 1/fs) > 1e-6)
            warning('calculatePowerLaw:nonUniformStroke', ...
                'Stroke %d is not uniformly sampled at %g Hz (max |dt-1/fs| = %.3g s)', ...
                sIdx, fs, max(abs(dtStroke - 1/fs)));
        end
    end

    if numel(seg) < minStrokeLen
        % Too short to filter. Left as NaN and counted, not fabricated.
        nDropped = nDropped + numel(seg);
        continue;
    end

    [bx, by] = differentiateKinematicsEBR(x(seg), y(seg), 2, bwFilterParams, fs);
    [sx, sy] = differentiateKinematicsEBR(x(seg), y(seg), 6, sgFilterParams, fs);
    dxBW(seg, :) = bx;  dyBW(seg, :) = by;
    dxSG(seg, :) = sx;  dySG(seg, :) = sy;

    % NaN-out this stroke's own boundary samples.
    % differentiateKinematicsEBR uses conv(...,'same') which zero-pads beyond
    % the signal boundary. The derivative of signal->zero is a large artefact
    % that does NOT appear as NaN, so validSG would otherwise treat it as real
    % data. Butterworth is masked over the same span: filtfilt has its own edge
    % transient, and in the single-stroke case this reproduces exactly what the
    % old code did anyway (clipRange began after SG's mask, so BW's first and
    % last sgPad samples were already discarded).
    head = seg(1:min(sgPad, numel(seg)));
    tail = seg(max(1, numel(seg)-sgPad+1):end);
    edges = [head; tail];
    dxBW(edges, :) = NaN;  dyBW(edges, :) = NaN;
    dxSG(edges, :) = NaN;  dySG(edges, :) = NaN;
end

results.NumStrokes = nStrokes;
results.NumSamplesDropped = nDropped;
if nDropped > 0
    warning('calculatePowerLaw:shortStrokeDropped', ...
        '%d sample(s) in stroke(s) shorter than the SG window (%d) were excluded', ...
        nDropped, minStrokeLen);
end

%% Find common valid range (principled: where both methods have valid data)
% Check for NaN in velocity columns (column 2) from both methods
validBW = ~isnan(dxBW(:,2)) & ~isnan(dyBW(:,2));
validSG = ~isnan(dxSG(:,2)) & ~isnan(dySG(:,2));
validBoth = validBW & validSG;

% Find contiguous valid range
validIdx = find(validBoth);
if isempty(validIdx)
    warning('No valid data points after differentiation');
    results = setNaNResults(results, regressionMethods, filterPaths);
    return;
end
clipRange = validIdx(1):validIdx(end);

%% Extract kinematics from common range - Butterworth
velX_BW = dxBW(clipRange, 2);  velY_BW = dyBW(clipRange, 2);
accX_BW = dxBW(clipRange, 3);  accY_BW = dyBW(clipRange, 3);
jerkX_BW = dxBW(clipRange, 4); jerkY_BW = dyBW(clipRange, 4);

velocity_BW = sqrt(velX_BW.^2 + velY_BW.^2);
acceleration_BW = sqrt(accX_BW.^2 + accY_BW.^2);
jerk_BW = sqrt(jerkX_BW.^2 + jerkY_BW.^2);
curvature_BW = curvatureKinematicEBR(velX_BW, velY_BW, accX_BW, accY_BW);

% BW kinematic stats
results.MeanVelocity_BW = mean(velocity_BW, 'omitnan');
results.MedianVelocity_BW = median(velocity_BW, 'omitnan');
results.PeakVelocity_BW = max(velocity_BW);
results.MeanAcceleration_BW = mean(acceleration_BW, 'omitnan');
results.MedianAcceleration_BW = median(acceleration_BW, 'omitnan');
results.PeakAcceleration_BW = max(acceleration_BW);
results.MeanJerk_BW = mean(jerk_BW, 'omitnan');
results.MedianJerk_BW = median(jerk_BW, 'omitnan');
results.StdJerk_BW = std(jerk_BW, 'omitnan');
results.PeakJerk_BW = max(jerk_BW);

%% Extract kinematics from common range - Savitzky-Golay
velX_SG = dxSG(clipRange, 2);  velY_SG = dySG(clipRange, 2);
accX_SG = dxSG(clipRange, 3);  accY_SG = dySG(clipRange, 3);
jerkX_SG = dxSG(clipRange, 4); jerkY_SG = dySG(clipRange, 4);

velocity_SG = sqrt(velX_SG.^2 + velY_SG.^2);
acceleration_SG = sqrt(accX_SG.^2 + accY_SG.^2);
jerk_SG = sqrt(jerkX_SG.^2 + jerkY_SG.^2);
curvature_SG = curvatureKinematicEBR(velX_SG, velY_SG, accX_SG, accY_SG);

% SG kinematic stats
results.MeanVelocity_SG = mean(velocity_SG, 'omitnan');
results.MedianVelocity_SG = median(velocity_SG, 'omitnan');
results.PeakVelocity_SG = max(velocity_SG);
results.MeanAcceleration_SG = mean(acceleration_SG, 'omitnan');
results.MedianAcceleration_SG = median(acceleration_SG, 'omitnan');
results.PeakAcceleration_SG = max(acceleration_SG);
results.MeanJerk_SG = mean(jerk_SG, 'omitnan');
results.MedianJerk_SG = median(jerk_SG, 'omitnan');
results.StdJerk_SG = std(jerk_SG, 'omitnan');
results.PeakJerk_SG = max(jerk_SG);

% Valid samples where BOTH filters have data. With multiple strokes,
% clipRange spans the masked lift boundaries, so its length would overcount;
% counting validBoth is the honest number. For a single stroke the two are
% identical (every sample inside clipRange is valid by construction).
results.NumPoints = sum(validBoth);

%% Power law regressions: all 6 {filter x method} combinations
% LMseeds are the nonlinear solver initial conditions [VGF, beta].
% Linear (OLS) ignores these; LMLS and IRLS use them.
LMseeds = [1, 1/3];

velocityByFilter  = struct('BW', velocity_BW, 'SG6', velocity_SG);
curvatureByFilter = struct('BW', curvature_BW, 'SG6', curvature_SG);

for fIdx = 1:size(filterPaths, 1)
    filterCode = filterPaths{fIdx, 1};  % 'BW' or 'SG6'

    [v_filt, k_filt, nPts] = filterForRegression(velocityByFilter.(filterCode), curvatureByFilter.(filterCode));
    results.(sprintf('NumPoints_Regress_%s', filterCode)) = nPts;

    for mIdx = 1:size(regressionMethods, 1)
        methodName = regressionMethods{mIdx, 1};   % 'Linear', 'LMLS', 'IRLS'
        regressType = regressionMethods{mIdx, 2};  % 3, 4, 5

        betaField    = sprintf('Beta_%s_%s', filterCode, methodName);
        vgfField     = sprintf('VGF_%s_%s', filterCode, methodName);
        fitCorrField = sprintf('FitCorr_%s_%s', filterCode, methodName);

        if nPts >= 50
            [betaVal, vgfVal, ~] = regressDataEBR(v_filt, k_filt, regressType, LMseeds, 0, 0);
            results.(betaField) = betaVal;
            results.(vgfField) = vgfVal;
            results.(fitCorrField) = computeFitCorrelation(v_filt, k_filt, betaVal, vgfVal);
        else
            results.(betaField) = NaN;
            results.(vgfField) = NaN;
            results.(fitCorrField) = NaN;
        end
    end
end

end

%% Helper functions
function [v, k, n] = filterForRegression(velocity, curvature)
    valid = curvature > 1e-10 & ~isnan(curvature) & velocity > 1e-10 & ~isnan(velocity);
    v = velocity(valid);
    k = curvature(valid);
    n = sum(valid);
end

function r = computeFitCorrelation(velocity, curvature, beta, vgf)
    % Compute correlation between observed and predicted velocity
    % in LOG-LOG space (where the regression was performed)
    %
    % Power law: v = VGF * κ^(-β)
    % Log form:  log(v) = log(VGF) - β*log(κ)
    %
    % r close to 1 = good fit
    % r close to 0 = poor fit
    
    if isnan(beta) || isnan(vgf)
        r = NaN;
        return;
    end
    
    % Work in log space (where linear regression was performed)
    logV_observed = log(velocity);
    logK = log(curvature);
    
    % Predicted log(velocity) from power law
    logV_predicted = log(vgf) - beta * logK;
    
    % Pearson correlation in log-log space
    r = corr(logV_observed, logV_predicted);
end
% NOTE: regressDataEBR returns VGF in linear space (not log-transformed).
% Therefore log(vgf) is correct for the log-log prediction above.

function results = setNaNResults(results, regressionMethods, filterPaths)
    % Set all output fields to NaN when no valid data
    results.NumPoints = 0;
    results.NumPoints_Regress_BW = 0;
    results.NumPoints_Regress_SG6 = 0;
    
    % Kinematics
    results.MeanVelocity_BW = NaN; results.MedianVelocity_BW = NaN; results.PeakVelocity_BW = NaN;
    results.MeanAcceleration_BW = NaN; results.MedianAcceleration_BW = NaN; results.PeakAcceleration_BW = NaN;
    results.MeanJerk_BW = NaN; results.MedianJerk_BW = NaN; results.StdJerk_BW = NaN; results.PeakJerk_BW = NaN;
    results.MeanVelocity_SG = NaN; results.MedianVelocity_SG = NaN; results.PeakVelocity_SG = NaN;
    results.MeanAcceleration_SG = NaN; results.MedianAcceleration_SG = NaN; results.PeakAcceleration_SG = NaN;
    results.MeanJerk_SG = NaN; results.MedianJerk_SG = NaN; results.StdJerk_SG = NaN; results.PeakJerk_SG = NaN;
    
    % Power law -- all 6 combinations
    for fIdx = 1:size(filterPaths, 1)
        filterCode = filterPaths{fIdx, 1};
        for mIdx = 1:size(regressionMethods, 1)
            methodName = regressionMethods{mIdx, 1};
            results.(sprintf('Beta_%s_%s', filterCode, methodName)) = NaN;
            results.(sprintf('VGF_%s_%s', filterCode, methodName)) = NaN;
            results.(sprintf('FitCorr_%s_%s', filterCode, methodName)) = NaN;
        end
    end
end
