function out = analyseOrphanRuns_2026(options)
% analyseOrphanRuns_2026 - Do the non-completers (default 101, 102, 214) look like the 45 completers?
%
% Reviewer-facing sensitivity check for the participants excluded under the minSessions rule. Their raw sessions
% are processed with the SAME pipeline (runAnalysis_2026, via the expectedVisits option), reduced to visit means
% (aggregateToSessionMeans / aggregateToVisitMeans), and each value is located in the frozen N=45 distribution.
%
% MATCHED COMPARISON: an orphan visit with m sessions is compared with the originals' visit means computed from
% their FIRST m sessions of that visit only, so fewer sessions (noisier means) are not mistaken for a difference.
% Quantities per shape: V1 mean, V2 mean (if that visit exists), V2 minus V1 shift (if both exist).
%
% FLAGS (same rule as compareCohortsN45N48_2026): SUSPECT = outside min..max of the originals; outside95 = outside
% the empirical 2.5-97.5 percentiles; ok otherwise; NO_DATA = value is NaN (reported, never dropped).
% Descriptive only: n=1 per orphan, no ICC can be computed, no inference. Reasons for dropout are not in the data.
%
% INPUTS (name-value): ids ([101 102 214]), param ("Beta_SG6_IRLS"), baselineFile (frozen baseline_N45 trial csv),
%   outDir (data/processed)
% OUTPUT  out.table (one row per orphan x quantity x shape), out.sessions (orphan x visit session counts), out.file
% FAILS LOUDLY if an id is in the baseline, has no processable trials, or a baseline cell is missing.

arguments
    options.ids (1,:) double = [101 102 214]
    options.param (1,1) string = "Beta_SG6_IRLS"
    options.baselineFile string = ""
    options.outDir string = ""
end
rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
if options.baselineFile == ""
    d = dir(fullfile(rootDir, 'data', 'processed', 'baseline_N45', 'trial_level_results_2*.csv'));
    assert(numel(d) == 1, 'orphan:baseline', 'Expected one frozen baseline trial-level csv, found %d.', numel(d));
    options.baselineFile = string(fullfile(d.folder, d.name));
end
if options.outDir == "", options.outDir = fullfile(rootDir, 'data', 'processed'); end
p = char(options.param);
need = {'ParticipantID', 'Visit', 'Session', 'SessionInVisit', 'ShapeType', p};
T = readtable(options.baselineFile, 'VariableNamingRule', 'preserve');
assert(all(ismember(need, T.Properties.VariableNames)), 'orphan:columns', 'Baseline lacks one of: %s', strjoin(need, ', '));
assert(~any(ismember(options.ids, T.ParticipantID)), 'orphan:inBaseline', 'IDs %s are already in the baseline.', ...
    mat2str(options.ids(ismember(options.ids, T.ParticipantID))));
T = T(:, need);

