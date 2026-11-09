function result = old_computeICCA1(data)
    [n, k] = size(data);
    grandMean = mean(data(:));
    subjectMeans = mean(data, 2);
    raterMeans = mean(data, 1);
    SST = sum((data(:) - grandMean).^2);
    SSR = k * sum((subjectMeans - grandMean).^2);
    SSC = n * sum((raterMeans - grandMean).^2);
    SSE = SST - SSR - SSC;
    MSR = SSR / (n - 1);
    MSC = SSC / (k - 1);
    MSE = SSE / ((n - 1) * (k - 1));
    icc = (MSR - MSE) / (MSR + (k - 1)*MSE + (k/n)*(MSC - MSE));
    alpha = 0.05;
    Fstar = MSR / MSE;
    df1 = n - 1; df2 = (n - 1) * (k - 1);
    vn = (k * icc * MSC / MSE + n * (1 + (k-1)*icc) - k*icc)^2;
    vd = ((k * icc * MSC / MSE)^2 / (k-1)) + (n*(1+(k-1)*icc) - k*icc)^2 / ((n-1)*(k-1));
    df_approx = vn / vd;
    if isnan(df_approx) || df_approx <= 0, df_approx = df2; end
    F_L = Fstar / finv(1 - alpha/2, df1, df_approx);
    F_U = Fstar * finv(1 - alpha/2, df_approx, df1);
    denom_L = F_L + (k-1) + (k/n)*(MSC/MSE - 1);
    denom_U = F_U + (k-1) + (k/n)*(MSC/MSE - 1);
    lb = max(-1, min(1, (F_L - 1) / denom_L));
    ub = max(-1, min(1, (F_U - 1) / denom_U));
    result = struct('icc', icc, 'lb', lb, 'ub', ub, 'n', n, 'k', k);
end
