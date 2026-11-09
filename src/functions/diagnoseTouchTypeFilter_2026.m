function D = diagnoseTouchTypeFilter_2026(options)
% diagnoseTouchTypeFilter_2026 - Effect of dropping finger/palm samples (touch_type ~= 2)
%
% The iPad writes finger/palm touches (touch_type 0) into the same
% -enhanced.csv stream as the Pencil (touch_type 2), sharing ONE touch_index
% counter. runAnalysis_2026 (lines 345-367) keeps them, so they are
% interleaved into the trajectory. Dropping them leaves gaps in the Pencil's
% touch_index, which would put false gaps into t = touch_index/fs, so the
% fixed path renumbers the Pencil samples 1..n after filtering.
%
% For every trial with any touch_type ~= 2 sample (included participants
% only), computes calculatePowerLaw both ways and reports the differences.
% Also checks that, in clean trials, Pencil touch_index already steps by 1
% (so renumbering is a no-op there).
%
% USAGE: D = diagnoseTouchTypeFilter_2026();   % writes data/processed/touchTypeFilterEffect_<ts>.mat
%
% d.s.fraser@bham.ac.uk

arguments
    options.excludeIDs double = [101 102 214]
    options.maxTrials double = Inf
end

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
f = dir(fullfile(root, 'data', 'raw', 'automatic', 'ID*', '*tracingSection-enhanced.csv'));
fs = 240; edgeClip = 50; ppm = ipadPointsPerMm();
keys = {'Beta_SG6_IRLS', 'VGF_SG6_IRLS', 'FitCorr_SG6_IRLS', 'NumStrokes'};
for flt = {'SG', 'BW'}
    for kin = {'Velocity', 'Acceleration', 'Jerk'}
        for st = {'Mean', 'Median', 'Peak'}
            keys{end+1} = [st{1} kin{1} '_' flt{1}]; %#ok<AGROW>
        end
    end
end
rows = {}; nClean = 0; nCleanGap = 0;

for i = 1:numel(f)
    pid = str2double(regexp(f(i).folder, 'ID(\d+)$', 'tokens', 'once'));
    if ismember(pid, options.excludeIDs), continue; end
    T = readtable(fullfile(f(i).folder, f(i).name));
    M = readtable(fullfile(f(i).folder, strrep(f(i).name, ' tracingSection-enhanced.csv', ' tracingSection.csv')));
    tr = unique(T.response_index); tr = tr(tr > 0 & tr <= 50)';
    for t = tr
        m = M(M.trial == t, :);
        if isempty(m), continue; end
        X = T(T.response_index == t, :);
        bad = X.touch_type ~= 2;
        if ~any(bad)
            P = sortrows(X, 'touch_index');
            nClean = nClean + 1;
            nCleanGap = nCleanGap + any(diff(unique(P.touch_index)) > 1);
            continue;
        end
        if numel(rows) >= options.maxTrials, continue; end
        old = runTrial(X, false); new = runTrial(X, true);
        r = struct('ParticipantID', pid, 'File', string(f(i).name), 'TrialNum', t, ...
            'ShapeType', m.tracingScene_object1_imageNumber, 'nNonPencil', sum(bad));
        for k = 1:numel(keys)
            r.([keys{k} '_old']) = getf(old, keys{k});
            r.([keys{k} '_new']) = getf(new, keys{k});
        end
        rows{end+1} = r; %#ok<AGROW>
    end
end

D = struct2table([rows{:}]);
fprintf('Clean trials: %d, of which %d have Pencil touch_index steps > 1 (should be 0)\n', nClean, nCleanGap);
fprintf('Contaminated trials: %d\n', height(D));
ts = datestr(now, 'yyyymmdd_HHMMSS');
save(fullfile(root, 'data', 'processed', ['touchTypeFilterEffect_' ts '.mat']), 'D', 'nClean', 'nCleanGap');

    function v = getf(s, k)
        if isstruct(s) && isfield(s, k), v = s.(k); else, v = NaN; end
    end

    function res = runTrial(X, doFilter)
        if doFilter, X = X(X.touch_type == 2, :); end
        [~, u] = unique(X.touch_index, 'stable');
        X = sortrows(X(u, :), 'touch_index');
        if height(X) <= 2*edgeClip + 100, res = []; return; end
        if doFilter, X.touch_index = (1:height(X))'; end   % close the gaps left by the dropped finger samples
        X = X(edgeClip+1:end-edgeClip, :);
        sid = detectPenLifts(X.touch_index, X.time_seconds, fs);
        try
            res = calculatePowerLaw(X.x/ppm, X.y/ppm, X.touch_index/fs, fs, sid);
        catch ME
            warning('diagnoseTouchType:fail', '%s trial %d (filter=%d): %s', X.Properties.Description, t, doFilter, ME.message);
            res = [];
        end
    end
end
