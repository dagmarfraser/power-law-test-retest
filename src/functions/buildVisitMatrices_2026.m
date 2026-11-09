function [ids, X, shapeTypes] = buildVisitMatrices_2026(T, param)
% buildVisitMatrices_2026 - participant x visit matrix of visit means, per shape
%
% Shared by reportStability_2026 and diagnoseShapeStability_2026 so the
% session -> visit aggregation lives in one place (it reuses
% aggregateToSessionMeans / aggregateToVisitMeans, the same path runICC_2026
% uses).
%
% INPUTS
%   T     trial-level table (trial_level_results_*.csv)
%   param column to aggregate, e.g. 'Beta_SG6_IRLS'
%
% OUTPUTS
%   ids         sorted participant IDs (n x 1); n comes from the data
%   X           cell, X{s} = n x nVisits matrix for shapeTypes(s)
%   shapeTypes  sorted ShapeType codes present
%
% FAILS LOUDLY if a participant x visit x shape cell is missing or NaN.

assert(ismember(param, T.Properties.VariableNames), 'buildVisitMatrices_2026:noParam', 'Missing column %s', param);
vis = aggregateToVisitMeans(aggregateToSessionMeans(T, {param}), {param});
ids = unique(vis.ParticipantID); visits = unique(vis.Visit)'; shapeTypes = unique(vis.ShapeType)';
X = cell(1, numel(shapeTypes));
for s = 1:numel(shapeTypes)
    X{s} = nan(numel(ids), numel(visits));
    for v = 1:numel(visits)
        for p = 1:numel(ids)
            val = vis.(param)(vis.ParticipantID == ids(p) & vis.ShapeType == shapeTypes(s) & vis.Visit == visits(v));
            assert(isscalar(val) && ~isnan(val), 'buildVisitMatrices_2026:missingCell', ...
                'ID %d shape %d visit %d: %d values (need exactly 1, non-NaN)', ids(p), shapeTypes(s), visits(v), numel(val));
            X{s}(p,v) = val;
        end
    end
end
end
