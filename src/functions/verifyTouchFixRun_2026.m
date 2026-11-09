function out = verifyTouchFixRun_2026(options)
% verifyTouchFixRun_2026 - Check a post-fix N=48 run against the pre-fix run and the diagnostic
%
% 1. Same trials (ID, visit, session, trial) in both runs.
% 2. Trials with no finger/palm samples must be unchanged (pencilSamplesOnly is a no-op there).
% 3. Contaminated trials must match diagnoseTouchTypeFilter_2026's "_new" values.
% 4. Between-visit ICC(A,1), pre vs post, from the two icc_results files.
% Writes data/processed/touchFixRunCheck_ICC_<ts>.csv and prints a summary.
%
% USAGE: out = verifyTouchFixRun_2026();   % newest run vs trial_level_results_20261103_151020
%
% d.s.fraser@bham.ac.uk

arguments
    options.preTrial string = "trial_level_results_20261103_151020.csv"
    options.preICC string = "icc_results_20261103_151023.csv"
    options.postTrial string = ""
    options.postICC string = ""
    options.effectFile string = ""
end

proc = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'data', 'processed');
rd = @(f) readtable(fullfile(proc, f), 'VariableNamingRule', 'preserve');
postTrial = pick(options.postTrial, proc, 'trial_level_results_2*.csv');
postICC = pick(options.postICC, proc, 'icc_results_2*.csv');
eff = pick(options.effectFile, proc, 'touchTypeFilterEffect_*.mat');
fprintf('Pre:  %s / %s\nPost: %s / %s\nDiagnostic: %s\n', options.preTrial, options.preICC, postTrial, postICC, eff);

A = rd(options.preTrial); B = rd(postTrial);
key = @(T) compose('%d|%d|%d|%d', T.ParticipantID, T.Visit, T.Session, T.TrialNum);
[ok, loc] = ismember(key(A), key(B));
out.nPre = height(A); out.nPost = height(B); out.nUnmatched = sum(~ok) + (height(B) - sum(ok));
out.nParticipants = numel(unique(B.ParticipantID));
fprintf('Trials pre %d, post %d, unmatched %d; participants %d\n', out.nPre, out.nPost, out.nUnmatched, out.nParticipants);
A = A(ok, :); B = B(loc(ok), :);

S = load(fullfile(proc, eff), 'D'); D = S.D;
stamp = @(x) string(x, 'yyyyMMddHHmmss');
tokD = regexp(D.File, '(\d{4})-(\d{2})-(\d{2}) (\d{6})', 'tokens', 'once');
keyD = compose('%d|%s|%d', D.ParticipantID, string(cellfun(@(c) strjoin(c, ''), tokD, 'UniformOutput', false)), D.TrialNum);
keyB = compose('%d|%s|%d', B.ParticipantID, stamp(B.SessionDatetime), B.TrialNum);
[okD, locD] = ismember(keyD, keyB);
assert(all(okD), 'verifyTouchFix:unmatched', '%d diagnostic trials not found in the post-fix run', sum(~okD));
isDirty = false(height(B), 1); isDirty(locD) = true;

params = {'Beta_SG6_IRLS', 'VGF_SG6_IRLS', 'MeanVelocity_SG', 'PeakVelocity_SG', 'MeanAcceleration_SG', ...
    'PeakAcceleration_SG', 'MeanJerk_SG', 'PeakJerk_SG', 'PeakJerk_BW'};
fprintf('\n%-22s %16s %18s\n', 'Param', 'clean max|rel d|', 'dirty vs diag max');
for p = params
    rc = relDiff(A.(p{1})(~isDirty), B.(p{1})(~isDirty));
    rdg = relDiff(D.([p{1} '_new']), B.(p{1})(locD));
    out.check.(p{1}) = [rc rdg];
    fprintf('%-22s %16.2g %18.2g\n', p{1}, rc, rdg);
end

I0 = rd(options.preICC); I1 = rd(postICC);
sel = @(I) I(strcmp(I.ICCType, 'absolute'), {'ShapeName', 'Parameter', 'ICC_BetweenVisit', 'ICC_BetweenVisit_LB'});
J = innerjoin(sel(I0), sel(I1), 'Keys', {'ShapeName', 'Parameter'});
J.Properties.VariableNames(3:6) = {'ICC_pre', 'LB_pre', 'ICC_post', 'LB_post'};
J.dICC = J.ICC_post - J.ICC_pre;
J.Class_pre = arrayfun(@kooLi, J.LB_pre); J.Class_post = arrayfun(@kooLi, J.LB_post);
out.icc = J;
f = fullfile(proc, ['touchFixRunCheck_ICC_' datestr(now, 'yyyymmdd_HHMMSS') '.csv']);
writetable(J, f); fprintf('\nSaved: %s\n', f); disp(J);
end

function r = relDiff(a, b)
r = max(abs(a - b) ./ max(abs(a), eps), [], 'omitnan');
if isempty(r), r = 0; end
nanFlip = sum(isnan(a) ~= isnan(b));
if nanFlip > 0, r = Inf; warning('verifyTouchFix:nan', '%d NaN-status changes', nanFlip); end
end

function c = kooLi(lb)
names = ["poor", "moderate", "good", "excellent"];
c = names(discretize(lb, [-Inf 0.5 0.75 0.9 Inf]));
end

function f = pick(explicit, folder, pattern)
if explicit ~= "", f = explicit; return; end
d = dir(fullfile(folder, pattern));
assert(~isempty(d), 'verifyTouchFix:notFound', 'No %s in %s', pattern, folder);
[~, i] = max([d.datenum]); f = d(i).name;
end
