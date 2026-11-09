function T = diffRunOutputs_2026(oldTag, newTag)
% diffRunOutputs_2026 - Which numbers changed between two runs' output CSVs
%
% For every data/processed CSV whose name contains oldTag (e.g. '20261103_15')
% finds the file with the same prefix containing newTag (e.g. '20261109_11'),
% and reports per numeric column the largest absolute change and how many
% cells changed by more than 1e-9. Used to decide which documented numbers
% must be refreshed after a re-run. Writes data/processed/runDiff_<old>_vs_<new>.csv.
%
% USAGE: T = diffRunOutputs_2026('20261103_15', '20261109_11');
%
% d.s.fraser@bham.ac.uk

proc = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'data', 'processed');
oldF = dir(fullfile(proc, ['*' oldTag '*.csv']));
rows = {};
for i = 1:numel(oldF)
    prefix = regexprep(oldF(i).name, ['_?' oldTag '\d*\.csv$'], '');
    newF = dir(fullfile(proc, [prefix '_' newTag '*.csv']));
    if isempty(newF)
        rows{end+1} = table(string(oldF(i).name), "", "(no new file)", NaN, NaN, NaN, ...
            'VariableNames', {'OldFile', 'NewFile', 'Column', 'MaxAbsChange', 'nChanged', 'nCells'}); %#ok<AGROW>
        continue
    end
    [~, k] = max([newF.datenum]);
    A = readtable(fullfile(proc, oldF(i).name), 'VariableNamingRule', 'preserve');
    B = readtable(fullfile(proc, newF(k).name), 'VariableNamingRule', 'preserve');
    if height(A) ~= height(B)
        rows{end+1} = table(string(oldF(i).name), string(newF(k).name), "(row count differs)", ...
            height(B) - height(A), NaN, NaN, 'VariableNames', {'OldFile', 'NewFile', 'Column', 'MaxAbsChange', 'nChanged', 'nCells'}); %#ok<AGROW>
        continue
    end
    for v = intersect(A.Properties.VariableNames, B.Properties.VariableNames, 'stable')
        a = A.(v{1}); b = B.(v{1});
        if ~isnumeric(a) || ~isnumeric(b), continue; end
        d = abs(a - b); d(isnan(a) & isnan(b)) = 0; d(isnan(a) ~= isnan(b)) = Inf;
        rows{end+1} = table(string(oldF(i).name), string(newF(k).name), string(v{1}), max(d(:)), ...
            sum(d(:) > 1e-9), numel(d), 'VariableNames', {'OldFile', 'NewFile', 'Column', 'MaxAbsChange', 'nChanged', 'nCells'}); %#ok<AGROW>
    end
end
T = vertcat(rows{:});
f = fullfile(proc, sprintf('runDiff_%s_vs_%s.csv', oldTag, newTag));
writetable(T, f);
fprintf('Saved: %s\n', f);
end
