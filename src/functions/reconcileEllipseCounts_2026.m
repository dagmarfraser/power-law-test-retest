function R = reconcileEllipseCounts_2026(options)
% reconcileEllipseCounts_2026 - One reconciled N=48 Ellipse trial count across MSc and BRM pipelines
%
% Explains the four Ellipse counts in circulation (BRM handoff 2026-11-22):
%   2,880  Ellipse rows in the session metadata, 48-person cohort (48 x 2 visits x 3 sessions x 10)
%   2,877  kept by importDB_fraser_v002 (BRM importer; PowerLawSimulationPreReg/src/functions)
%   2,879  rows in the MSc run trial_level_results_<RunStamp>.csv
%   2,829  old pre-N=48 corpus (importDB_fraser_v001 over all 51 folders, incl. ID101/102/214)
% Every Ellipse metadata row gets one line saying where it is kept or dropped and why.
% Read-only use of importDB_fraser_v001/v002 (frozen, not edited).
%
% Writes data/processed/ellipseCountReconciliation_<ts>_trials.csv and _summary.csv.
%
% USAGE: R = reconcileEllipseCounts_2026();
%        R = reconcileEllipseCounts_2026(RunV001=false);   % skip the slow v001 re-import
%
% d.s.fraser@bham.ac.uk

arguments
    options.RunStamp string = "20261109_112129"
    options.PreRegRoot string = ""
    options.RunV001 (1,1) logical = true
end

here   = fileparts(mfilename('fullpath'));
anaDir = fileparts(fileparts(here));                          % Analysis_2026
b2b    = fileparts(fileparts(fileparts(anaDir)));            % Brain2Bee
prereg = options.PreRegRoot;
if prereg == "", prereg = fullfile(b2b, 'PowerLawSimulationPreReg'); end
fnDir  = fullfile(prereg, 'src', 'functions');
assert(isfile(fullfile(fnDir, 'importDB_fraser_v002.m')), 'reconcile:noV002', 'importDB_fraser_v002 not found in %s', fnDir);
addpath(fnDir);
bRoot  = fullfile(prereg, 'data', 'fraser');                  % the copy the BRM importers read
mRoot  = fullfile(anaDir, 'data', 'raw');                     % the copy the MSc run read
proc   = fullfile(anaDir, 'data', 'processed');
EXCL   = ["ID101","ID102","ID214"];

%% 1. The two raw copies must hold the same session files
lst = @(r) sort(string(cellfun(@(p,n) [p(numel(fullfile(r,'automatic'))+2:end) '/' n], ...
    {dir(fullfile(r,'automatic','ID*','betaTestv002 * tracingSection.csv')).folder}, ...
    {dir(fullfile(r,'automatic','ID*','betaTestv002 * tracingSection.csv')).name}, 'UniformOutput', false)));
fb = lst(bRoot); fm = lst(mRoot);
if ~isequal(fb, fm)
    error('reconcile:rawCopiesDiffer', 'BRM and MSc raw copies list different session files:\n only BRM: %s\n only MSc: %s', ...
        strjoin(setdiff(fb, fm), ', '), strjoin(setdiff(fm, fb), ', '));
end
fprintf('Raw copies agree: %d session metadata files in %s and %s\n', numel(fb), bRoot, mRoot);

%% 2. Every Ellipse metadata row, all folders, with "has samples" flag
rows = {};
for f = fb(:)'
    parts = split(f, '/'); pid = parts(1);
    stem  = string(regexp(parts(end), '\d{4}-\d{2}-\d{2} \d{6}', 'match', 'once'));
    meta  = readtable(fullfile(bRoot, 'automatic', f), 'VariableNamingRule', 'preserve');
    tr    = meta.trial(meta.tracingScene_object1_imageNumber == 3);
    io    = detectImportOptions(fullfile(bRoot, 'automatic', pid, "betaTestv002 " + stem + " tracingSection-enhanced.csv"));
    io.SelectedVariableNames = 'response_index';
    ri    = unique(readtable(fullfile(bRoot, 'automatic', pid, "betaTestv002 " + stem + " tracingSection-enhanced.csv"), io).response_index);
    for t = tr'
        rows(end+1, :) = {pid, stem, t, ~ismember(pid, EXCL), ismember(t, ri)}; %#ok<AGROW>
    end
end
T = cell2table(rows, 'VariableNames', {'Folder','Stem','Trial','InCohort','HasSamples'});
T.Key = T.Folder + "|" + T.Stem + "|" + string(T.Trial);

