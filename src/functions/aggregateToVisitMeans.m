function visitData = aggregateToVisitMeans(sessionData, paramList)
% aggregateToVisitMeans - Aggregate session means to visit means
%
% See aggregateToSessionMeans.m for why this is a shared function rather
% than the duplicated block it replaces.
%
% INPUTS:
%   sessionData - output of aggregateToSessionMeans
%   paramList   - cell array of column names to aggregate (mean, omitnan)
%
% OUTPUTS:
%   visitData - one row per participant x visit x shape

nShapes = 5;
participants = unique(sessionData.ParticipantID);
visitData = table();

for pIdx = 1:length(participants)
    pID = participants(pIdx);
    pData = sessionData(sessionData.ParticipantID == pID, :);

    visits = unique(pData.Visit);
    for vIdx = 1:length(visits)
        visit = visits(vIdx);
        vData = pData(pData.Visit == visit, :);

        for shapeType = 1:nShapes
            shapeData = vData(vData.ShapeType == shapeType, :);
            if height(shapeData) == 0
                continue;
            end

            row = struct();
            row.ParticipantID = pID;
            row.Visit = visit;
            row.ShapeType = shapeType;
            row.nSessions = height(shapeData);

            for paramIdx = 1:length(paramList)
                param = paramList{paramIdx};
                row.(param) = mean(shapeData.(param), 'omitnan');
            end

            visitData = [visitData; struct2table(row)]; %#ok<AGROW>
        end
    end
end

end
