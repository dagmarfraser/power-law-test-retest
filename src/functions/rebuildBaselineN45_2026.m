function out = rebuildBaselineN45_2026(options)
% rebuildBaselineN45_2026 - Replace the N=45 baseline with the 45 originals from a current run
%
% The baseline frozen on 2026-10-12 came from the 2026-08-04 run, i.e. before the
% 2026-11-02 scale fix and the 2026-11-09 finger-touch fix, so comparing it with a
% current run mixes pipeline changes into the N=45 vs N=48 sensitivity analysis
% (Dagmar 2026-11-09: "N=45 is obsolete"; "the sensitivity analysis should be on
% recent stats"). This:
%   1. moves the old baseline_N45/ to data/processed/archive/baseline_N45_frozen20261012/
%   2. writes a new baseline_N45/ holding the original participants (all IDs outside
%      newIDRange) from the given trial-level run: trial_level_results_<src>_orig.csv/.mat
%   3. runs runICC_2026 on that subset and moves its icc_results_* into baseline_N45/
%   4. writes MANIFEST_<today>.md (bytes + MD5) so preflightN48_2026 can check it
% Fails loudly if the target archive exists or the subset is not the expected size.
%
% USAGE: out = rebuildBaselineN45_2026();   % newest trial_level_results_2*.mat
%
% d.s.fraser@bham.ac.uk

arguments
    options.trialMat string = ""
    options.newIDRange (1,2) double = [400 499]
    options.expectedN (1,1) double = 45
end

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
proc = fullfile(root, 'data', 'processed');
baseDir = fullfile(proc, 'baseline_N45');
arch = fullfile(proc, 'archive', 'baseline_N45_frozen20261012');

src = options.trialMat;
if src == ""
    d = dir(fullfile(proc, 'trial_level_results_2*.mat')); [~, i] = max([d.datenum]);
    src = fullfile(proc, d(i).name);
end
[~, srcName] = fileparts(src);
S = load(src, 'allResults', 'participantSummary');
isNew = S.allResults.ParticipantID >= options.newIDRange(1) & S.allResults.ParticipantID <= options.newIDRange(2);
allResults = S.allResults(~isNew, :);
nOrig = numel(unique(allResults.ParticipantID));
assert(nOrig == options.expectedN, 'rebuildBaseline:N', 'Subset has %d participants, expected %d.', nOrig, options.expectedN);
participantSummary = S.participantSummary(~ismember(S.participantSummary.ParticipantID, unique(S.allResults.ParticipantID(isNew))), :); %#ok<NASGU>

%% 1. Archive the old frozen baseline
assert(~isfolder(arch), 'rebuildBaseline:archiveExists', '%s already exists; nothing moved.', arch);
if ~isfolder(fileparts(arch)), mkdir(fileparts(arch)); end
[ok, msg] = movefile(baseDir, arch);
assert(ok, 'rebuildBaseline:move', 'Could not archive %s: %s', baseDir, msg);
mkdir(baseDir);

%% 2. New baseline trial file
stem = [srcName '_orig'];
save(fullfile(baseDir, [stem '.mat']), 'allResults', 'participantSummary');
writetable(allResults, fullfile(baseDir, [stem '.csv']));
hdr = fgetl(fopen(fullfile(baseDir, [stem '.csv']))); fclose('all');
assert(startsWith(hdr, allResults.Properties.VariableNames{1}), 'rebuildBaseline:header', 'CSV header missing (join.m shadow?)');

%% 3. ICC on the subset (runICC_2026 writes to data/processed; move the pair in)
before = dir(fullfile(proc, 'icc_results_2*.csv'));
runICC_2026('dataFile', string(fullfile(baseDir, [stem '.mat'])), 'verbose', false);
after = dir(fullfile(proc, 'icc_results_2*.csv'));
newIcc = setdiff({after.name}, {before.name});
assert(numel(newIcc) == 1, 'rebuildBaseline:icc', 'Expected one new icc_results file, found %d.', numel(newIcc));
[~, iccStem] = fileparts(newIcc{1});
for ext = {'.csv', '.mat'}
    movefile(fullfile(proc, [iccStem ext{1}]), baseDir);
end

%% 4. Manifest
files = dir(fullfile(baseDir, '*.*')); files = files(~[files.isdir]);
L = {sprintf('# baseline_N45: the %d original participants from `%s` (rebuilt %s)', nOrig, srcName, datestr(now, 'yyyy-mm-dd')), '', ...
    ['Built by `rebuildBaselineN45_2026` from the current pipeline (5.209 pt/mm scale, Pencil-only `touch_type == 2`), ' ...
     'so the N=45 vs N=48 sensitivity analysis compares like with like. The previous baseline (frozen 2026-10-12 from the ' ...
     '2026-08-04 run, before both fixes) is in `data/processed/archive/baseline_N45_frozen20261012/` and is obsolete. ' ...
     'Do not edit; rebuild with the script if the pipeline changes again.'], '', '| File | Bytes | MD5 |', '|---|---|---|'};
for i = 1:numel(files)
    L{end+1} = sprintf('| `%s` | %d | %s |', files(i).name, files(i).bytes, md5file(fullfile(baseDir, files(i).name))); %#ok<AGROW>
end
mfile = fullfile(baseDir, ['MANIFEST_' datestr(now, 'yyyymmdd') '.md']);
writelines(string(L(:)), mfile);

out = struct('source', src, 'nOriginal', nOrig, 'baseDir', baseDir, 'archive', arch, 'iccFile', iccStem, 'manifest', mfile);
fprintf('Baseline rebuilt: %d participants from %s; old baseline archived to %s\n', nOrig, srcName, arch);
end

function h = md5file(f)
fid = fopen(f, 'r'); b = fread(fid, Inf, '*uint8'); fclose(fid);
md = java.security.MessageDigest.getInstance('MD5'); md.update(b);
h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end
