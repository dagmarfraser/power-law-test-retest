function md = makeDocTables_2026(tag)
% makeDocTables_2026 - Markdown tables for docs/AnalysisPipeline.md from the newest outputs
%
% Emits the N=final tables quoted in AnalysisPipeline.md (beta vs theory, beta vs
% jerk ICC, absolute vs consistency, CCC vs ICC, Zou power, variance split), so
% the docs are refreshed from a script, not typed by hand. Optional tag limits
% the source files to names containing it. Writes data/processed/docTables_<ts>.md.
%
% d.s.fraser@bham.ac.uk

if nargin < 1, tag = ""; end
proc = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'data', 'processed');
[I, fI] = rd(proc, 'icc_results_2*.csv', tag);
[BT, fBT] = rd(proc, 'beta_vs_theory_2*.csv', tag);
[SY, fSY] = rd(proc, 'icc_type_symmetry_2*.csv', tag);
P = readtable(fullfile(proc, 'icc_power_output.csv'), 'VariableNamingRule', 'preserve');
Ia = I(strcmp(I.ICCType, 'absolute'), :);
get = @(sh, p) Ia(strcmp(Ia.ShapeName, sh) & strcmp(Ia.Parameter, p), :);
L = {};

L{end+1} = sprintf('Sources: `%s`, `%s`, `%s`, `icc_power_output.csv`', fI, fBT, fSY);
L{end+1} = '';
L{end+1} = '| Shape | phi | Beta_SG6_IRLS | Beta_BW_Linear | H&S theoretical | %-of-theory (SG6_IRLS) | %-of-theory (BW_Linear) |';
L{end+1} = '|---|---|---|---|---|---|---|';
for i = 1:height(BT)
    L{end+1} = sprintf('| %s | %g | %.3f | %.3f | %.3f | %.0f%% | %.0f%% |', BT.ShapeName{i}, BT.Phi(i), BT.Beta_SG6_IRLS_mean(i), ...
        BT.Beta_BW_Linear_mean(i), BT.Theoretical(i), BT.PctOfTheory_SG6IRLS(i), BT.PctOfTheory_BWLinear(i)); %#ok<AGROW>
end

order = {'phi=0.8', 'phi=0.4', 'Square', 'Ellipse', 'Cursive'};
L = [L, {'', '| Shape | Beta_SG6_IRLS ICC [95% CI] | Class | MeanJerk_SG ICC [95% CI] | Class |', '|---|---|---|---|---|'}];
for s = order
    b = get(s{1}, 'Beta_SG6_IRLS'); j = get(s{1}, 'MeanJerk_SG');
    L{end+1} = sprintf('| %s | %s | %s | %s | %s |', s{1}, ci(b), kooLi(b.ICC_BetweenVisit_LB), ci(j), kooLi(j.ICC_BetweenVisit_LB)); %#ok<AGROW>
end

L = [L, {'', '| Parameter | Shape | Absolute | Consistency | Diff |', '|---|---|---|---|---|'}];
for i = 1:height(SY)
    L{end+1} = sprintf('| %s | %s | %.3f | %.3f | %.3f |', SY.Parameter{i}, SY.ShapeName{i}, SY.ICC_Absolute(i), SY.ICC_Consistency(i), SY.Diff(i)); %#ok<AGROW>
end

shapes = {'phi=0.4', 'phi=0.8', 'Ellipse', 'Square', 'Cursive'};
L = [L, {'', '| Shape | CCC | ICC(A,1) | gap |', '|---|---|---|---|'}];
for s = shapes
    b = get(s{1}, 'Beta_SG6_IRLS'); n = b.ICC_BetweenVisit_N; icc = b.ICC_BetweenVisit;
    ccc = fzero(@(c) c + c*(1-c)/(n-1+c) - icc, icc);    % exact Lin/ICC(A,1) identity for k=2 (computeCCC.m)
    L{end+1} = sprintf('| %s | %.3f | %.3f | %.4f |', s{1}, ccc, icc, icc - ccc); %#ok<AGROW>
end

