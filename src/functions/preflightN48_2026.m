function out = preflightN48_2026(options)
% preflightN48_2026 - Read-only readiness check before the N=48 re-run
%
% Safe to run at any time (no data written). Checks:
%   1. frozen baseline intact: bytes and MD5 of every file in baseline_N45/ against its MANIFEST_*.md (ERROR if not)
%   2. every original participant still has >= minSessions sessions (ERROR if not)
%   3. excluded IDs (default 101, 102, 214) are still incomplete, i.e. still excluded (ERROR if not; rule 2026-10-12)
%   4. replacements (IDs in newIDRange not in the baseline): sessions, visits, sessions per visit, missing
%      -enhanced files; ready = 1..maxNew complete replacements
%   Any other ID folder, and any replacement that is incomplete, is WARNED about.
%
% OUTPUT  out.ready, out.expectedN (originals + complete replacements), out.inventory (table), out.nOriginal,
%         out.nReplacementComplete, out.replacementIDs

arguments
    options.minSessions (1,1) double = 6
    options.excludedIDs (1,:) double = [101 102 214]
    options.newIDRange (1,2) double = [400 499]
    options.maxNew (1,1) double = 3
    options.rootDir string = ""
end
if options.rootDir == "", options.rootDir = fileparts(fileparts(fileparts(mfilename('fullpath')))); end
rawDir = fullfile(options.rootDir, 'data', 'raw', 'automatic');
baseDir = fullfile(options.rootDir, 'data', 'processed', 'baseline_N45');

%% 1. Frozen baseline intact
mf = dir(fullfile(baseDir, 'MANIFEST_*.md'));
assert(numel(mf) == 1, 'preflight:manifest', 'Expected exactly one MANIFEST_*.md in %s, found %d.', baseDir, numel(mf));
tok = regexp(fileread(fullfile(mf.folder, mf.name)), '\|\s*`([^`]+)`\s*\|\s*(\d+)\s*\|\s*([0-9a-f]{32})\s*\|', 'tokens');
assert(~isempty(tok), 'preflight:manifestParse', 'No file rows parsed from %s.', mf.name);
bad = strings(0, 1);
for i = 1:numel(tok)
    f = fullfile(baseDir, tok{i}{1}); d = dir(f);
    if isempty(d) || d.bytes ~= str2double(tok{i}{2}) || ~strcmp(md5file(f), tok{i}{3}), bad(end+1, 1) = string(tok{i}{1}); end %#ok<AGROW>
end
assert(isempty(bad), 'preflight:baselineChanged', 'Frozen baseline differs from its manifest: %s', strjoin(bad, ', '));
fprintf('1. Baseline intact: %d files match %s (bytes + MD5)\n', numel(tok), mf.name);

%% 2. Session inventory
tl = dir(fullfile(baseDir, 'trial_level_results_2*.csv')); assert(numel(tl) == 1, 'preflight:baselineFile', 'Need exactly one baseline trial-level csv.');
blOpts = detectImportOptions(fullfile(tl.folder, tl.name), 'VariableNamingRule', 'preserve');
blOpts.SelectedVariableNames = {'ParticipantID'};
idsOrig = unique(readtable(fullfile(tl.folder, tl.name), blOpts).ParticipantID);
D = dir(fullfile(rawDir, 'ID*')); D = D([D.isdir]); n = numel(D);
inv = table('Size', [n 6], 'VariableTypes', {'double','double','double','string','double','string'}, ...
    'VariableNames', {'ID','nSessions','nVisits','PerVisit','nMissingEnhanced','Group'});
for i = 1:n
    fs = dir(fullfile(rawDir, D(i).name, '*tracingSection.csv'));
    fs = fs(~contains({fs.name}, '-enhanced') & ~contains({fs.name}, '-trajectories'));
    miss = sum(~arrayfun(@(f) isfile(fullfile(f.folder, strrep(f.name, ' tracingSection.csv', ' tracingSection-enhanced.csv'))), fs));
    dt = sort(sessionTimes(fs)); vis = zeros(0, 1);
    if ~isempty(dt), vis = [1; 1 + cumsum(diff(dt) > 90/1440)]; end            % 90 min proximity, as runAnalysis_2026
    inv(i, :) = {str2double(D(i).name(3:end)), numel(fs), max([0; vis(:)]), perVisit(vis), miss, ""};
