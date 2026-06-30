ofdmFile = 'OFDM_DATA.mat';
if ~exist(ofdmFile,'file')
    warning('No se encontró %s en el directorio actual. Se omite overlay OFDM.', ofdmFile);
else
    S = load(ofdmFile);
    % Validar variables requeridas
    req = {'BER_com_mean','BER_nav_mean','SNRvec'};
    missing = setdiff(req, fieldnames(S));
    if ~isempty(missing)
        warning('OFDM file no contiene variables: %s. Se omite overlay OFDM.', strjoin(missing,', '));
    else
        % extraer SNRvec_ofdm
        SNR_ofdm = S.SNRvec(:)'; % row
        % comprobar compatibilidad con SNR de DDBDM (allSNR previamente calculado)
        % Preferir SNR_ofdm para graficar curves OFDM (son coherentes según tu mensaje)
        if exist('allSNR','var') && ~isequal(SNR_ofdm, unique(allSNR))
            warning('SNRvec de OFDM difiere del SNR usado anteriormente. Usaré SNRvec de OFDM para curves OFDM.');
        end

        % Obtener BER matrices
        BERc = S.BER_com_mean; % esperado dims: [nRatios x nMods x nSNR] (o variante)
        BERn = S.BER_nav_mean;

        % Detectar qué dimensión es la de SNR (igual a length(SNR_ofdm))
        lenSNR = length(SNR_ofdm);
        szc = size(BERc);
        sumnon1 = numel(BERc);
        % buscar index of dimension equal to lenSNR
        idxSNR_c = find(szc == lenSNR, 1);
        idxSNR_n = find(size(BERn) == lenSNR, 1);

        if isempty(idxSNR_c) || isempty(idxSNR_n)
            % No se encontró la dimensión; intentar usar variable nSNR si existe
            if isfield(S,'nSNR')
                idxSNR = S.nSNR;
                % try to reshape assuming last dim is nSNR if product matches
                % compute candidate reorder to put SNR as last dim
                % fallback: try to reshape to [3,5,nSNR] if fits
                if numel(BERc) == 3*5*lenSNR
                    BERc = reshape(BERc, 3, 5, lenSNR);
                    BERn = reshape(BERn, 3, 5, lenSNR);
                    idxSNR_c = 3; idxSNR_n = 3;
                else
                    error('No se pudo determinar la dimensión SNR en BER_com_mean/BER_nav_mean automáticamente.');
                end
            else
                error('No se pudo determinar la dimensión SNR en BER_com_mean/BER_nav_mean.');
            end
        end

        % Permutar para que la dimensión SNR quede en la tercera posición: [R x M x SNR]
        % (si ya está en 3ra, no hace nada)
        if idxSNR_c ~= 3
            perm_c = 1:ndims(BERc);
            perm_c([idxSNR_c 3]) = perm_c([3 idxSNR_c]); % swap positions
            BERc = permute(BERc, perm_c);
        end
        if idxSNR_n ~= 3
            perm_n = 1:ndims(BERn);
            perm_n([idxSNR_n 3]) = perm_n([3 idxSNR_n]);
            BERn = permute(BERn, perm_n);
        end

        % Now BERc, BERn should be at least 3-D with last dim length = lenSNR
        % If there are extra dimensions (e.g., 4-D), collapse by mean across dims>3
        if ndims(BERc) > 3
            extra_dims = 4:ndims(BERc);
            BERc = mean(BERc, extra_dims);
        end
        if ndims(BERn) > 3
            extra_dims = 4:ndims(BERn);
            BERn = mean(BERn, extra_dims);
        end

        % Final shape check
        [R_c, M_c, SNRdim_c] = size(BERc); %#ok<ASGLU>
        [R_n, M_n, SNRdim_n] = size(BERn);
        if SNRdim_c ~= lenSNR || SNRdim_n ~= lenSNR
            error('Tras reorganizar, la dimensión SNR no coincide con length(SNRvec).');
        end

        % Ahora extraer las curvas 2D: índices ratios x mods
        % Asumimos R_c = number of ratios (ej. 3) y M_c = number of mod schemes (ej. 5)
        nRatios_ofdm = R_c;
        nMods_ofdm   = M_c;

        % Preparar estilo de plot para OFDM (diferenciar de DDBDM)
        ofdmCols = lines(max(5, nMods_ofdm)); % colores por mod
        ofdmMarkers = {'+','x','*','>','<'};
        ofdmLineStyle = '--'; % dashed thinner

        % --- Crear figuras combinadas: Comunicaciones, Navegación, Suma ---
        % Preparamos leyenda adicional para OFDM: etiqueta 'OFDM R# M#'
        % For consistent overlay, we'll create new combined figures that include both DDBDM
        % curves (already in 'data') and OFDM curves.

        % Figure: Communications combined
        hCom = figure('Name','BER Comunicaciones - DDBDM vs OFDM'); hold on; grid on;
        % Plot DDBDM curves first (from 'data')
        for k = 1:numel(data)
            SNRv = data(k).SNRvec;
            berv  = data(k).berCom;
            plot(SNRv, berv, '-o', 'Color', [0.2 0.2 0.2], 'LineWidth',1, 'MarkerSize',5, 'DisplayName', data(k).label);
            % also plot smoothed DDBDM curve using existing smoothBERinterp (deg2 default)
            smoothD = smoothBERinterp(SNRv, berv, SNRfine, 2, 6);
            semilogy(SNRfine, smoothD, 'Color', [0.2 0.2 0.2], 'LineWidth',1.6, 'HandleVisibility','off');
        end

        % Plot OFDM curves (for each ratio and mod)
        legendEntries = {};
        for r = 1:nRatios_ofdm
            for m = 1:nMods_ofdm
                curve = squeeze(BERc(r,m,:)).'; % row vector length lenSNR
                % replace zeros or negatives with NaN for fitting/plot
                curve(curve<=0) = NaN;
                % Plot raw points
                plot(SNR_ofdm, curve, 'Color', ofdmCols(m,:), 'LineStyle', 'none', ...
                    'Marker', ofdmMarkers{mod(m-1,numel(ofdmMarkers))+1}, 'MarkerSize',5, ...
                    'DisplayName', sprintf('OFDM R%d M%d (pts)', r, m));
                % Fit/regress-smoothed curve using existing smoothBERinterp (degree 2, K_tail)
                smoothOFDM = smoothBERinterp(SNR_ofdm, curve, SNRfine, 2, 6);
                semilogy(SNRfine, smoothOFDM, 'Color', ofdmCols(m,:), 'LineStyle', ofdmLineStyle, ...
                    'LineWidth', 1.4, 'DisplayName', sprintf('OFDM R%d M%d', r, m));
                legendEntries{end+1} = sprintf('OFDM R%d M%d', r, m); %#ok<SAGROW>
            end
        end
        set(gca,'YScale','log');
        xlabel('SNR (dB)'); ylabel('BER'); title('BER Comunicaciones: DDBDM (gray) vs OFDM (colored)');
        xlim([min(SNR_ofdm) max(SNR_ofdm)]);
        ylim([1e-12 1]);
        legend('Location','southwestoutside','NumColumns',1);
        hold off;

        % Figure: Navigation combined
        hNav = figure('Name','BER Navegación - DDBDM vs OFDM'); hold on; grid on;
        for k = 1:numel(data)
            SNRv = data(k).SNRvec;
            berv  = data(k).berNav;
            plot(SNRv, berv, '-o', 'Color', [0.2 0.2 0.2], 'LineWidth',1, 'MarkerSize',5, 'DisplayName', data(k).label);
            smoothD = smoothBERinterp(SNRv, berv, SNRfine, 2, 6);
            semilogy(SNRfine, smoothD, 'Color', [0.2 0.2 0.2], 'LineWidth',1.6, 'HandleVisibility','off');
        end
        % OFDM nav curves
        for r = 1:nRatios_ofdm
            for m = 1:nMods_ofdm
                curve = squeeze(BERn(r,m,:)).';
                curve(curve<=0) = NaN;
                plot(SNR_ofdm, curve, 'Color', ofdmCols(m,:), 'LineStyle','none', ...
                    'Marker', ofdmMarkers{mod(m-1,numel(ofdmMarkers))+1}, 'MarkerSize',5, ...
                    'DisplayName', sprintf('OFDM R%d M%d (pts)', r, m));
                smoothOFDM = smoothBERinterp(SNR_ofdm, curve, SNRfine, 2, 6);
                semilogy(SNRfine, smoothOFDM, 'Color', ofdmCols(m,:), 'LineStyle', ofdmLineStyle, ...
                    'LineWidth', 1.4, 'DisplayName', sprintf('OFDM R%d M%d', r, m));
            end
        end
        set(gca,'YScale','log');
        xlabel('SNR (dB)'); ylabel('BER'); title('BER Navegación: DDBDM (gray) vs OFDM (colored)');
        xlim([min(SNR_ofdm) max(SNR_ofdm)]);
        ylim([1e-12 1]);
        legend('Location','southwestoutside','NumColumns',1);
        hold off;

        % Figure: Sum combined (com + nav)
        hSum = figure('Name','BER Sumada - DDBDM vs OFDM'); hold on; grid on;
        for k = 1:numel(data)
            SNRv = data(k).SNRvec;
            berv  = data(k).berSum;
            plot(SNRv, berv, '-o', 'Color', [0.2 0.2 0.2], 'LineWidth',1, 'MarkerSize',5, 'DisplayName', data(k).label);
            smoothD = smoothBERinterp(SNRv, berv, SNRfine, 2, 6);
            semilogy(SNRfine, smoothD, 'Color', [0.2 0.2 0.2], 'LineWidth',1.6, 'HandleVisibility','off');
        end
        for r = 1:nRatios_ofdm
            for m = 1:nMods_ofdm
                curve_com = squeeze(BERc(r,m,:)).';
                curve_nav = squeeze(BERn(r,m,:)).';
                curve_sum = curve_com + curve_nav;
                curve_sum(curve_sum<=0) = NaN;
                plot(SNR_ofdm, curve_sum, 'Color', ofdmCols(m,:), 'LineStyle','none', ...
                    'Marker', ofdmMarkers{mod(m-1,numel(ofdmMarkers))+1}, 'MarkerSize',5, ...
                    'DisplayName', sprintf('OFDM R%d M%d (pts)', r, m));
                smoothOFDM_sum = smoothBERinterp(SNR_ofdm, curve_sum, SNRfine, 2, 6);
                semilogy(SNRfine, smoothOFDM_sum, 'Color', ofdmCols(m,:), 'LineStyle', ofdmLineStyle, ...
                    'LineWidth', 1.4, 'DisplayName', sprintf('OFDM R%d M%d', r, m));
            end
        end
        set(gca,'YScale','log');
        xlabel('SNR (dB)'); ylabel('BER sum'); title('BER_{com}+BER_{nav}: DDBDM (gray) vs OFDM (colored)');
        xlim([min(SNR_ofdm) max(SNR_ofdm)]);
        ylim([1e-12 1]);
        legend('Location','southwestoutside','NumColumns',1);
        hold off;

        % Optional: bring figures to front
        figure(hCom); figure(hNav); figure(hSum);

        fprintf('Overlay OFDM results completado. Plots creados: %s, %s, %s\n', hCom.Name, hNav.Name, hSum.Name);
    end
end