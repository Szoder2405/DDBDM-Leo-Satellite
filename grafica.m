%% Ploteo comparativo BER vs SNR para OFDM y DDBDM
clear; close all; clc;

% =========================================================================
% 1. CARGAR DATOS DDBDM (código original)
% =========================================================================

% Lista de archivos DDBDM
files = { ...
    'BER_sweep_results_DDBDM_CNPR_20dB.m', ...
    'BER_sweep_results_DDBDM_CNPR_10dB.m', ...
    'BER_sweep_results_DDBDM_CNPR_0dB.m' ...
};

nFiles = numel(files);

% Estructuras para almacenar datos cargados
data = struct('label',{}, 'SNRvec',{}, 'berCom',{}, 'berNav',{}, 'berSum',{}, 'type',{}, 'scheme',{}, 'cnpr',{});

% Cargar datos DDBDM
for k = 1:nFiles
    fname = files{k};
    fprintf('Procesando archivo DDBDM: %s\n', fname);
    [~, nameOnly, ext] = fileparts(fname);
    loaded = false;
    try
        matname = [nameOnly '.mat'];
        if exist(matname, 'file')
            tmp = load(matname);
            loaded = true;
            fprintf('  -> cargado %s (MAT-file)\n', matname);
        else
            if exist(fname, 'file') == 2
                run(fname);
                tmp.SNRvec = evalin('base','SNRvec');
                tmp.berCom_vs_SNR = evalin('base','berCom_vs_SNR');
                tmp.berNav_vs_SNR = evalin('base','berNav_vs_SNR');
                tmp.berSum_vs_SNR = evalin('base','berSum_vs_SNR');
                loaded = true;
                fprintf('  -> ejecutado script %s\n', fname);
            else
                error('Archivo no encontrado: %s', fname);
            end
        end
    catch ME
        warning('No se pudo cargar %s: %s', fname, ME.message);
        loaded = false;
    end

    if ~loaded
        continue;
    end

    % Normalizar nombres de variables
    if ~isfield(tmp,'SNRvec') && isfield(tmp,'SNR')
        tmp.SNRvec = tmp.SNR;
    end
    if ~isfield(tmp,'berCom_vs_SNR') && isfield(tmp,'berCom')
        tmp.berCom_vs_SNR = tmp.berCom;
    end
    if ~isfield(tmp,'berNav_vs_SNR') && isfield(tmp,'berNav')
        tmp.berNav_vs_SNR = tmp.berNav;
    end
    if ~isfield(tmp,'berSum_vs_SNR') && isfield(tmp,'berSum')
        tmp.berSum_vs_SNR = tmp.berSum;
    end

    % Verificar variables críticas
    if ~isfield(tmp,'SNRvec') || ~isfield(tmp,'berCom_vs_SNR') || ~isfield(tmp,'berNav_vs_SNR')
        warning('Archivo %s no contiene las variables esperadas. Se omite.', fname);
        continue;
    end

    % Extraer valor CNPR del nombre del archivo
    tok = regexp(nameOnly, 'CNPR_(-?\d+)dB', 'tokens', 'once');
    if ~isempty(tok)
        cnpr_value = str2double(tok{1});
        label = ['DDBDM CNPR ' tok{1} ' dB'];
    else
        cnpr_value = 0; % Valor por defecto
        label = ['DDBDM ' nameOnly];
    end

    % Guardar en estructura
    data(end+1).label = label;
    data(end).SNRvec = tmp.SNRvec(:)';
    data(end).berCom  = tmp.berCom_vs_SNR(:)';
    data(end).berNav  = tmp.berNav_vs_SNR(:)';
    if isfield(tmp,'berSum_vs_SNR')
        data(end).berSum = tmp.berSum_vs_SNR(:)';
    else
        data(end).berSum = data(end).berCom + data(end).berNav;
    end
    data(end).type = 'DDBDM'; % Marcar como DDBDM
    data(end).scheme = 'DDBDM';
    data(end).cnpr = cnpr_value;
end

% =========================================================================
% 2. CARGAR DATOS OFDM
% =========================================================================

