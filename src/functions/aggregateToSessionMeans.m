function sessionData = aggregateToSessionMeans(allResults, paramList)
% aggregateToSessionMeans - Aggregate trial-level results to session means
%
% Consolidates the identical aggregation block that was duplicated
% verbatim between analysis_2025's runICC_2025.m and
% runICC_2025_AbsAgree.m (one copy each, kept manually in sync -- flagged
% in analysis_2025/README_TestRetest.md Known Issues as the exact
% duplication pattern to avoid in the next generation).
%
% INPUTS:
%   allResults - trial-level table (ParticipantID, Session, Visit,
%                SessionInVisit, ShapeType, and one column per entry in paramList)
%   paramList  - cell array of column names to aggregate (mean, omitnan)
%
% OUTPUTS:
%   sessionData - one row per participant x session x shape, with mean
%                 of each param plus {param}_nValid (count of non-NaN trials)

nShapes = 5;
participants = unique(allResults.ParticipantID);
sessionData = table();

for pIdx = 1:length(participants)
    pID = participants(pIdx);
    pData = allResults(allResults.ParticipantID == pID, :);

    sessions = unique(pData.Session);
    for sIdx = 1:length(sessions)
        sess = sessions(sIdx);
        sData = pData(pData.Session == sess, :);

        visit = sData.Visit(1);
        sessionInVisit = sData.SessionInVisit(1);

        for shapeType = 1:nShapes
            shapeData = sData(sData.ShapeType == shapeType, :);
            if height(shapeData) == 0
                continue;
            end

            row = struct();
            row.ParticipantID = pID;
            row.Session = sess;
            row.Visit = visit;
            row.SessionInVisit = sessionInVisit;
            row.ShapeType = shapeType;
            row.nTrials = height(shapeData);

            for paramIdx = 1:length(paramList)
                param = paramList{paramIdx};
                row.(param) = mean(shapeData.(param), 'omitnan');
                row.([param '_nValid']) = sum(~isnan(shapeData.(param)));
            end

            sessionData = [sessionData; struct2table(row)]; %#ok<AGROW>
        end
    end
end

end
