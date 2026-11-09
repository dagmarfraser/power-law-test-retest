function R = compareICCTouchFix_2026(effectFile, trialFile)
% compareICCTouchFix_2026 - Between-visit ICC(A,1) before vs after the touch_type filter
%
% Patches the trials in effectFile (from diagnoseTouchTypeFilter_2026) into
% trialFile with their filtered values, aggregates trial -> session mean ->
% visit mean (as runICC_2026), and computes ICC(A,1) on the k=2 visit matrix.
% Interim check only; the definitive numbers come from the full re-run.
%
% d.s.fraser@bham.ac.uk

S = load(effectFile, 'D'); D = S.D;
T0 = readtable(trialFile, 'VariableNamingRule', 'preserve');
params = regexprep(D.Properties.VariableNames(endsWith(D.Properties.VariableNames, '_new')), '_new$', '');
params = setdiff(params, {'NumStrokes'}, 'stable');

% Match diagnostic rows to trial rows on (ParticipantID, SessionDatetime file, TrialNum, ShapeType)
T1 = T0;
key0 = compose('%d|%s|%d', T0.ParticipantID, fileStamp(T0.SessionDatetime), T0.TrialNum);
keyD = compose('%d|%s|%d', D.ParticipantID, fileStamp(D.File), D.TrialNum);
[ok, loc] = ismember(keyD, key0);
assert(all(ok), 'compareICC:unmatched', '%d of %d patched trials not found in %s', sum(~ok), numel(ok), trialFile);
assert(all(T0.ShapeType(loc) == D.ShapeType), 'compareICC:shapeMismatch', 'Shape mismatch on matched trials');
for k = 1:numel(params)
    oldMax = max(abs(T0.(params{k})(loc) - D.([params{k} '_old'])) ./ max(abs(D.([params{k} '_old'])), eps));
    if oldMax > 1e-6
        warning('compareICC:oldMismatch', '%s: unfiltered diagnostic differs from trial file (max rel %.2g)', params{k}, oldMax);
    end
    T1.(params{k})(loc) = D.([params{k} '_new']);
end

shapes = {'phi=0.4', 'phi=0.8', 'Ellipse', 'Square', 'Cursive'};
rows = {};
for s = 1:5
    for k = 1:numel(params)
        a = visitICC(T0, s, params{k}); b = visitICC(T1, s, params{k});
        rows{end+1} = table(string(shapes{s}), string(params{k}), a.icc, a.lb, b.icc, b.lb, b.icc - a.icc, ...
            string(kooLi(a.lb)), string(kooLi(b.lb)), 'VariableNames', ...
            {'Shape', 'Param', 'ICC_old', 'LB_old', 'ICC_new', 'LB_new', 'dICC', 'Class_old', 'Class_new'}); %#ok<AGROW>
    end
end
R = vertcat(rows{:});
end

function r = visitICC(T, s, p)
X = T(T.ShapeType == s, :);
G = groupsummary(X, {'ParticipantID', 'Visit', 'SessionInVisit'}, 'mean', p);
V = groupsummary(G, {'ParticipantID', 'Visit'}, 'mean', ['mean_' p]);
ids = unique(V.ParticipantID); M = nan(numel(ids), 2);
for i = 1:height(V), M(ids == V.ParticipantID(i), V.Visit(i)) = V.(['mean_mean_' p])(i); end
r = computeICC(M(all(~isnan(M), 2), :), 'absolute');
end

function c = kooLi(lb)
edges = [-Inf 0.5 0.75 0.9 Inf]; names = {'poor', 'moderate', 'good', 'excellent'};
c = names{discretize(lb, edges)};
end

function s = fileStamp(x)
% yyyyMMddHHmmss from a trial-file datetime or from an -enhanced.csv file name
if isdatetime(x)
    s = string(x, 'yyyyMMddHHmmss');
    return
end
tok = regexp(string(x), '(\d{4})-(\d{2})-(\d{2}) (\d{6})', 'tokens', 'once');
bad = cellfun(@isempty, tok);
assert(~any(bad), 'compareICC:stamp', 'Cannot parse a timestamp from %d file name(s), e.g. "%s"', sum(bad), x(find(bad, 1)));
s = string(cellfun(@(c) strjoin(c, ''), tok, 'UniformOutput', false));
end