fprintf('Cargando datos OFDM...\n');
try
    % Cargar archivo OFDM
    ofdm_data = load('OFDM_DATA.mat');
    
    % Extraer datos relevantes
    BER_com_mean = ofdm_data.BER_com_mean; % 3x5x36
    BER_nav_mean = ofdm_data.BER_nav_mean; % 3x5x36
    SNRvec = ofdm_data.SNRvec; % 1x16
    
    fprintf('Datos OFDM cargados:\n');
    fprintf('  BER_com_mean: %s\n', mat2str(size(BER_com_mean)));
    fprintf('  BER_nav_mean: %s\n', mat2str(size(BER_nav_mean)));
    fprintf('  SNRvec: %s, rango [%.1f, %.1f] dB\n', mat2str(size(SNRvec)), min(SNRvec), max(SNRvec));
    
    % Definir nombres para los esquemas OFDM
    ofdm_schemes = {'BPSK', 'QPSK', '8PSK', '16QAM', '64QAM'};
    power_schemes = {'CNPR=0dB', 'CNPR=10dB', 'CNPR=20dB'};
    cnpr_values = [0, 10, 20];
    
    % Añadir datos OFDM a la estructura
    for scheme_idx = 1:5  % 5 esquemas de modulación
        for power_idx = 1:3  % 3 esquemas de potencia
            
            % Extraer datos para este esquema específico
            ber_com = squeeze(BER_com_mean(power_idx, scheme_idx, :))';
            ber_nav = squeeze(BER_nav_mean(power_idx, scheme_idx, :))';
            
            % Crear etiqueta
            label = sprintf('OFDM %s %s', ofdm_schemes{scheme_idx}, power_schemes{power_idx});
            
            % Añadir a estructura de datos
            data(end+1).label = label;
            data(end).SNRvec = SNRvec;
            data(end).berCom = ber_com;
            data(end).berNav = ber_nav;
            data(end).berSum = ber_com + ber_nav;
            data(end).type = 'OFDM'; % Marcar como OFDM
            data(end).scheme = ofdm_schemes{scheme_idx};
            data(end).cnpr = cnpr_values(power_idx);
            
        end
    end
    
    fprintf('Se añadieron %d configuraciones OFDM\n', 5*3);
    
catch ME
    warning('Error cargando datos OFDM: %s', ME.message);
    fprintf('Continuando solo con datos DDBDM...\n');
end

% =========================================================================
% 3. LIMPIEZA DE DATOS (código original modificado)
% =========================================================================

% Verificación: al menos un dataset cargado
if isempty(data)
    error('No se cargó ningún dataset válido. Verifica nombres y variables en los archivos.');
end

mode = 'nan';   % cambia a 'cut' si prefieres eliminar las entradas

for k = 1:numel(data)
    % Asegurar vectores fila
    SNRv = data(k).SNRvec(:).';
    berC = data(k).berCom(:).';
    berN = data(k).berNav(:).';
    berS = data(k).berSum(:).';
    L = numel(SNRv);

    % Función auxiliar inline: índice último > 0 (ignorando NaN)
    lastPosIdx = @(x) find(~isnan(x) & (x>0), 1, 'last');

    % comunicaciones
    lastC = lastPosIdx(berC);
    if isempty(lastC)
        if strcmp(mode,'nan')
            berC(:) = NaN;
        else % cut
            SNRv = []; berC = [];
        end
    else
        if strcmp(mode,'nan')
            zeroTail = ( (1:L) > lastC ) & (berC == 0);
            berC(zeroTail) = NaN;
        else % cut
            SNRv = SNRv(1:lastC);
            berC = berC(1:lastC);
        end
    end

    % navegación
    lastN = lastPosIdx(berN);
    if isempty(lastN)
        if strcmp(mode,'nan')
            berN(:) = NaN;
        else
            SNRv = []; berN = [];
        end
    else
        if strcmp(mode,'nan')
            zeroTail = ( (1:L) > lastN ) & (berN == 0);
            berN(zeroTail) = NaN;
        else
            SNRv = SNRv(1:lastN);
            berN = berN(1:lastN);
        end
    end

    % suma
    lastS = lastPosIdx(berS);
    if isempty(lastS)
        if strcmp(mode,'nan')
            berS(:) = NaN;
        else
            SNRv = []; berS = [];
        end
    else
        if strcmp(mode,'nan')
            zeroTail = ( (1:L) > lastS ) & (berS == 0);
            berS(zeroTail) = NaN;
        else
            SNRv = SNRv(1:lastS);
            berS = berS(1:lastS);
        end
    end

    % Guardar cambios
    if strcmp(mode,'cut')
        lens = [numel(SNRv), numel(berC), numel(berN), numel(berS)];
        minL = min(lens);
        if minL == 0
            data(k).SNRvec = [];
            data(k).berCom = [];
            data(k).berNav = [];
            data(k).berSum = [];
            continue;
        end
        data(k).SNRvec = SNRv(1:minL);
        data(k).berCom = berC(1:minL);
        data(k).berNav = berN(1:minL);
        data(k).berSum = berS(1:minL);
    else
        data(k).SNRvec = data(k).SNRvec;
        data(k).berCom = berC;
        data(k).berNav = berN;
        data(k).berSum = berS;
    end
