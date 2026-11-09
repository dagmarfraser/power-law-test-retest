function out = compareCohortsN45N48_2026(options)
% compareCohortsN45N48_2026 - Original cohort vs original + replacements: results and sensitivity
%
% Implements the plan in docs/SensitivityPlan_N48.md. Written 2026-11-01, BEFORE
% the replacement data existed. Nothing here hard-codes N.
%
% DEFINITIONS
%   original     IDs in the frozen baseline (data/processed/baseline_N45/trial_level_results_*.csv)
%   replacement  IDs in the new run but not in the baseline (expected 400-499)
%   "original-only" results are RECOMPUTED from the new run restricted to the original IDs,
%   so original vs all is like-for-like. Whether that reproduces the frozen baseline is
%   checked separately (drift columns, warning banner).
%
% ANALYSES (confirmatory parameter by default, ICC(A,1), visit means, per shape)
%   main   ICC + 95% CI + Koo & Li class (from CI lower bound) + Zou required N, both cohorts
%   ref    exact exchangeability reference (delete-d jackknife, Shao & Wu 1989): change in ICC, its CI
%          lower bound, mean beta and V2-V1 shift when nNew originals are added to the remaining
%          originals, over ALL nchoosek combinations (see also leaveKOutReference_2026). The observed
%          change is located in each distribution: Flag_* is ok (inside 2.5-97.5%), outside95, or
%          SUSPECT (outside the min-max of every possible draw; warns). RefP is the ICC two-sided p.
%   tests  exact permutation tests (all nchoosek(n,nNew) choices) that the replacements are a
%          random draw from the pooled cohort: mean beta, V2-V1 shift, |V2-V1|; Holm-adjusted
%   newP   each replacement participant as a z-score against the originals
%   qual   per-participant trial counts, NaN %, sampling frequency, session dates
%
% FAILS LOUDLY (error) if: no new run, originals missing from the new run, no/too many
% replacements, replacement IDs outside newIDRange, a participant x visit x shape cell is
% missing. WARNS (visibly, also in the CSV) if the originals do not reproduce the frozen
% baseline, replacement sessions pre-date the N=45 interim look (options.lockDate), replacement sampling
% frequency is outside the originals' range, or Zou N could not be computed.
%
% USAGE:  out = compareCohortsN45N48_2026();   % newest trial_level_results_2*.csv vs baseline_N45
%         out = compareCohortsN45N48_2026('zouDir', 'data/processed/zou');   % PC: Zou N via zouCohort_M5.sh on the Mac
%
% OUTPUT: struct with tables main, ref, tests, newP, qual and files; CSVs written to outDir.

arguments
    options.trialFile string = ""
    options.baselineFile string = ""
    options.baselineIccFile string = ""
    options.param (1,1) string = "Beta_SG6_IRLS"
    options.newIDRange (1,2) double = [400 499]
    options.maxNew (1,1) double = 3
    options.p0 (1,1) double = 0.75
    options.margin (1,1) double {mustBePositive} = 0.03   % TOST equivalence margin, beta units, all shapes (fixed 2026-11-01)
    options.driftTol (1,1) double = 1e-9
    options.strictDrift (1,1) logical = false
    options.runZou (1,1) logical = true
    % Folder for the Mac route (R is not used on the PC): non-empty = write zouInput_N45/N48.csv
    % there and read zouOutput_N45/N48.csv written by zouCohort_M5.sh, checked against the current ICCs.
    options.zouDir string = ""
    options.outDir string = ""
    % When the N=45 interim look was taken (the 2026-08-04 15:05:37 run, frozen 2026-10-12):
    % replacements must have been collected after it. Since 2026-11-09 the baseline file is
    % rebuilt from the current run (rebuildBaselineN45_2026), so its file name no longer
    % carries this date. NaT = take it from the baseline file name (pre-2026-11-09 behaviour).
    options.lockDate (1,1) datetime = datetime(2026, 8, 4, 15, 5, 37)
end
param = char(options.param);
rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
procDir = fullfile(rootDir, 'data', 'processed');
baseDir = fullfile(procDir, 'baseline_N45');
if options.outDir == "", options.outDir = procDir; end