end
inv.Complete = inv.nSessions >= options.minSessions;
inv.Group(:) = "Other";
inv.Group(ismember(inv.ID, idsOrig)) = "Original";
inv.Group(inv.ID >= options.newIDRange(1) & inv.ID <= options.newIDRange(2) & ~ismember(inv.ID, idsOrig)) = "Replacement";
inv.Group(ismember(inv.ID, options.excludedIDs)) = "Excluded";
inv = sortrows(inv, {'Group', 'ID'});

o = inv(inv.Group == "Original", :);
assert(height(o) == numel(idsOrig) && all(o.Complete), 'preflight:originalIncomplete', ...
    'Original participants missing or incomplete: %s', mat2str(setdiff(idsOrig, o.ID(o.Complete))'));
x = inv(inv.Group == "Excluded", :);
assert(~any(x.Complete), 'preflight:excludedNowComplete', ...
    'Excluded IDs %s now have >= %d sessions. The 2026-10-12 rule keeps them excluded: resolve before running.', mat2str(x.ID(x.Complete)'), options.minSessions);
fprintf('2. %d original participants complete (>= %d sessions); excluded IDs %s remain incomplete\n', height(o), options.minSessions, mat2str(options.excludedIDs));
if any(o.nMissingEnhanced > 0), warning('preflight:enhanced', 'Originals with missing -enhanced files: %s', mat2str(o.ID(o.nMissingEnhanced > 0)')); end

%% 3. Replacements and strays
r = inv(inv.Group == "Replacement", :); rc = r(r.Complete, :);
other = inv(inv.Group == "Other", :);
if ~isempty(other), warning('preflight:otherIDs', 'ID folders outside original/excluded/replacement: %s', mat2str(other.ID')); end
if any(~r.Complete), warning('preflight:replacementIncomplete', ...
        'Incomplete replacements %s will be EXCLUDED by runAnalysis_2026 (minSessions). Intended under the stopping rule?', mat2str(r.ID(~r.Complete)')); end
if any(r.nMissingEnhanced > 0), warning('preflight:enhanced', 'Replacements with missing -enhanced files: %s', mat2str(r.ID(r.nMissingEnhanced > 0)')); end
odd = rc(rc.nVisits ~= 2 | rc.PerVisit ~= "[3 3]", :);
if ~isempty(odd), warning('preflight:visitStructure', 'Replacements not 2 visits x 3 sessions: %s', strjoin(odd.ID + " " + odd.PerVisit, '; ')); end
ready = height(rc) >= 1 && height(rc) <= options.maxNew;
fprintf('3. Replacements present: %d (complete %d, max %d). Expected N = %d + %d = %d\n', height(r), height(rc), options.maxNew, ...
    height(o), height(rc), height(o) + height(rc));
disp(inv(inv.Group ~= "Original", {'ID','Group','nSessions','nVisits','PerVisit','nMissingEnhanced','Complete'}));
if ready, fprintf('READY for the N=%d run.\n', height(o) + height(rc));
else, fprintf('NOT READY: no complete replacement data yet (or more than %d).\n', options.maxNew); end
out = struct('ready', ready, 'expectedN', height(o) + height(rc), 'inventory', inv, 'nOriginal', height(o), ...
    'nReplacementComplete', height(rc), 'replacementIDs', rc.ID');
end

function t = sessionTimes(fs)
t = NaN(numel(fs), 1);
for i = 1:numel(fs)
    tk = regexp(fs(i).name, '(\d{4}-\d{2}-\d{2})\s+(\d{6})', 'tokens', 'once');
    if ~isempty(tk), t(i) = datenum(datetime([tk{1} ' ' tk{2}], 'InputFormat', 'yyyy-MM-dd HHmmss')); end
end
assert(~any(isnan(t)), 'preflight:filename', 'Session file without a parseable timestamp.');
end

function s = perVisit(vis)
if isempty(vis), s = "[]"; else, s = string(mat2str(accumarray(vis(:), 1)')); end
end

function h = md5file(f)
fid = fopen(f, 'r'); b = fread(fid, Inf, '*uint8'); fclose(fid);
md = java.security.MessageDigest.getInstance('MD5'); md.update(b);
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
