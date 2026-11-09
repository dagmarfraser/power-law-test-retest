function result = old_computeICC31(data)
    [n, k] = size(data);
    grandMean = mean(data(:));
    subjectMeans = mean(data, 2);
    raterMeans = mean(data, 1);
    SST = sum((data(:) - grandMean).^2);
    SSR = k * sum((subjectMeans - grandMean).^2);
    SSC = n * sum((raterMeans - grandMean).^2);
    SSE = SST - SSR - SSC;
    MSR = SSR / (n - 1);
    MSE = SSE / ((n - 1) * (k - 1));
    icc = (MSR - MSE) / (MSR + (k - 1) * MSE);
    alpha = 0.05;
    F = MSR / MSE;
    df1 = n - 1; df2 = (n - 1) * (k - 1);
    F_L = F / finv(1 - alpha/2, df1, df2);
    F_U = F * finv(1 - alpha/2, df2, df1);
    lb = (F_L - 1) / (F_L + k - 1);
    ub = (F_U - 1) / (F_U + k - 1);
    result = struct('icc', icc, 'lb', lb, 'ub', ub, 'n', n, 'k', k);
end
