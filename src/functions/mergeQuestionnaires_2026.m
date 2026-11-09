function out = mergeQuestionnaires_2026(rootDir)
% mergeQuestionnaires_2026 - Join CATI / M-EDL scores to per-participant kinematics
%
% Reads data/CATI and M-EDL scores anonymised.xlsx and the newest
% data/processed/trial_level_results_*.csv, validates both, and writes two
% de-identified CSVs (timestamped, never overwritten) plus a sidecar README
% to data/processed/:
%   questionnaires_CATI_MEDL_N<n>_<ts>.csv
%   participant_kinematics_questionnaires_N<n>_<ts>.csv
% n is DERIVED from the data (no participant count is hard-coded), so adding
% participants only needs the sheet and trial_level_results to be refreshed.
%
% Outcomes (confirmatory pipeline): Beta = Beta_SG6_IRLS, Jerk = MeanJerk_SG.
% Per shape: mean over visits of visit means of session means (Beta_<shape>)
% and per-visit values (Beta_<shape>_V<k>); same for Jerk_.
% ShapeType 1-5 = phi04, phi08, Ellipse, Square, Cursive.
%
% FAILS LOUDLY on: missing/non-numeric cells, duplicate IDs, ID mismatch
% between sheet and trial data, CATI total != sum of subscales, subscale
% outside 7-35, missing outcome columns, or an incomplete participant x
% visit x shape grid.
%
% CATI subscale labels are the published English et al. (2021) order and are
% UNVERIFIED against the students' scoring: set LABELS_VERIFIED = true only
% once confirmed. While false, a warning is raised and the sidecar says so.

LABELS_VERIFIED = false;
subLabels  = {'SocialInteractions','Communication','SocialCamouflage', ...
              'RepetitiveBehaviours','CognitiveRigidity','SensorySensitivity'};
shapeNames = {'phi04','phi08','Ellipse','Square','Cursive'};
outcomes   = struct('prefix', {'Beta','Jerk'}, 'col', {'Beta_SG6_IRLS','MeanJerk_SG'});

if nargin < 1, rootDir = fileparts(fileparts(fileparts(mfilename('fullpath')))); end
procDir = fullfile(rootDir,'data','processed');
xlsx    = fullfile(rootDir,'data','CATI and M-EDL scores anonymised.xlsx');
assert(isfile(xlsx), 'mergeQuestionnaires_2026:noSheet', 'Missing %s', xlsx);
tl = dir(fullfile(procDir,'trial_level_results_*.csv'));
assert(~isempty(tl), 'mergeQuestionnaires_2026:noTrials', 'No trial_level_results_*.csv in %s', procDir);
[~,k] = max([tl.datenum]); tlFile = fullfile(tl(k).folder, tl(k).name);

% ---- questionnaire sheet: rows 1-2 are headers, ID in col 9, 7 CATI cols, M-EDL col 8
C = readcell(xlsx,'Sheet','Sheet1'); D = C(3:end,:);
isNum = cellfun(@(v) isnumeric(v) && isscalar(v) && ~isnan(v), D);
keep = any(isNum,2); D = D(keep,:); isNum = isNum(keep,:);
assert(size(D,2) == 9 && all(isNum(:)), 'mergeQuestionnaires_2026:badCells', ...
    'Sheet must be N x 9 numeric; %d non-numeric/missing cells', sum(~isNum(:)));
