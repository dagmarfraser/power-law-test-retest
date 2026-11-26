function J = diagnoseSpatialJumps_2026(options)
% diagnoseSpatialJumps_2026 - Largest sample-to-sample spatial step per trial, before and after the Pencil filter
%
% Follows up the open item in docs/AnalysisPipeline.md ("Still open", pen-lift
% section, 2026-07-16): Square showed a 649 pt (125 mm at 5.209 pt/mm) jump
% with no time gap. For every trial of the included participants it finds the
% largest step |d(x,y)| between consecutive samples on the analysis path
% (sorted on touch_index, edge clip 50) in two streams:
%   old: all touch types (runAnalysis_2026 before 2026-11-09)
%   new: pencilSamplesOnly (current runAnalysis_2026)
% and records where the step sits, the touch types either side of it (old
% stream) and the clock-residual step there (the detectPenLifts signal).
%
% USAGE: J = diagnoseSpatialJumps_2026();   % writes data/processed/spatialJumps_<ts>.csv
%
% d.s.fraser@bham.ac.uk

arguments
    options.excludeIDs double = [101 102 214]
    options.jumpMm double = 10      % a step this big at 240 Hz is > 2,400 mm/s: not drawing
end

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
f = dir(fullfile(root, 'data', 'raw', 'automatic', 'ID*', '*tracingSection-enhanced.csv'));
assert(~isempty(f), 'diagnoseSpatialJumps:noData', 'No -enhanced.csv files under %s', fullfile(root, 'data', 'raw', 'automatic'));
fs = 240; edgeClip = 50; ppm = ipadPointsPerMm();
shapeNames = {'phi=0.4', 'phi=0.8', 'Ellipse', 'Square', 'Cursive'};
rows = {};

for i = 1:numel(f)
    pid = str2double(regexp(f(i).folder, 'ID(\d+)$', 'tokens', 'once'));
    if ismember(pid, options.excludeIDs), continue; end
    T = readtable(fullfile(f(i).folder, f(i).name));
    M = readtable(fullfile(f(i).folder, strrep(f(i).name, ' tracingSection-enhanced.csv', ' tracingSection.csv')));
    for t = reshape(unique(T.response_index(T.response_index > 0 & T.response_index <= 50)), 1, [])
        m = M(M.trial == t, :);
        if isempty(m), continue; end
        X = T(T.response_index == t, :);
        [~, u] = unique(X.touch_index, 'stable');
        old = clip(sortrows(X(u, :), 'touch_index'));
        new = clip(pencilSamplesOnly(X));
        if isempty(new), continue; end      % runAnalysis_2026 skips these trials too
        r = struct('ParticipantID', pid, 'File', string(f(i).name), 'TrialNum', t, ...
            'Shape', string(shapeNames{m.tracingScene_object1_imageNumber}), ...
            'nNonPencil', sum(X.touch_type ~= 2));
        r = addStep(r, 'Old', old, true);
        r = addStep(r, 'New', new, false);
        rows{end+1} = r; %#ok<AGROW>
    end
end

J = struct2table([rows{:}]);
ts = datestr(now, 'yyyymmdd_HHMMSS');
writeTableVerified(J, fullfile(root, 'data', 'processed', ['spatialJumps_' ts '.csv']));

% Summary by shape: max jump and trials with a step > jumpMm, old vs new
fprintf('\nLargest sample-to-sample step (mm, %.3f pt/mm), trials with a step > %g mm\n', ppm, options.jumpMm);
fprintf('%-8s %6s | %8s %6s | %8s %6s %10s\n', 'Shape', 'trials', 'old max', 'n>thr', 'new max', 'n>thr', 'new w/o lift');
for s = shapeNames
    k = J.Shape == s{1};
    o = J.MaxStepMm_Old(k); n = J.MaxStepMm_New(k);
    noLift = sum(n > options.jumpMm & J.ResidStepS_New(k) <= 0.0125);
    fprintf('%-8s %6d | %8.1f %6d | %8.1f %6d %10d\n', s{1}, sum(k), max(o), sum(o > options.jumpMm), ...
        max(n), sum(n > options.jumpMm), noLift);
end

    function d = clip(d)
        if height(d) <= 2*edgeClip + 100, d = d([], :); else, d = d(edgeClip+1:end-edgeClip, :); end
    end

    function r = addStep(r, tag, d, withTypes)
        if isempty(d)
            [r.(['MaxStepMm_' tag]), r.(['StepPos_' tag]), r.(['ResidStepS_' tag])] = deal(NaN);
            if withTypes, r.TypesAtStep_Old = ""; end
            return
        end
        s = hypot(diff(d.x), diff(d.y)) / ppm;
        [mx, k] = max(s);
        dr = diff(d.time_seconds - d.touch_index / fs);   % same residual as detectPenLifts
        r.(['MaxStepMm_' tag]) = mx;
        r.(['StepPos_' tag]) = k / numel(s);              % 0 = start of clipped trial, 1 = end
        r.(['ResidStepS_' tag]) = dr(k);
        if withTypes, r.TypesAtStep_Old = sprintf('%d->%d', d.touch_type(k), d.touch_type(k+1)); end
    end
end