end

% Eliminar datasets vacíos
keepIdx = true(1,numel(data));
for k = 1:numel(data)
    if isempty(data(k).SNRvec) || isempty(data(k).berCom)
        warning('Dataset %s quedó vacío tras limpieza y será ignorado.', data(k).label);
        keepIdx(k) = false;
    end
end
data = data(keepIdx);

% Recalcular SNR_min y SNR_max
allSNR = [data.SNRvec];
if isempty(allSNR)
    error('Tras limpiar los ceros no quedan SNR válidos en ningún dataset.');
end
SNR_min = min(allSNR);
SNR_max = max(allSNR);

% Crear SNRfine (eje fino) con nuevo rango
SNRfine = linspace(SNR_min, SNR_max, 400);

% Función auxiliar: generar curva suave usando fit()
interpBER = @(SNRin, BERin, SNRfine) smoothBERfit(SNRin, BERin, SNRfine);

% =========================================================================
% 4. CONFIGURACIÓN DE PLOTEO MEJORADA
% =========================================================================

% Separar datos por tipo
ddbdm_idx = strcmp({data.type}, 'DDBDM');
ofdm_idx = strcmp({data.type}, 'OFDM');

ddbdm_data = data(ddbdm_idx);
ofdm_data = data(ofdm_idx);

fprintf('\nResumen de datos para plotear:\n');
fprintf('  DDBDM: %d configuraciones\n', sum(ddbdm_idx));
fprintf('  OFDM: %d configuraciones\n', sum(ofdm_idx));

% =========================================================================
% 5. CONFIGURACIÓN DE COLORES Y ESTILOS MEJORADA
% =========================================================================

% Colores para esquemas OFDM
ofdm_schemes = unique({ofdm_data.scheme});
n_ofdm_schemes = length(ofdm_schemes);
ofdm_colors = lines(n_ofdm_schemes); % Un color por esquema de modulación

% Color único para DDBDM (negro)
ddbdm_color = [1 0 0];

% Marcadores para CNPR
cnpr_markers = {'o', 's', '^'}; % Para CNPR 0dB, 10dB, 20dB
cnpr_values = [0, 10, 20];

% =========================================================================
% 6. FIGURAS COMPARATIVAS
% =========================================================================

%% ===== 1) Figura Comunicaciones - COMPARATIVA =====
figure('Name','BER Comunicaciones - OFDM vs DDBDM');
hold on; grid on;

% Primero plotear DDBDM - MISMO COLOR, DIFERENTES MARCADORES POR CNPR
for k = 1:numel(ddbdm_data)
    SNRv = ddbdm_data(k).SNRvec;
    berv = ddbdm_data(k).berCom;
    
    % Manejar ceros para log plot
    minpos = min(berv(berv>0));
    if isempty(minpos), minpos = 1e-6; end
    berv_safe = berv;
    berv_safe(berv_safe==0) = minpos/10;
    
    % Encontrar índice del marcador basado en CNPR
    cnpr_val = ddbdm_data(k).cnpr;
    marker_idx = find(cnpr_values == cnpr_val);
    if isempty(marker_idx), marker_idx = 1; end
    
    % Puntos originales - MISMO COLOR, DIFERENTE MARCADOR
    plot(SNRv, berv, [cnpr_markers{marker_idx}], ...
        'Color', ddbdm_color, 'LineWidth', 2, 'MarkerSize', 8, ...
        'DisplayName', ddbdm_data(k).label);
    
    % Curva suave - MISMO COLOR PARA TODOS LOS DDBDM
    smoothBer = interpBER(SNRv, berv_safe, SNRfine);
    semilogy(SNRfine, smoothBer, 'Color', ddbdm_color, ...
        'LineWidth', 2, 'LineStyle', '-');
end

