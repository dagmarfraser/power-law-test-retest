function S = summariseKeyNumbers_2026(tag)
% summariseKeyNumbers_2026 - The numbers quoted in claude.md section 2, from the newest outputs
%
% Reads the newest timestamped file of each kind in data/processed (plus
% icc_power_output.csv) and prints the headline figures, so the hub text can be
% refreshed from a script rather than by hand. Returns them in struct S and
% writes data/processed/keyNumbers_<ts>.txt. Fails loudly if a file is missing.
% Optional tag (e.g. '20261103_15') restricts to files whose names contain it,
% to reproduce an earlier run's numbers (icc_power_output.csv is untimestamped: always current).
%
% d.s.fraser@bham.ac.uk

if nargin < 1, tag = ""; end
proc = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'data', 'processed');
rd = @(pat) readtable(fullfile(proc, newest(proc, pat, tag)), 'VariableNamingRule', 'preserve');
L = strings(0, 1); add = @(varargin) sprintf(varargin{:});
shapes = {'phi=0.4', 'phi=0.8', 'Ellipse', 'Square', 'Cursive'};

TR = rd('trial_level_results_2*.csv');
b = TR.Beta_SG6_IRLS;
L(end+1) = add('Trials %d, participants %d; Beta_SG6_IRLS %.3f +/- %.3f; NaN %.2f%%', height(TR), ...
    numel(unique(TR.ParticipantID)), mean(b, 'omitnan'), std(b, 'omitnan'), 100*mean(isnan(b)));

I = rd('icc_results_2*.csv'); I = I(strcmp(I.ICCType, 'absolute'), :);
P = readtable(fullfile(proc, 'icc_power_output.csv'), 'VariableNamingRule', 'preserve');
for s = 1:5
    r = I(strcmp(I.ShapeName, shapes{s}) & strcmp(I.Parameter, 'Beta_SG6_IRLS'), :);
    j = I(strcmp(I.ShapeName, shapes{s}) & strcmp(I.Parameter, 'MeanJerk_SG'), :);
    pr = P(strcmp(P.ShapeName, shapes{s}), :);
    L(end+1) = add('%-8s beta ICC(A,1) %.3f [%.3f, %.3f] %s | Zou N %g | MeanJerk_SG %.3f [%.3f, %.3f]', ...
        shapes{s}, r.ICC_BetweenVisit, r.ICC_BetweenVisit_LB, r.ICC_BetweenVisit_UB, kooLi(r.ICC_BetweenVisit_LB), ...
        pr.N_required, j.ICC_BetweenVisit, j.ICC_BetweenVisit_LB, j.ICC_BetweenVisit_UB); %#ok<AGROW>
end

A = rd('stability_agreement_N48_*.csv'); D = rd('stability_participants_N48_*.csv');
L(end+1) = add('Stability: MDC95 %%mean %.0f-%.0f; Spearman Cursive %.2f; within-visit ICC Cursive %.2f/%.2f', ...
    min(A.MDC95_pctOfMean), max(A.MDC95_pctOfMean), A.Spearman(5), A.ICC_withinV1(5), A.ICC_withinV2(5));
L(end+1) = add('Never beyond MDC95: %d of %d; 2+ shapes: IDs %s', sum(D.nShapesBeyondMDC95 == 0), height(D), ...
    mat2str(D.ParticipantID(D.nShapesBeyondMDC95 >= 2)'));
T = rd('tostShift_N48_*.csv');
for s = 1:5
    L(end+1) = add('TOST %-8s shift %.4f [%.4f, %.4f] (90%% %.4f..%.4f) p=%.3f equiv=%d', shapes{s}, T.Shift(s), ...
        T.CI95_Lo(s), T.CI95_Hi(s), T.CI90_Lo(s), T.CI90_Hi(s), T.P_TOST(s), T.Equivalent(s)); %#ok<AGROW>
end
C = rd('corridorStability_N48_*.csv'); C = C(C.Width == 0.05, :);
L(end+1) = add('Corridor +/-0.05 nStable95: %s', mat2str(C.nStable95'));

R = rd('pipelineRobustness_N48_*.csv'); t = R(R.ShapeType <= 4, :);
rng4 = splitapply(@(x) max(x) - min(x), t.ICC_abs, findgroups(t.ShapeType));
L(end+1) = add('Robustness: templated grid range max %.3f; dICC CIs excluding 0: %d of %d; Cursive ICC %.2f-%.2f', ...
    max(rng4), sum(R.dCI_excludes0 == 1), sum(~R.IsPrimary), min(R.ICC_abs(R.ShapeType == 5)), max(R.ICC_abs(R.ShapeType == 5)));

X = rd('exploratory_traitKinematics_N48_*.csv'); x = X(strcmp(X.Method, 'Spearman') & strcmp(X.Visit, 'Mean'), :);
ex = x(sign(x.CI_lo) == sign(x.CI_hi), :);
L(end+1) = add('Trait: %d of %d Spearman CIs exclude 0', height(ex), height(x));
for i = 1:height(ex)
    L(end+1) = add('   %s vs %s %s: %.2f [%.2f, %.2f]', ex.Trait{i}, ex.Shape{i}, ex.Outcome{i}, ex.r(i), ex.CI_lo(i), ex.CI_hi(i)); %#ok<AGROW>
end

K = rd('cohortComparison_N45vsN48_*.csv'); Z = rd('cohortReplacements_N45vsN48_*.csv'); Q = rd('cohortPermutation_N45vsN48_*.csv');
L(end+1) = add('Cohort: max |dICC| templated %.4f; class changes %d; max |z| %.2f; min Holm p %.3f', ...
    max(abs(K.DeltaICC(K.ShapeType <= 4))), sum(K.ClassChanged), max(abs([Z.z_MeanBeta; Z.z_Shift])), min(Q.P_Holm));

S.lines = L; S.tag = tag;
fprintf('%s\n', L{:});
sfx = ""; if tag ~= "", sfx = "_from" + tag; end
f = fullfile(proc, sprintf('keyNumbers_%s%s.txt', datestr(now, 'yyyymmdd_HHMMSS'), sfx));
writelines(L, f); fprintf('Saved: %s\n', f);
end

function c = kooLi(lb)
names = ["poor", "moderate", "good", "excellent"];
c = names(discretize(lb, [-Inf 0.5 0.75 0.9 Inf]));
end

function f = newest(folder, pattern, tag)
d = dir(fullfile(folder, pattern));
d = d(contains({d.name}, tag));
assert(~isempty(d), 'summariseKeyNumbers:notFound', 'No %s in %s', pattern, folder);
[~, i] = max([d.datenum]); f = d(i).name;
end