M = cell2mat(D);
subNames = arrayfun(@(j) sprintf('CATI_Sub%d_%s', j, subLabels{j}), 1:6, 'UniformOutput', false);
Q = array2table(M(:,[9 1:8]), 'VariableNames', [{'ParticipantID','CATI_Total'}, subNames, {'M_EDL'}]);
assert(numel(unique(Q.ParticipantID)) == height(Q), 'mergeQuestionnaires_2026:dupID', 'Duplicate ParticipantID');
sub = Q{:,3:8};
bad = Q.CATI_Total ~= sum(sub,2);
assert(~any(bad), 'mergeQuestionnaires_2026:totalMismatch', 'CATI total != subscale sum for ID(s): %s', mat2str(Q.ParticipantID(bad)'));
assert(all(sub(:) >= 7 & sub(:) <= 35), 'mergeQuestionnaires_2026:subRange', 'CATI subscale outside 7-35');

% ---- trial data -> participant x visit x shape outcomes (confirmatory pipeline)
T = readtable(tlFile, 'VariableNamingRule', 'preserve');
cols = {outcomes.col};
assert(all(ismember(cols, T.Properties.VariableNames)), 'mergeQuestionnaires_2026:noOutcome', ...
    'Missing outcome column(s): %s', strjoin(setdiff(cols, T.Properties.VariableNames), ', '));
ids = unique(T.ParticipantID); visits = unique(T.Visit)';
assert(isequal(sort(Q.ParticipantID), ids), 'mergeQuestionnaires_2026:idMismatch', ...
    'In sheet only: %s ; in trials only: %s', mat2str(setdiff(Q.ParticipantID,ids)'), mat2str(setdiff(ids,Q.ParticipantID)'));
vis = aggregateToVisitMeans(aggregateToSessionMeans(T, cols), cols);
nExp = numel(ids) * numel(visits) * numel(shapeNames);
assert(height(vis) == nExp && ~any(any(isnan(vis{:,cols}))), 'mergeQuestionnaires_2026:gridIncomplete', ...
    'Expected %d participant x visit x shape rows with no NaN, got %d', nExp, height(vis));
W = table(ids, 'VariableNames', {'ParticipantID'});
for o = 1:numel(outcomes)
    for s = 1:numel(shapeNames)
        nm = sprintf('%s_%s', outcomes(o).prefix, shapeNames{s}); sel = vis.ShapeType == s;
        W.(nm) = arrayfun(@(p) mean(vis.(outcomes(o).col)(vis.ParticipantID==p & sel)), ids);
        for v = visits
            W.(sprintf('%s_V%d', nm, v)) = arrayfun(@(p) vis.(outcomes(o).col)(vis.ParticipantID==p & sel & vis.Visit==v), ids);
        end
    end
end
Merged = innerjoin(Q, W, 'Keys', 'ParticipantID');
assert(height(Merged) == height(Q), 'mergeQuestionnaires_2026:joinLoss', 'Join dropped rows');

% ---- write (timestamped, header verified)
n  = height(Merged); ts = char(datetime('now','Format','yyyyMMdd_HHmmss'));
fQ = fullfile(procDir, sprintf('questionnaires_CATI_MEDL_N%d_%s.csv', n, ts));
fM = fullfile(procDir, sprintf('participant_kinematics_questionnaires_N%d_%s.csv', n, ts));
fR = fullfile(procDir, sprintf('questionnaires_CATI_MEDL_N%d_%s_README.md', n, ts));
writeVerified(Q, fQ); writeVerified(Merged, fM);
fid = fopen(fR,'w'); assert(fid > 0, 'mergeQuestionnaires_2026:readme', 'Cannot write %s', fR);
fprintf(fid, ['# questionnaires_CATI_MEDL_N%d_%s\n\nSource sheet: %s\nTrial data: %s\n' ...
    'Outcomes: Beta = %s, Jerk = %s; mean over visits of visit means of session means (_V<k> = single visit).\n' ...
    'Shapes: 1 phi04, 2 phi08, 3 Ellipse, 4 Square, 5 Cursive.\n' ...
    'CATI subscale labels verified against students scoring: %s\n' ...
    '(While false the labels are the published English et al. 2021 order, ASSUMED.)\n' ...
    'M-EDL: %d of %d scores are exactly 0; meaning of 0 (genuine vs not recorded) unconfirmed.\n'], ...
    n, ts, xlsx, tlFile, outcomes(1).col, outcomes(2).col, mat2str(LABELS_VERIFIED), sum(Q.M_EDL==0), n);
fclose(fid);
if ~LABELS_VERIFIED
    warning('mergeQuestionnaires_2026:labelsUnverified', ...
        'CATI subscale labels are ASSUMED (published order), not verified with the students.');
end
fprintf('Wrote %d participants:\n  %s\n  %s\n  %s\n', n, fQ, fM, fR);
out = struct('questionnaires', Q, 'merged', Merged, 'files', {{fQ, fM, fR}});
end

function writeVerified(tbl, path)
% Write CSV and fail if the header row on disk is not the table's variable names.
writetable(tbl, path);
fid = fopen(path,'r'); assert(fid > 0, 'mergeQuestionnaires_2026:writeFail', 'Cannot reopen %s', path);
hdr = fgetl(fid); fclose(fid);
assert(strcmp(hdr, strjoin(tbl.Properties.VariableNames, ',')), 'mergeQuestionnaires_2026:badHeader', ...
    'Header on disk differs from table variable names in %s', path);
end