% Luego plotear OFDM - COLOR POR ESQUEMA, MARCADOR POR CNPR
for k = 1:numel(ofdm_data)
    SNRv = ofdm_data(k).SNRvec;
    berv = ofdm_data(k).berCom;
    
    % Manejar ceros para log plot
    minpos = min(berv(berv>0));
    if isempty(minpos), minpos = 1e-6; end
    berv_safe = berv;
    berv_safe(berv_safe==0) = minpos/10;
    
    % Encontrar color basado en esquema de modulación
    scheme_name = ofdm_data(k).scheme;
    scheme_idx = find(strcmp(ofdm_schemes, scheme_name));
    scheme_color = ofdm_colors(scheme_idx, :);
    
    % Encontrar marcador basado en CNPR
    cnpr_val = ofdm_data(k).cnpr;
    marker_idx = find(cnpr_values == cnpr_val);
    if isempty(marker_idx), marker_idx = 1; end
    
    % Puntos originales - COLOR POR ESQUEMA, MARCADOR POR CNPR
    plot(SNRv, berv, [cnpr_markers{marker_idx}], ...
        'Color', scheme_color, 'LineWidth', 2, 'MarkerSize', 8, ...
        'DisplayName', ofdm_data(k).label);
    
    % Curva suave - COLOR POR ESQUEMA
    smoothBer = interpBER(SNRv, berv_safe, SNRfine);
    semilogy(SNRfine, smoothBer, 'Color', scheme_color, ...
        'LineWidth', 2.5, 'LineStyle', '-');
end

set(gca,'YScale','log');
xlabel('SNR (dB)'); ylabel('BER'); 
title('BER vs SNR - Comunicaciones (OFDM vs DDBDM)');
xlim([SNR_min SNR_max]); ylim([1e-6 1]);
legend('Location','southwest', 'NumColumns', 2);
grid on; hold off;

%% ===== 2) Figura Navegación - COMPARATIVA =====
figure('Name','BER Navegación - OFDM vs DDBDM');
hold on; grid on;

% Primero plotear DDBDM - MISMO COLOR, DIFERENTES MARCADORES POR CNPR
for k = 1:numel(ddbdm_data)
    SNRv = ddbdm_data(k).SNRvec;
    berv = ddbdm_data(k).berNav;
    
    minpos = min(berv(berv>0));
    if isempty(minpos), minpos = 1e-6; end
    berv_safe = berv;
    berv_safe(berv_safe==0) = minpos/10;
    
    % Encontrar índice del marcador basado en CNPR
    cnpr_val = ddbdm_data(k).cnpr;
    marker_idx = find(cnpr_values == cnpr_val);
    if isempty(marker_idx), marker_idx = 1; end
    
    % Puntos originales - MISMO COLOR, DIFERENTE MARCADOR
    plot(SNRv, berv, [cnpr_markers{marker_idx}], ...
        'Color', ddbdm_color, 'LineWidth', 2, 'MarkerSize', 8, ...
        'DisplayName', ddbdm_data(k).label);
    
    % Curva suave - MISMO COLOR PARA TODOS LOS DDBDM
    smoothBer = interpBER(SNRv, berv_safe, SNRfine);
    semilogy(SNRfine, smoothBer, 'Color', ddbdm_color, ...
        'LineWidth', 2, 'LineStyle', '-');
end

% Luego plotear OFDM - COLOR POR ESQUEMA, MARCADOR POR CNPR
for k = 1:numel(ofdm_data)
    SNRv = ofdm_data(k).SNRvec;
    berv = ofdm_data(k).berNav;
    
    minpos = min(berv(berv>0));
    if isempty(minpos), minpos = 1e-6; end
    berv_safe = berv;
    berv_safe(berv_safe==0) = minpos/10;
    
    % Encontrar color basado en esquema de modulación
    scheme_name = ofdm_data(k).scheme;
    scheme_idx = find(strcmp(ofdm_schemes, scheme_name));
    scheme_color = ofdm_colors(scheme_idx, :);
    
    % Encontrar marcadores basado en CNPR
    cnpr_val = ofdm_data(k).cnpr;
    marker_idx = find(cnpr_values == cnpr_val);
    if isempty(marker_idx), marker_idx = 1; end
    
    % Puntos originales - COLOR POR ESQUEMA, MARCADOR POR CNPR
    plot(SNRv, berv, [cnpr_markers{marker_idx}], ...
        'Color', scheme_color, 'LineWidth', 2, 'MarkerSize', 8, ...
        'DisplayName', ofdm_data(k).label);
    
    % Curva suave - COLOR POR ESQUEMA
    smoothBer = interpBER(SNRv, berv_safe, SNRfine);
    semilogy(SNRfine, smoothBer, 'Color', scheme_color, ...
        'LineWidth', 2.5, 'LineStyle', '-');
