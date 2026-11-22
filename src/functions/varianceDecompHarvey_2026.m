function out = varianceDecompHarvey_2026(root)
%VARIANCEDECOMPHARVEY_2026 MATLAB reproduction of Harvey Neal's lmer model (HarveyR, 17 Nov 2026).
%   Beta_SG6_IRLS ~ Visit + (1|PID) + (1|PID:Visit) + (1|PID:Session), per shape, all 5 shapes,
%   plus the CATI main-effect model. Review aid only; does not touch Harvey's files.
%   root = '.../MSc Analysis' (folder holding handover/ and Analysis_2026/).
t = readtable(fullfile(root,'handover','StudentDataset_2026_SG6IRLS_20261109_113130.csv'));
q = readtable(fullfile(root,'Analysis_2026','data','processed','questionnaires_CATI_MEDL_N48_20261109_113503.csv'));
t = outerjoin(t, q(:,{'ParticipantID','CATI_Total'}),'Keys','ParticipantID','MergeKeys',true,'Type','left');
assert(~any(isnan(t.CATI_Total)), 'varianceDecompHarvey_2026:CATI', 'CATI missing for some trials');
assert(numel(unique(t.ParticipantID))==48, 'varianceDecompHarvey_2026:N', 'Expected N=48');
t.PID = categorical(t.ParticipantID); t.Vis = categorical(t.Visit);
t.PV  = categorical(compose("%d_%d", t.ParticipantID, t.Visit));
t.PS  = categorical(compose("%d_%d", t.ParticipantID, t.Session)); % Session is 1-6 overall
out = table();
for s = ["phi=0.4","phi=0.8","Ellipse","Square","Cursive"]
    d  = t(t.ShapeName==s & ~isnan(t.Beta_SG6_IRLS),:);
    pc = unique(d(:,{'ParticipantID','CATI_Total'}));
    d.CATI_c = d.CATI_Total - mean(pc.CATI_Total);
    m0 = fitlme(d,'Beta_SG6_IRLS ~ Vis + (1|PID) + (1|PV) + (1|PS)','FitMethod','REML');   % REML = lmer default
    m1 = fitlme(d,'Beta_SG6_IRLS ~ Vis + CATI_c + (1|PID) + (1|PV) + (1|PS)','FitMethod','REML');   % REML = lmer default
    [psi,mse] = covarianceParameters(m0);
    v  = [psi{1} psi{2} psi{3} mse];   % person, person x visit, person x session, trial
    nT = height(d)/(48*2);             % trials per visit
    rel = v(1)/(v(1)+v(2)+v(3)/3+v(4)/nT);   % implied reliability of a visit mean
    cf = m1.Coefficients; iC = strcmp(cf.Name,'CATI_c'); iV = strcmp(cf.Name,'Vis_2');
    out = [out; table(s,height(d),v(1)/sum(v),v(2)/sum(v),v(3)/sum(v),v(4)/sum(v),rel, ...
        cf.Estimate(iV),cf.pValue(iV),10*cf.Estimate(iC),cf.pValue(iC), ...
        'VariableNames',{'Shape','nTrials','Person','PxVisit','PxSession','Trial', ...
        'RelVisitMean','VisitEff','pVisit','CATIper10','pCATI'})]; %#ok<AGROW>
end
end