%% 3. BRM importer v002 (cohort of 48)
[trB, rejB] = importDB_fraser_v002(bRoot, Verbose=false);
tokB = regexp(string({trB.notes})', 'stem=(\S+ \S+)', 'tokens', 'once');
numB = regexp(string({trB.trialID})', '_T(\d+)_', 'tokens', 'once');
keyB = "ID" + extractAfter(string({trB.subjectID})', "F") + "|" + string(cellfun(@(c) c{1}, tokB, 'UniformOutput', false)) ...
     + "|" + string(str2double(string(cellfun(@(c) c{1}, numB, 'UniformOutput', false))));
keyR = string(rejB.participant) + "|" + string(rejB.stem) + "|" + string(rejB.trial);
T.V002 = repmat("notInCohort", height(T), 1);
T.V002(ismember(T.Key, keyB)) = "kept";
[isR, iR] = ismember(T.Key, keyR);
T.V002(isR) = "rejected:" + string(rejB.reason(iR(isR))) + " (" + string(rejB.detail(iR(isR))) + ")";
assert(all(ismember(keyB, T.Key)) && all(ismember(keyR, T.Key)), 'reconcile:v002Unmatched', 'v002 output has trials not in the metadata');

%% 4. MSc run
M = readtable(fullfile(proc, "trial_level_results_" + options.RunStamp + ".csv"), 'VariableNamingRule', 'preserve');
M = M(M.ShapeType == 3, :);
sd = M.SessionDatetime;
if ~isdatetime(sd), sd = datetime(string(sd), 'InputFormat', 'dd-MMM-yyyy HH:mm:ss'); end
keyM = "ID" + string(M.ParticipantID) + "|" + string(sd, 'yyyy-MM-dd HHmmss') + "|" + string(M.TrialNum);
bad = setdiff(keyM, T.Key);
assert(isempty(bad), 'reconcile:mscUnmatched', 'MSc rows not in metadata: %s', strjoin(bad, ', '));
[inM, iM] = ismember(T.Key, keyM);
T.InMScRun = inM;
T.MSc_SG6IRLS_finite = false(height(T), 1);
T.MSc_SG6IRLS_finite(inM) = isfinite(M.Beta_SG6_IRLS(iM(inM)));

%% 5. Old corpus: importDB_fraser_v001 over every folder (frozen importer, default options)
nV001 = NaN;
if options.RunV001
    trO = importDB_fraser_v001(bRoot, Verbose=false);
    nV001 = numel(trO);
end

%% Summary
c  = T.InCohort;
S = table( ...
  ["Ellipse metadata rows, all 51 folders"; "Ellipse metadata rows, 48-person cohort"; ...
   "  of which no samples in enhanced CSV"; "Kept by importDB_fraser_v002"; ...
   "Rejected by v002 (all reasons)"; "Rows in MSc run " + options.RunStamp; ...
   "  of which finite SG6-IRLS beta"; "In MSc run but rejected by v002"; ...
   "Kept by v002 but not in MSc run"; "Ellipse rows with samples, all 51 folders"; ...
   "importDB_fraser_v001 re-run, all folders (old corpus)"], ...
  [height(T); sum(c); sum(c & ~T.HasSamples); sum(T.V002 == "kept"); sum(startsWith(T.V002, "rejected")); ...
   sum(T.InMScRun); sum(T.MSc_SG6IRLS_finite); sum(T.InMScRun & startsWith(T.V002, "rejected")); ...
   sum(T.V002 == "kept" & ~T.InMScRun); sum(T.HasSamples); nV001], 'VariableNames', {'Count','N'});
ts = string(datetime('now'), 'yyyyMMdd_HHmmss');
writetable(T(~(T.V002 == "kept" & T.InMScRun), :),fullfile(proc, "ellipseCountReconciliation_" + ts + "_exceptions.csv"));
writetable(T, fullfile(proc, "ellipseCountReconciliation_" + ts + "_trials.csv"));
writetable(S, fullfile(proc, "ellipseCountReconciliation_" + ts + "_summary.csv"));
disp(S);
disp(T(c & ~(T.V002 == "kept" & T.InMScRun), {'Folder','Stem','Trial','HasSamples','V002','InMScRun','MSc_SG6IRLS_finite'}));
fprintf('Excluded folders: %d Ellipse rows (%s)\n', sum(~c), strjoin(EXCL, ', '));
fprintf('Wrote ellipseCountReconciliation_%s_{trials,summary,exceptions}.csv in %s\n', ts, proc);
R = struct('summary', S, 'trials', T, 'v002Rejects', rejB, 'stamp', ts);
end
