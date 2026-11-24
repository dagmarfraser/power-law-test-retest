function T = compareReliabilityModels_2026(root)
%% Side-by-side: ICC(A,1), ICC(3,1) (Beta_SG6_IRLS, between visit), RM-ANCOVA CATI, Bayesian CATI.
iccF = dir(fullfile(root,'data','processed','icc_results_*.csv')); [~,i]=max([iccF.datenum]);
I = readtable(fullfile(iccF(i).folder,iccF(i).name));
I = I(strcmp(I.Parameter,'Beta_SG6_IRLS'),:);
A = dir(fullfile(root,'reports','R','regAncova_N48_*')); [~,j]=max([A.datenum]);
S = readtable(fullfile(A(j).folder,A(j).name,'CATIslope_byShape.csv'));
S = S(strcmp(S.analysis,'primary_5shapes_rawBeta'),:);
B = dir(fullfile(root,'reports','R','bayesMixedModel_N48_*')); [~,o]=sort([B.datenum]); B=B(o);
% later runs (re-fits of failed shapes) override earlier ones, shape by shape
Y = table();
for b=1:numel(B)
 y=readtable(fullfile(B(b).folder,B(b).name,'bayes_fixedEffects_N48.csv'));
 y=y(strcmp(y.Model,'main')&strcmp(y.Term,'CATI_Total_c'),:);
 if ~isempty(Y), Y=Y(~ismember(Y.Shape,y.Shape),:); end
 Y=[Y;y];
end
shapes = {'phi=0.4','phi=0.8','Ellipse','Square','Cursive'}';
T = table(shapes,'VariableNames',{'Shape'});
for n=1:5, s=shapes{n};
 a=I(strcmp(I.ShapeName,s)&strcmp(I.ICCType,'absolute'),:); c=I(strcmp(I.ShapeName,s)&strcmp(I.ICCType,'consistency'),:);
 T.ICC_A1(n)=a.ICC_BetweenVisit; T.A1_LB(n)=a.ICC_BetweenVisit_LB; T.A1_UB(n)=a.ICC_BetweenVisit_UB;
 T.ICC_31(n)=c.ICC_BetweenVisit; T.C31_LB(n)=c.ICC_BetweenVisit_LB; T.C31_UB(n)=c.ICC_BetweenVisit_UB;
 r=S(strcmp(S.ShapeName,s),:); T.ANCOVA_slope(n)=r.slope; T.ANCOVA_lo(n)=r.lower_CL; T.ANCOVA_hi(n)=r.upper_CL;
 q=Y(strcmp(Y.Shape,s),:); T.Bayes_slope(n)=q.Estimate; T.Bayes_lo(n)=q.CI_low; T.Bayes_hi(n)=q.CI_high; T.Bayes_Ppos(n)=q.P_positive;
end
out = fullfile(root,'reports',['reliabilityModelCompare_' datestr(now,'yyyymmdd_HHMMSS') '.csv']);
writetable(T,out); fprintf('Wrote %s\n',out);
end
