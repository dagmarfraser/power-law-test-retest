function result = computeICCFromLongTable(data, param, allParticipants, groupVar, type)
% computeICCFromLongTable - Build a subjects x groups matrix from a long
% table and compute ICC on it
%
% Consolidates 4 near-identical wrapper functions from analysis_2025
% (computeICC31_sessions, computeICC31_visits, computeICCA1_sessions,
% computeICCA1_visits) into one, parameterised by which grouping column
% to pivot on and which ICC type to compute.
%
% INPUTS:
%   data            - long table with columns ParticipantID, {groupVar}, {param}
%   param           - column name to build the matrix from
%   allParticipants - full participant ID list (ensures consistent row order/count)
%   groupVar        - 'SessionInVisit' (within-visit, k=3) or 'Visit' (between-visit, k=2 or 3)
%   type            - 'consistency' or 'absolute' (see computeICC.m)
%
% OUTPUTS:
%   result - struct from computeICC.m (.icc, .lb, .ub, .n, .k)

groups = unique(data.(groupVar));
nGroups = length(groups);

matrix = NaN(length(allParticipants), nGroups);

for pIdx = 1:length(allParticipants)
    pID = allParticipants(pIdx);
    pData = data(data.ParticipantID == pID, :);

    for gIdx = 1:nGroups
        gRow = pData(pData.(groupVar) == groups(gIdx), :);
        if height(gRow) == 1
            matrix(pIdx, gIdx) = gRow.(param);
        end
    end
end

% Remove participants with any NaN (must have complete data across all groups)
matrix = matrix(all(~isnan(matrix), 2), :);

result = computeICC(matrix, type);

end