%% Inputs and cohort definition
trialFile = pickFile(options.trialFile, procDir, 'trial_level_results_2*.csv', false);
baseFile  = pickFile(options.baselineFile, baseDir, 'trial_level_results_2*.csv', true);
baseIcc   = pickFile(options.baselineIccFile, baseDir, 'icc_results_2*.csv', true);
[~, tn] = fileparts(trialFile); [~, bn] = fileparts(baseFile);
assert(~strcmp(tn, bn), 'compareCohorts:noNewRun', ...
    'Newest trial-level file is the frozen baseline run (%s). Run runAnalysis_2026 on the new data first.', tn);
T = readtable(trialFile, 'VariableNamingRule', 'preserve');
B = readtable(baseFile,  'VariableNamingRule', 'preserve');
idsOrig = unique(B.ParticipantID); idsAll = unique(T.ParticipantID);
lost = setdiff(idsOrig, idsAll); newIDs = setdiff(idsAll, idsOrig); nNew = numel(newIDs);
assert(isempty(lost), 'compareCohorts:lostBaseline', 'Baseline participants missing from the new run: %s', mat2str(lost'));
assert(nNew >= 1, 'compareCohorts:noNewParticipants', 'The new run (%s) has no participants beyond the baseline.', tn);
assert(nNew <= options.maxNew, 'compareCohorts:tooManyNew', ...
    '%d new participants but the stopping rule allows at most %d (docs/PublicationTodo.md).', nNew, options.maxNew);
assert(all(newIDs >= options.newIDRange(1) & newIDs <= options.newIDRange(2)), 'compareCohorts:unexpectedID', ...
    'New IDs %s fall outside the expected range %s.', mat2str(newIDs'), mat2str(options.newIDRange));

[ids, X, sT] = buildVisitMatrices_2026(T, param);      % fails loudly on any missing cell
[idsB, XB, sTB] = buildVisitMatrices_2026(B, param);
assert(isequal(sT, sTB, 1:5), 'compareCohorts:shapes', 'Expected ShapeType 1:5 in both runs.');
isNew = ismember(ids, newIDs); isOld = ~isNew; n48 = numel(ids); n45 = sum(isOld);
assert(isequal(ids(isOld), idsB), 'compareCohorts:idMismatch', 'Original IDs in the new run differ from the baseline.');
shapeNames = ["phi=0.4", "phi=0.8", "Ellipse", "Square", "Cursive"];
statNames = ["MeanBeta", "Shift_V2minusV1", "AbsDiff_V2minusV1"];
statRef = ["ICC", "LB", "MeanBeta", "Shift"];
Ifz = readtable(baseIcc, 'VariableNamingRule', 'preserve');
Cref = nchoosek(1:n45, nNew); Cperm = nchoosek(1:n48, nNew);

%% Per shape
rows = struct([]); tests = table(); newP = table(); tostT = table(); drift = zeros(1, 5);
for s = 1:5
    x48 = X{s}; x45 = x48(isOld, :);
    i48 = computeICC(x48, 'absolute'); i45 = computeICC(x45, 'absolute');
    assert(abs(iccA1(x48) - i48.icc) < 1e-12 && abs(iccA1(x45) - i45.icc) < 1e-12, 'compareCohorts:fastIcc', ...
        'Point-estimate ICC disagrees with computeICC (shape %d).', s);
    drift(s) = max(abs(XB{s}(:) - x45(:)));
    fr = Ifz(Ifz.ShapeType == s & strcmp(string(Ifz.Parameter), param) & strcmp(string(Ifz.ICCType), 'absolute'), :);
    assert(height(fr) == 1, 'compareCohorts:noFrozenRow', 'Need one frozen icc_results row for shape %d / %s, got %d.', s, param, height(fr));

    % Exchangeability reference: change from adding nNew originals to the other originals, every choice
    dRefM = zeros(size(Cref, 1), 4);
    for r = 1:size(Cref, 1)
        keep = true(n45, 1); keep(Cref(r, :)) = false; xr = x45(keep, :); ir = computeICC(xr, 'absolute');
        dRefM(r, :) = [i45.icc - ir.icc, i45.lb - ir.lb, mean(x45(:)) - mean(xr(:)), ...
            mean(x45(:, 2) - x45(:, 1)) - mean(xr(:, 2) - xr(:, 1))];
    end
    dRef = dRefM(:, 1);
    dObsM = [i48.icc - i45.icc, i48.lb - i45.lb, mean(x48(:)) - mean(x45(:)), ...
        mean(x48(:, 2) - x48(:, 1)) - mean(x45(:, 2) - x45(:, 1))];
    dObs = dObsM(1); q = prctile(dRef, [2.5 97.5]);

    % Permutation tests that the replacements are a random draw from the pooled cohort
    v = {mean(x48, 2), x48(:, 2) - x48(:, 1), abs(x48(:, 2) - x48(:, 1))};
    for k = 1:3
        tot = sum(v{k}); sm = sum(v{k}(Cperm), 2);
        dist = sm / nNew - (tot - sm) / (n48 - nNew);
        obs = mean(v{k}(isNew)) - mean(v{k}(isOld));
        tests = [tests; table(s, shapeNames(s), statNames(k), mean(v{k}(isNew)), mean(v{k}(isOld)), obs, ...
            mean(abs(dist) >= abs(obs) - 1e-12), 'VariableNames', {'ShapeType','ShapeName','Statistic', ...
            'MeanReplacement','MeanOriginal','Difference','P_exact'})]; %#ok<AGROW>
    end
    % TOST equivalence within +/-margin (90% CI inside): within-person V2-V1 shift, originals and all; and the
    % replacement-vs-original mean beta (Welch). The last needs >= 2 replacements and cannot pass with n=3 vs
    % a between-person SD near 0.1: reported so that limit is visible, not as a test of cohort equivalence.
    tc = {"Shift_original", computeTOST(x45(:, 2) - x45(:, 1), options.margin); ...
          "Shift_all", computeTOST(x48(:, 2) - x48(:, 1), options.margin); ...
          "MeanBeta_replacement_minus_original", computeTOST(mean(x48(isNew, :), 2), options.margin, 'ref', mean(x45, 2))};
    for c = 1:size(tc, 1)
        r = tc{c, 2};
        tostT = [tostT; table(s, shapeNames(s), tc{c, 1}, r.n, r.est, r.lo90, r.hi90, r.margin, r.p, r.equivalent, r.note, ...
            'VariableNames', {'ShapeType','ShapeName','Contrast','n','Estimate','CI90_Lo','CI90_Hi','Margin','P_TOST','Equivalent','Note'})]; %#ok<AGROW>
    end
    % Each replacement against the originals (descriptive; |z| > 3 is flagged)
    for j = find(isNew)'
        zM = (v{1}(j) - mean(v{1}(isOld))) / std(v{1}(isOld)); zD = (v{2}(j) - mean(v{2}(isOld))) / std(v{2}(isOld));
        newP = [newP; table(ids(j), s, shapeNames(s), v{1}(j), zM, v{2}(j), zD, abs(zM) > 3 || abs(zD) > 3, ...
            'VariableNames', {'ParticipantID','ShapeType','ShapeName','MeanBeta','z_MeanBeta','Shift','z_Shift','Flag_absZ_gt3'})]; %#ok<AGROW>
    end

    rows(s).ShapeType = s; rows(s).ShapeName = shapeNames(s);
    rows(s).nOriginal = n45; rows(s).ICC_orig = i45.icc; rows(s).LB_orig = i45.lb; rows(s).UB_orig = i45.ub;
    rows(s).nAll = n48; rows(s).ICC_all = i48.icc; rows(s).LB_all = i48.lb; rows(s).UB_all = i48.ub;
    rows(s).DeltaICC = dObs; rows(s).RefLo = q(1); rows(s).RefHi = q(2); rows(s).RefP = mean(abs(dRef) >= abs(dObs) - 1e-12);
    for j = 1:4
        v = dRefM(:, j); q2 = prctile(v, [2.5 97.5]);
        rows(s).(char("Obs_" + statRef(j))) = dObsM(j);
        rows(s).(char("Lo95_" + statRef(j))) = q2(1); rows(s).(char("Hi95_" + statRef(j))) = q2(2);
        rows(s).(char("Min_" + statRef(j))) = min(v); rows(s).(char("Max_" + statRef(j))) = max(v);
        rows(s).(char("Flag_" + statRef(j))) = rangeFlag(dObsM(j), v, q2);
    end
    rows(s).Class_orig = kooLi(i45.lb); rows(s).Class_all = kooLi(i48.lb);
    rows(s).ClassChanged = ~strcmp(rows(s).Class_orig, rows(s).Class_all);
    rows(s).LBabovep0_orig = i45.lb >= options.p0; rows(s).LBabovep0_all = i48.lb >= options.p0;
    rows(s).DriftVsFrozen = drift(s); rows(s).FrozenICCdiff = abs(computeICC(XB{s}, 'absolute').icc - fr.ICC_BetweenVisit);
end
main = struct2table(rows);
tests.P_Holm = holmAdjust(tests.P_exact);
for j = 1:4
    bad = main.ShapeName(main.(char("Flag_" + statRef(j))) == "SUSPECT");
    if ~isempty(bad)
        warning('compareCohorts:outsideLeaveOut', ['SUSPECT: observed change in %s (%d replacement(s)) lies outside EVERY possible draw of ' ...
            '%d originals, for shape(s): %s. Check the new data (protocol, device, labelling) before interpreting.'], ...
            statRef(j), nNew, nNew, strjoin(bad, ', '));
    end
end

%% Zou required N (R via powerAnalysisICC_R; failure is disclosed, never filled in)
[main.ZouN_orig, st1] = zouN(shapeNames, main.ICC_orig, n45, options.runZou, options.zouDir, "N45");
[main.ZouN_all,  st2] = zouN(shapeNames, main.ICC_all,  n48, options.runZou, options.zouDir, "N48");
main.ZouCleared_orig = main.ZouN_orig <= n45; main.ZouCleared_all = main.ZouN_all <= n48;
main.ZouStatus = repmat(st1 + " | " + st2, height(main), 1);

%% Drift and data-quality checks
if any(drift > options.driftTol) || any(main.FrozenICCdiff > 1e-3)
    msg = sprintf(['The originals in the new run do NOT reproduce the frozen baseline (max visit-mean diff %.3g, ' ...
        'max ICC diff vs frozen icc_results %.3g). Code or data changed since the baseline; original-vs-all is still like-for-like, ' ...
        'but any quoted N=%d figure will differ from the frozen one.'], max(drift), max(main.FrozenICCdiff), n45);
    assert(~options.strictDrift, 'compareCohorts:driftFromBaseline', '%s', msg);
    warning('compareCohorts:driftFromBaseline', '%s', msg);
end
[g, gid] = findgroups(T.ParticipantID);
qual = table(gid, splitapply(@numel, T.Session, g), splitapply(@(s) numel(unique(s)), T.Session, g), ...
    splitapply(@(x) 100*mean(isnan(x)), T.(param), g), splitapply(@(f) mean(f, 'omitnan'), T.SamplingFrequency, g), ...
    'VariableNames', {'ParticipantID','nTrials','nSessions','pctNaN','meanFs'});
qual.Cohort = repmat("Original", height(qual), 1); qual.Cohort(ismember(qual.ParticipantID, newIDs)) = "Replacement";
when = sessionTimes(T); lock = options.lockDate;
if isnat(lock), lock = datetime(regexp(bn, '\d{8}_\d{6}', 'match', 'once'), 'InputFormat', 'yyyyMMdd_HHmmss'); end
qual.FirstSession = splitapply(@min, when, g); qual.LastSession = splitapply(@max, when, g);
rep = qual.Cohort == "Replacement"; org = ~rep;
if any(qual.FirstSession(rep) < lock)
    warning('compareCohorts:replacementBeforeLock', 'Replacement sessions pre-date the N=%d interim look (%s): they were NOT gathered after it.', n45, string(lock));
end
if any(qual.meanFs(rep) < min(qual.meanFs(org)) - 1 | qual.meanFs(rep) > max(qual.meanFs(org)) + 1)
    warning('compareCohorts:samplingFrequency', 'Replacement sampling frequency is outside the originals'' range (+/-1 Hz): protocol or device changed?');
end
if any(qual.nSessions(rep) ~= mode(qual.nSessions(org)))
    warning('compareCohorts:sessionCount', 'A replacement does not have the usual %d sessions.', mode(qual.nSessions(org)));
end
if any(newP.Flag_absZ_gt3)
    warning('compareCohorts:outlier', 'Replacement(s) with |z| > 3 vs originals: IDs %s (see newP table).', mat2str(unique(newP.ParticipantID(newP.Flag_absZ_gt3))'));
end

%% Report and save
fprintf('\n=== %s ICC(A,1): original N=%d vs all N=%d (replacements: %s) ===\n', param, n45, n48, mat2str(newIDs'));
disp(main(:, {'ShapeName','ICC_orig','LB_orig','Class_orig','ZouN_orig','ICC_all','LB_all','Class_all','ZouN_all','DeltaICC','RefLo','RefHi','RefP','ClassChanged'}));
fprintf('Observed change vs every possible draw of %d originals (Flag: ok / outside95 / SUSPECT):\n', nNew);
disp(main(:, {'ShapeName','Obs_MeanBeta','Lo95_MeanBeta','Hi95_MeanBeta','Flag_MeanBeta','Obs_Shift','Flag_Shift','Obs_ICC','Flag_ICC','Obs_LB','Flag_LB'}));
fprintf('TOST equivalence, margin +/-%g (Equivalent = 90%% CI inside the margin):\n', options.margin);
disp(tostT(:, {'ShapeName','Contrast','Estimate','CI90_Lo','CI90_Hi','P_TOST','Equivalent','Note'}));
fprintf('Permutation tests (exact; Holm over %d):\n', height(tests)); disp(tests(:, {'ShapeName','Statistic','Difference','P_exact','P_Holm'}));
fprintf('Replacement sessions: %s to %s (N=45 interim look %s)\n\n', string(min(qual.FirstSession(rep))), string(max(qual.LastSession(rep))), string(lock));
if ~exist(options.outDir, 'dir'), mkdir(options.outDir); end
ts = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')); tag = sprintf('N%dvsN%d_%s', n45, n48, ts);
files = {fullfile(options.outDir, ['cohortComparison_' tag '.csv']), fullfile(options.outDir, ['cohortReference_' tag '.csv']), ...
         fullfile(options.outDir, ['cohortPermutation_' tag '.csv']), fullfile(options.outDir, ['cohortReplacements_' tag '.csv']), ...
         fullfile(options.outDir, ['cohortQuality_' tag '.csv']), fullfile(options.outDir, ['cohortEquivalence_' tag '.csv'])};
pf = ["Obs_", "Lo95_", "Hi95_", "Min_", "Max_", "Flag_"]; extra = strings(1, 0);
for j = 1:4, extra = [extra, pf + statRef(j)]; end
refCols = cellstr(["ShapeName", "DeltaICC", "RefLo", "RefHi", "RefP", extra]);
tbls = {main, main(:, refCols), tests, newP, qual, tostT};
for i = 1:numel(files), writeVerified(tbls{i}, files{i}); fprintf('Wrote %s\n', files{i}); end
out = struct('main', main, 'ref', tbls{2}, 'tests', tests, 'newP', newP, 'qual', qual, 'tost', tostT, 'newIDs', newIDs, 'files', {files});
end

function f = pickFile(given, folder, pattern, mustBeUnique)
if given ~= ""
    assert(isfile(given), 'compareCohorts:noFile', 'File not found: %s', given); f = char(given); return
end
d = dir(fullfile(folder, pattern));
assert(~isempty(d), 'compareCohorts:noFile', 'No %s in %s', pattern, folder);
assert(~mustBeUnique || numel(d) == 1, 'compareCohorts:ambiguous', '%d files match %s in %s (expected exactly one frozen file)', numel(d), pattern, folder);
[~, k] = max([d.datenum]); f = fullfile(d(k).folder, d(k).name);
end

function v = iccA1(x)
% ICC(A,1) point estimate only (McGraw & Wong), same algebra as computeICC; checked against it above
[n, k] = size(x); gm = mean(x(:)); rm = mean(x, 2); cm = mean(x, 1);
MSR = k * sum((rm - gm).^2) / (n - 1); MSC = n * sum((cm - gm).^2) / (k - 1);
MSE = (sum((x(:) - gm).^2) - (n - 1) * MSR - (k - 1) * MSC) / ((n - 1) * (k - 1));
v = (MSR - MSE) / (MSR + (k - 1) * MSE + (k / n) * (MSC - MSE));
end

function f = rangeFlag(obs, dist, q95)
% ok inside 2.5-97.5%; outside95 beyond it; SUSPECT beyond the min or max of every possible draw
if obs < min(dist) || obs > max(dist), f = "SUSPECT"; elseif obs < q95(1) || obs > q95(2), f = "outside95"; else, f = "ok"; end
end

function c = kooLi(lb)
% Koo & Li (2016) class from the 95% CI lower bound
if isnan(lb), c = "undefined"; return; end
cats = {'poor', 'moderate', 'good', 'excellent'}; c = string(cats{1 + sum(lb >= [0.5 0.75 0.9])});
end

function q = holmAdjust(p)
[ps, o] = sort(p(:)); m = numel(ps);
adj = min(1, cummax((m - (1:m)' + 1) .* ps)); q = zeros(m, 1); q(o) = adj;
end

function when = sessionTimes(T)
if isdatetime(T.SessionDatetime), when = T.SessionDatetime; return; end
try
    when = datetime(string(T.SessionDatetime), 'InputFormat', 'dd-MMM-yyyy HH:mm:ss', 'Locale', 'en_US');
catch ME
    warning('compareCohorts:sessionDatetime', 'Could not parse SessionDatetime (%s): session-date checks are NOT available.', ME.message);
    when = NaT(height(T), 1);
end
end

function [nReq, status] = zouN(names, icc, n, run, zouDir, tag)
nReq = nan(numel(icc), 1);
if ~run, status = "SKIPPED(runZou=false)"; return; end
in = table(names(:), icc(:), repmat(n, numel(icc), 1), 'VariableNames', {'ShapeName','ICC_BetweenVisit','N_achieved'});
if zouDir ~= ""   % Mac route: R output from zouCohort_M5.sh, used only if it was computed from these ICCs
    if ~isfolder(zouDir), mkdir(zouDir); end
    outCSV = fullfile(zouDir, "zouOutput_" + tag + ".csv");
    writeVerified(in, fullfile(zouDir, "zouInput_" + tag + ".csv"));
    if isfile(outCSV)
        r = readtable(outCSV, 'VariableNamingRule', 'preserve', 'TextType', 'string');
        [tf, loc] = ismember(names(:), r.ShapeName);
        if all(tf) && all(abs(r.ICC_observed(loc) - icc(:)) < 1e-9)
            [~, nm, ex] = fileparts(outCSV); nReq = double(r.N_required(loc)); status = "OK(" + tag + " from " + nm + ex + ")"; return
        end
    end
    warning('compareCohorts:zouPending', ['Zou required N for n=%d NOT computed: %s is missing or was made from other ICCs. ' ...
        'Run src/functions/zouCohort_M5.sh on the Mac, then re-run this. Left NaN.'], n, outCSV);
    status = "PENDING(run zouCohort_M5.sh)"; return
end
d = tempname; mkdir(d); cleaner = onCleanup(@() rmdir(d, 's')); %#ok<NASGU>
inCSV = fullfile(d, 'in.csv'); outCSV = fullfile(d, 'out.csv');
writeVerified(in, inCSV);
try
    r = powerAnalysisICC_R('verbose', false, 'inputCSV', inCSV, 'outputCSV', outCSV);
    [tf, loc] = ismember(names(:), string(r.ShapeName));
    assert(all(tf), 'compareCohorts:zouNames', 'R output is missing shapes.');
    nReq = double(r.N_required(loc)); status = "OK";
catch ME
    warning('compareCohorts:zouFailed', 'Zou required N FAILED for n=%d (%s); left NaN, not estimated.', n, ME.message);
    status = "FAILED";
end
end

function writeVerified(tbl, path)
% Write CSV and fail if the header on disk is not the table's variable names (FieldTrip join.m hazard)
writetable(tbl, path);
fid = fopen(path, 'r'); assert(fid > 0, 'compareCohorts:writeFail', 'Cannot reopen %s', path);
hdr = fgetl(fid); fclose(fid);
assert(strcmp(hdr, strjoin(tbl.Properties.VariableNames, ',')), 'compareCohorts:badHeader', 'Bad header in %s', path);
end