L = [L, {'', '| Shape | ICC | N required | N achieved | Required N cleared? |', '|---|---|---|---|---|'}];
for s = order
    b = get(s{1}, 'Beta_SG6_IRLS'); pr = P(strcmp(P.ShapeName, s{1}), :);
    if isnan(pr.N_required), req = 'intractable (below p0=0.75)'; ok = 'no -- not an N problem';
    else, req = sprintf('%d', pr.N_required); ok = ternary(pr.N_required <= b.ICC_BetweenVisit_N, '**YES**', 'no'); end
    L{end+1} = sprintf('| %s | %.3f | %s | %d | %s |', s{1}, b.ICC_BetweenVisit, req, b.ICC_BetweenVisit_N, ok); %#ok<AGROW>
end

c5 = get('Cursive', 'Beta_SG6_IRLS'); c4 = get('Square', 'Beta_SG6_IRLS');
L{end+1} = '';
L{end+1} = sprintf('Variance split (Beta_SG6_IRLS): BetweenSD Cursive %.4f vs Square %.4f; WithinSD Cursive %.4f vs Square %.4f; within-visit ICC Cursive %.2f / %.2f', ...
    c5.BetweenSD, c4.BetweenSD, c5.WithinSD, c4.WithinSD, c5.ICC_WithinVisit1, c5.ICC_WithinVisit2);
jt = Ia(strcmp(Ia.Parameter, 'MeanJerk_SG') & ~strcmp(Ia.ShapeName, 'Cursive'), :);
L{end+1} = sprintf('MeanJerk_SG templated ICC %.2f to %.2f (LB %.2f to %.2f); beta templated %.2f to %.2f', min(jt.ICC_BetweenVisit), ...
    max(jt.ICC_BetweenVisit), min(jt.ICC_BetweenVisit_LB), max(jt.ICC_BetweenVisit_LB), ...
    min(Ia.ICC_BetweenVisit(strcmp(Ia.Parameter, 'Beta_SG6_IRLS') & ~strcmp(Ia.ShapeName, 'Cursive'))), ...
    max(Ia.ICC_BetweenVisit(strcmp(Ia.Parameter, 'Beta_SG6_IRLS') & ~strcmp(Ia.ShapeName, 'Cursive'))));

[TR, fTR] = rd(proc, 'trial_level_results_2*.csv', tag);
pipes = TR.Properties.VariableNames(startsWith(TR.Properties.VariableNames, 'Beta_'));
for s = 1:5
    m = cellfun(@(p) mean(TR.(p)(TR.ShapeType == s), 'omitnan'), pipes);
    L{end+1} = sprintf('Pipeline spread %s (%s, trial means over %d pipelines): %.3f to %.3f, span %.3f; SG6_IRLS minus BW_Linear %.3f', ...
        shapes{s}, fTR, numel(pipes), min(m), max(m), max(m) - min(m), m(strcmp(pipes, 'Beta_SG6_IRLS')) - m(strcmp(pipes, 'Beta_BW_Linear'))); %#ok<AGROW>
end

md = string(L(:));
f = fullfile(proc, ['docTables_' datestr(now, 'yyyymmdd_HHMMSS') '.md']);
writelines(md, f); fprintf('%s\n', md{:}); fprintf('Saved: %s\n', f);
end

function s = ci(r), s = sprintf('%.3f [%.3f, %.3f]', r.ICC_BetweenVisit, r.ICC_BetweenVisit_LB, r.ICC_BetweenVisit_UB); end
function c = kooLi(lb), n = ["poor", "moderate", "good", "excellent"]; c = char(n(discretize(lb, [-Inf 0.5 0.75 0.9 Inf]))); end
function out = ternary(c, a, b), if c, out = a; else, out = b; end, end

function [T, name] = rd(folder, pattern, tag)
d = dir(fullfile(folder, pattern)); d = d(contains({d.name}, tag));
assert(~isempty(d), 'makeDocTables:notFound', 'No %s (tag "%s") in %s', pattern, tag, folder);
[~, i] = max([d.datenum]); name = d(i).name;
T = readtable(fullfile(folder, name), 'VariableNamingRule', 'preserve');
end
