function s = ipadPointsPerMm()
% IPADPOINTSPERMM  UIKit points per mm for the StimuliAppUoB enhanced CSVs.
%
% Single source of truth for the trajectory scale. Raw x,y in the
% tracingSection-enhanced.csv files are UIKit POINTS, not pixels. Both the
% Pilot (analysis_2025) and Analysis_2026 data come from the same M4 13" iPad
% Pro, so both use this one constant.
%
% Derivation (Dagmar, 2 Nov 2026): 5.209 points/mm on the M4 13" iPad Pro.
% Checked two ways: a ruler on the on-screen ellipse gives ~116 x 55 mm; the
% median traced extent over 7,259 ellipse trials is 629-637 x 292-294 points,
% i.e. ~121 x 56 mm at this scale (vs 60 x 28 mm if the units were pixels).
%
% Replaces 9.73 (Pilot / Analysis_2026) and 10.418 (Fraser importer), which
% understated every mm quantity by 1.87x and 2.00x respectively.
%
% Scale-dependent outputs: velocity, acceleration, jerk (x s), PathLength_mm
% (x s), VGF (x s^(1-beta)). Beta, FitCorr, NumPoints and the ICCs on beta
% are scale-invariant (checked on 60 real trials: max |dBeta_SG6_IRLS| 1.5e-7).
s = 5.209;
end