end

set(gca,'YScale','log');
xlabel('SNR (dB)'); ylabel('BER'); 
title('BER vs SNR - Navegación (OFDM vs DDBDM)');
xlim([SNR_min SNR_max]); ylim([1e-6 1]);
legend('Location','southwest', 'NumColumns', 2);
grid on; hold off;

%% ===== 3) Figura Suma - COMPARATIVA =====
figure('Name','BER Sumada - OFDM vs DDBDM');
hold on; grid on;

% Primero plotear DDBDM - MISMO COLOR, DIFERENTES MARCADORES POR CNPR
for k = 1:numel(ddbdm_data)
    SNRv = ddbdm_data(k).SNRvec;
    berv = ddbdm_data(k).berSum;
    
    minpos = min(berv(berv>0));
    if isempty(minpos), minpos = 1e-6; end
    berv_safe = berv;
    berv_safe(berv_safe==0) = minpos/10;
    
    % Encontrar índice del marcador basado en CNPR
    cnpr_val = ddbdm_data(k).cnpr;
    marker_idx = find(cnpr_values == cnpr_val);
    if isempty(marker_idx), marker_idx = 1; end
    
    % Puntos originales - MISMO COLOR, DIFERENTE MARCADOR
    plot(SNRv, berv, [cnpr_markers{marker_idx}], ...
        'Color', ddbdm_color, 'LineWidth', 2, 'MarkerSize', 8, ...
        'DisplayName', ddbdm_data(k).label);
    
    % Curva suave - MISMO COLOR PARA TODOS LOS DDBDM
    smoothBer = interpBER(SNRv, berv_safe, SNRfine);
    semilogy(SNRfine, smoothBer, 'Color', ddbdm_color, ...
        'LineWidth', 2, 'LineStyle', '-');
end

% Luego plotear OFDM - COLOR POR ESQUEMA, MARCADOR POR CNPR
for k = 1:numel(ofdm_data)
    SNRv = ofdm_data(k).SNRvec;
    berv = ofdm_data(k).berSum;
    
    minpos = min(berv(berv>0));
    if isempty(minpos), minpos = 1e-6; end
    berv_safe = berv;
    berv_safe(berv_safe==0) = minpos/10;
    
    % Encontrar color basado en esquema de modulación
    scheme_name = ofdm_data(k).scheme;
    scheme_idx = find(strcmp(ofdm_schemes, scheme_name));
    scheme_color = ofdm_colors(scheme_idx, :);
    
    % Encontrar marcadores basado en CNPR
    cnpr_val = ofdm_data(k).cnpr;
    marker_idx = find(cnpr_values == cnpr_val);
    if isempty(marker_idx), marker_idx = 1; end
    
    % Puntos originales - COLOR POR ESQUEMA, MARCADOR POR CNPR
    plot(SNRv, berv, [cnpr_markers{marker_idx}], ...
        'Color', scheme_color, 'LineWidth', 2, 'MarkerSize', 8, ...
        'DisplayName', ofdm_data(k).label);
    
    % Curva suave - COLOR POR ESQUEMA
    smoothBer = interpBER(SNRv, berv_safe, SNRfine);
    semilogy(SNRfine, smoothBer, 'Color', scheme_color, ...
        'LineWidth', 2.5, 'LineStyle', '-');
end

set(gca,'YScale','log');
xlabel('SNR (dB)'); ylabel('BER sum'); 
title('BER_{com}+BER_{nav} vs SNR (OFDM vs DDBDM)');
xlim([SNR_min SNR_max]); ylim([1e-6 1]);
legend('Location','southwest', 'NumColumns', 2);
grid on; hold off;

fprintf('\nGrágficas comparativas generadas exitosamente!\n');
fprintf('Esquema de colores y marcadores:\n');
fprintf('  DDBDM: Color negro único, marcadores: o=0dB, s=10dB, ^=20dB\n');
for i = 1:length(ofdm_schemes)
    fprintf('  OFDM %s: Color específico, marcadores: o=0dB, s=10dB, ^=20dB\n', ofdm_schemes{i});
end