%% Process the orphans with the unchanged pipeline
O = table();
for id = options.ids
    R = runAnalysis_2026('participantID', "ID" + id, 'minSessions', 1, 'expectedVisits', 2, 'saveResults', false, 'verbose', false);
    assert(height(R) > 0 && all(ismember(need, R.Properties.VariableNames)), 'orphan:noTrials', 'ID%d: no processable trials.', id);
    assert(isequal(unique(R.ParticipantID), id), 'orphan:badID', 'ID%d: pipeline returned ParticipantID %s.', id, mat2str(unique(R.ParticipantID)'));
    O = [O; R(:, need)]; %#ok<AGROW>
end
V = aggregateToVisitMeans(aggregateToSessionMeans(O, {p}), {p});
shapeNames = ["phi=0.4", "phi=0.8", "Ellipse", "Square", "Cursive"];

%% Matched reference from the originals, then locate each orphan value in it
cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
rows = {}; sessRows = {};
for id = options.ids
    Vi = V(V.ParticipantID == id, :);
    for v = unique(Vi.Visit)'
        sessRows(end+1, :) = {id, v, max(Vi.nSessions(Vi.Visit == v))}; %#ok<AGROW>
    end
    for s = 1:5
        vals = nan(1, 2); ms = nan(1, 2);
        for v = 1:2
            k = Vi.Visit == v & Vi.ShapeType == s;
            if any(k), assert(nnz(k) == 1, 'orphan:dup', 'ID%d visit %d shape %d: %d rows.', id, v, s, nnz(k)); vals(v) = Vi.(p)(k); ms(v) = Vi.nSessions(k); end
        end
        for v = 1:2
            if isnan(ms(v)), continue; end
            [refIds, M] = refMeans(T, p, v, ms(v), cache);
            rows(end+1, :) = makeRow(id, sprintf('V%d', v), s, shapeNames(s), ms(v), vals(v), M(:, s)); %#ok<AGROW>
            if v == 2 && ~isnan(ms(1))
                [refIds1, M1] = refMeans(T, p, 1, ms(1), cache);
                assert(isequal(refIds, refIds1), 'orphan:ids', 'Reference IDs differ between visits.');
                rows(end+1, :) = makeRow(id, 'Shift_V2minusV1', s, shapeNames(s), ms(2), vals(2) - vals(1), M(:, s) - M1(:, s)); %#ok<AGROW>
            end
        end
    end
end
tbl = cell2table(rows, 'VariableNames', {'ParticipantID', 'Quantity', 'ShapeType', 'ShapeName', 'nSessions', 'Value', 'RefN', ...
    'RefMean', 'RefSD', 'Z', 'Percentile', 'RefMin', 'RefMax', 'Flag'});
sess = cell2table(sessRows, 'VariableNames', {'ParticipantID', 'Visit', 'nSessions'});

fprintf('Orphan runs vs frozen N=%d baseline (matched session counts), %s\n', numel(unique(T.ParticipantID)), p);
disp(sess); disp(tbl(:, {'ParticipantID', 'Quantity', 'ShapeName', 'nSessions', 'Value', 'RefMean', 'RefSD', 'Z', 'Percentile', 'Flag'}));
nS = sum(tbl.Flag == "SUSPECT"); n95 = sum(tbl.Flag == "outside95"); nNo = sum(tbl.Flag == "NO_DATA");
fprintf('%d values: %d SUSPECT (outside the originals'' min..max), %d outside95, %d NO_DATA, %d ok.\n', height(tbl), nS, n95, nNo, sum(tbl.Flag == "ok"));
if nS > 0, warning('orphan:suspect', '%d orphan value(s) lie outside the range of the completers: %s', nS, strjoin(unique(tbl.Quantity(tbl.Flag == "SUSPECT") + " ID" + tbl.ParticipantID(tbl.Flag == "SUSPECT") + " " + tbl.ShapeName(tbl.Flag == "SUSPECT")), '; ')); end
if nNo > 0, warning('orphan:noData', '%d orphan value(s) are NaN (see Flag NO_DATA).', nNo); end

if ~exist(options.outDir, 'dir'), mkdir(options.outDir); end
f = fullfile(options.outDir, sprintf('orphanRuns_%s.csv', char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))));
writetable(tbl, f);
fid = fopen(f, 'r'); assert(fid > 0, 'orphan:writeFail', 'Cannot reopen %s', f); hdr = fgetl(fid); fclose(fid);
assert(strcmp(hdr, strjoin(tbl.Properties.VariableNames, ',')), 'orphan:badHeader', 'Bad header in %s', f);
fprintf('Wrote %s\n', f);
out = struct('table', tbl, 'sessions', sess, 'file', f, 'baselineFile', options.baselineFile);
end

function [ids, M] = refMeans(T, p, visit, m, cache)
% Originals' participant x shape visit means from the first m sessions of that visit (cached)
key = sprintf('%d_%d', visit, m);
if isKey(cache, key), c = cache(key); ids = c{1}; M = c{2}; return; end
V = aggregateToVisitMeans(aggregateToSessionMeans(T(T.Visit == visit & T.SessionInVisit <= m, :), {p}), {p});
ids = unique(V.ParticipantID); M = nan(numel(ids), 5);
for s = 1:5
    for i = 1:numel(ids)
        x = V.(p)(V.ParticipantID == ids(i) & V.ShapeType == s);
        assert(isscalar(x) && ~isnan(x), 'orphan:refCell', 'Baseline ID %d visit %d shape %d first %d sessions: %d values.', ids(i), visit, s, m, numel(x));
        M(i, s) = x;
    end
end
cache(key) = {ids, M};
end

function r = makeRow(id, q, s, name, m, val, ref)
sd = std(ref); lo = prctile(ref, 2.5); hi = prctile(ref, 97.5);
if isnan(val), flag = "NO_DATA"; pc = NaN; z = NaN;
else
    pc = 100 * (sum(ref < val) + 0.5 * sum(ref == val)) / numel(ref); z = (val - mean(ref)) / sd;
    if val < min(ref) || val > max(ref), flag = "SUSPECT"; elseif val < lo || val > hi, flag = "outside95"; else, flag = "ok"; end
end
r = {id, string(q), s, name, m, val, numel(ref), mean(ref), sd, z, pc, min(ref), max(ref), flag};
end