%% ===== Función auxiliar local usando fit() =====
function smoothBer = smoothBERfit(SNRin, BERin, SNRfine)
    % Usa la función fit() de MATLAB para ajuste robusto con detección de ruptura
    
    SNRin = SNRin(:)';
    BERin = BERin(:)';
    
    % Filtrar datos válidos
    validIdx = ~isnan(BERin) & (BERin > 0);
    if sum(validIdx) < 3
        % Fallback a interpolación básica si no hay suficientes puntos
        smoothBer = basicInterpolation(SNRin, BERin, SNRfine);
        return;
    end
    
    SNR_valid = SNRin(validIdx);
    BER_valid = BERin(validIdx);
    
    % Convertir a escala logarítmica para el ajuste
    logBER = log10(BER_valid);
    
    try
        % Opción 1: Ajuste polinomial cúbico (suave y curvado hacia abajo)
        [fitresult, ~] = fit(SNR_valid', logBER', 'poly3', ...
            'Robust', 'Bisquare', 'Normalize', 'on');
        
        % Evaluar el ajuste
        logBER_fine = fitresult(SNRfine');
        smoothBer = 10.^logBER_fine';
        
    catch
        % Fallback a interpolación spline si fit falla
        warning('Fit polinomial falló, usando spline de respaldo');
        smoothBer = basicInterpolation(SNRin, BERin, SNRfine);
        return;
    end
    
    % Detección de ruptura de tendencia (versión simplificada)
    smoothBer = detectTrendBreakSimplified(SNRfine, smoothBer, SNR_valid, BER_valid);
end

%% Función simplificada para detección de ruptura de tendencia
function y_out = detectTrendBreakSimplified(x, y, x_orig, y_orig)
    % Detección simplificada de ruptura de tendencia
    
    y_out = y;
    
    if numel(y) < 5
        return;
    end
    
    % Calcular derivada numérica
    dy = diff(y) ./ diff(x);
    
    % Buscar donde la derivada se vuelve positiva o cero (ruptura)
    positive_slope_idx = find(dy >= -1e-8, 1); % Casi plano o positivo
    
    if ~isempty(positive_slope_idx)
        break_idx = positive_slope_idx + 1;
        
        % Verificación adicional: comparar con datos originales
        if break_idx < numel(x)
            % Si hay datos originales después del punto de ruptura, verificar
            x_break = x(break_idx);
            orig_after_break = x_orig(x_orig >= x_break);
            
            if ~isempty(orig_after_break)
                % Si hay datos originales después de la ruptura, no cortar
                return;
            end
            
            % Cortar la curva asignando NaN
            y_out(break_idx:end) = NaN;
            fprintf('Ruptura detectada en SNR = %.2f dB\n', x(break_idx));
        end
    end
    
    % Detección adicional: si la curva se aleja mucho de los datos originales
    for i = 1:numel(x)
        if i > 1 && ~isnan(y(i))
            % Buscar datos originales cercanos
            nearby_orig = find(abs(x_orig - x(i)) < 1.0); % Within 1 dB
            if ~isempty(nearby_orig)
                orig_vals = y_orig(nearby_orig);
                if y(i) > max(orig_vals) * 10 || y(i) < min(orig_vals) / 10
                    y_out(i:end) = NaN;
                    fprintf('Desviación detectada en SNR = %.2f dB\n', x(i));
                    break;
                end
            end
        end
    end
end

%% Función de interpolación básica (fallback)
function smoothBer = basicInterpolation(SNRin, BERin, SNRfine)
    % Interpolación básica de respaldo
    
    SNRin = SNRin(:)';
    BERin = BERin(:)';
    
    if numel(SNRin) < 2
        smoothBer = repmat(BERin(1), size(SNRfine));
        return;
    end
    
    % Filtrar datos válidos
    validIdx = ~isnan(BERin) & (BERin > 0);
    if sum(validIdx) < 2
        smoothBer = nan(size(SNRfine));
        return;
    end
    
    SNR_valid = SNRin(validIdx);
    BER_valid = BERin(validIdx);
    
    % Convertir a log10 y usar spline
    logBER = log10(BER_valid);
    logBER_fine = interp1(SNR_valid, logBER, SNRfine, 'spline', 'extrap');
    smoothBer = 10.^logBER_fine;
    
    % Limitar valores extremos
    minBER = min(BER_valid);
    maxBER = max(BER_valid);
    smoothBer(smoothBer < minBER/100) = minBER/100;
    smoothBer(smoothBer > maxBER*100) = maxBER*100;
end