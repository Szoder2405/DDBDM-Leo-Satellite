%% Barrido BER vs SNR para DDBDM (OTFS + piloto + LMMSE)
% - Resultados: berCom_vs_SNR, berNav_vs_SNR, berSum_vs_SNR
% Requiere: helperOTFSmod, helperOTFSdemod, getG (definidos abajo o en path), dopplerChannel
clear; close all; clc;
rng(0); % reproducible

%% ====== Parámetros del sistema ======
M = 256;           % subcarriers (delay bins)
N = 16;            % subsymbols / frame (Doppler bins)
df = 120e3;
fc = 20e9;
padLen = 140;
padType = 'ZP';

% DDBDM partition
Mn = 110;
Mc = 110;
Mp = M - (Mn + Mc);
if Mp < 0, error('Mn + Mc must be <= M'); end
start_com = Mn + Mp + 1;

% CNPR (potencia comunicación / navegación)
CNPRdB = 0;
Pn = 1;
Pc = Pn * 10^(CNPRdB/10);

% Canal (ejemplo)
chanParams.pathDelays   = [0 0 ceil((1.4824e-6)*M*df)];
chanParams.pathGains    = [10^(-0.394/10) 10^(-10.618/10) 10^(-23.373/10)];
chanParams.pathDopplers = [0, -3, 5];
fsamp = M * df;
Meff = M + padLen;
numSamps = Meff * N;
T = ((M + padLen) / (M * df));
chanParams.pathDopplerFreqs = chanParams.pathDopplers * 1/(N*T);

% Piloto para sounding (misma ubicación que usaste)
pilotBin = floor(N/2) + 1;
Pdd = zeros(M, N);
Pdd(1, pilotBin) = exp(1i * pi/4);

% Constantes QPSK usadas para definir energía de símbolo referencia
EsQPSK = mean(abs(pskmod(0:3,4,pi/4)).^2);

% Barrido SNR
SNRvec = 5:1:30;            % dB
nSNR = length(SNRvec);

% Reservar vectores BER
berCom_vs_SNR = zeros(1, nSNR);
berNav_vs_SNR = zeros(1, nSNR);
berSum_vs_SNR = zeros(1, nSNR);

% Parámetros de prueba (misma trama para cada SNR pero PRN y datos regenerados por reproducibilidad)
% Generar datos fijos para todas las SNR para comparar directemente
prnSeq = 2*randi([0 1], Mn*N, 1) - 1;    % ±1 PRN
navBits = randi([0 1], Mn*N, 1);
navSymbolsBits = 2*navBits - 1;
navChips = navSymbolsBits .* prnSeq;
Xnav_template = reshape(navChips, Mn, N);

comSymbolsInt = randi([0 3], Mc*N, 1);
Xcom_vec_template = pskmod(comSymbolsInt, 4, pi/4, InputType="integer");
Xcom_template = reshape(Xcom_vec_template, Mc, N);

% Umbral para detección de caminos a partir de Hdd
threshold = 0.05;

%% ====== Bucle principal sobre SNR con parfor en las repeticiones (Monte-Carlo) ======
fprintf('Iniciando barrido SNR con parfor (Monte-Carlo)\n');

% Parámetros de Monte-Carlo
nIter = 2;               % número de repeticiones por SNR (ajusta)
SNRvec = -5:1:30;
nSNR = length(SNRvec);

% Prealocar resultados finales
berCom_vs_SNR = zeros(1, nSNR);
berNav_vs_SNR = zeros(1, nSNR);
berSum_vs_SNR = zeros(1, nSNR);
berCom_std = zeros(1, nSNR);
berNav_std = zeros(1, nSNR);

% Abrir pool paralelo si no existe (opcional)
p = gcp('nocreate');
if isempty(p)
    try
        parpool; % abre el pool con el valor por defecto de workers
    catch ME
        warning('No se pudo iniciar parpool automáticamente: %s\nSe continuará en modo secuencial.', ME.message);
    end
end

% Repeticiones por SNR con parfor en it
for idxS = 1:nSNR
    SNRdB = SNRvec(idxS);
    fprintf('SNR = %3.1f dB  (%d/%d)\n', SNRdB, idxS, nSNR);
    n0 = EsQPSK / (10^(SNRdB/10));  % ruido para LMMSE

    % Vectores de salida por iteración (sliced variables aceptadas por parfor)
    berCom_iter = zeros(1, nIter);
    berNav_iter = zeros(1, nIter);

    % parfor: cada iteración es independiente -> safe
    % parfor: cada iteración es independiente -> safe
    parfor it = 1:nIter
        % --- Generar datos frescos por iteración (local) ---
        prnSeq_it = 2*randi([0 1], Mn*N, 1) - 1;   % PRN local
        navBits_it = randi([0 1], Mn*N, 1);
        navChips_it = (2*navBits_it - 1) .* prnSeq_it;
        Xnav_it = reshape(navChips_it, Mn, N);

        comSymbolsInt_it = randi([0 3], Mc*N, 1);
        Xcom_vec_it = pskmod(comSymbolsInt_it, 4, pi/4, InputType="integer");
        Xcom_it = reshape(Xcom_vec_it, Mc, N);

        % Escalamiento de potencias (local)
        Xnav_it = sqrt(Pn) * Xnav_it;
        Xcom_it = sqrt(Pc) * Xcom_it;
        Xdd_it = zeros(M, N);
        Xdd_it(1:Mn, :) = Xnav_it;
        Xdd_it(start_com : start_com + Mc - 1, :) = Xcom_it;

        % --- Sounding: piloto transmitido y estimación Hdd (local) ---
        txPilot = helperOTFSmod(Pdd, padLen, padType);
        dopplerPilotOut = dopplerChannel(txPilot, fsamp, chanParams);
        rxPilotNoisy = awgn(dopplerPilotOut, SNRdB, 'measured');
        rxPilotWindow = rxPilotNoisy(1:numSamps);
        Ydd_pilot = helperOTFSdemod(rxPilotWindow, M, padLen, 0, padType);
        Hdd_it = Ydd_pilot * conj(Pdd(1,pilotBin)) / (abs(Pdd(1,pilotBin))^2 + n0);

        % --- Inicializar la estructura chanEst_local de forma explícita ---
        chanEst_local = struct('pathGains',[],'pathDelays',[],'pathDopplers',[]);

        % Detectar paths y rellenar arrays temporales
        [lp_it, vp_it] = find(abs(Hdd_it) >= threshold);
        if isempty(lp_it)
            % Guardar una estimación muy débil para evitar G vacía
            chanEst_local.pathGains = 1e-6;
            chanEst_local.pathDelays = 0;
            chanEst_local.pathDopplers = 0;
        else
            idx_it = sub2ind(size(Hdd_it), lp_it, vp_it);
            % Asignar a los campos de la estructura local
            chanEst_local.pathGains    = Hdd_it(idx_it);
            chanEst_local.pathDelays   = lp_it - 1;
            chanEst_local.pathDopplers = vp_it - pilotBin;
        end

        % --- Transmitir trama de datos por el canal (local) ---
        txData = helperOTFSmod(Xdd_it, padLen, padType);
        dopplerDataOut = dopplerChannel(txData, fsamp, chanParams);
        chOut = awgn(dopplerDataOut, SNRdB, 'measured');
        rxWindow = chOut(1:numSamps);

        % --- Igualación LMMSE local usando chanEst_local ---
        G_local = getG(M, N, chanEst_local, padLen, padType);
        if isempty(G_local) || all(G_local(:)==0)
            Xhat_otfs = helperOTFSdemod(rxWindow, M, padLen, 0, padType);
        else
            A_local = (G_local' * G_local) + n0 * eye(size(G_local,2));
            b_local = G_local' * rxWindow;
            y_otfs_local = A_local \ b_local;
            Xhat_otfs = helperOTFSdemod(y_otfs_local, M, padLen, 0, padType);
        end

        % --- Separación y decisiones (local) ---
        Xhat_nav = Xhat_otfs(1:Mn, :);
        Xhat_com = Xhat_otfs(start_com : start_com + Mc - 1, :);

        % Navegación: despreading con PRN local
        Xhat_nav_vec = Xhat_nav(:);
        despread_chips_hat = Xhat_nav_vec .* conj(prnSeq_it);
        navBitsHat_logic = real(despread_chips_hat) > 0;
        navBitsHat = double(navBitsHat_logic);
        [~, berNav_it] = biterr(navBits_it, navBitsHat);

        % Comunicaciones: demodulación QPSK
        Xhat_com_vec = Xhat_com(:);
        comBitsHat = pskdemod(Xhat_com_vec, 4, pi/4, OutputType="bit", OutputDataType="logical");
        comBitsTx = de2bi(comSymbolsInt_it, 2, 'left-msb')';
        comBitsTx = comBitsTx(:);
        comBitsHatVec = double(comBitsHat(:));
        minLen_local = min(length(comBitsTx), length(comBitsHatVec));
        [~, berCom_it] = biterr(comBitsTx(1:minLen_local), comBitsHatVec(1:minLen_local));

        % Escribir resultados en variables sliced (aceptadas por parfor)
        berNav_iter(it) = berNav_it;
        berCom_iter(it) = berCom_it;
    end % parfor it

    % Estadísticos por SNR (promedio y std)
    berNav_vs_SNR(idxS) = mean(berNav_iter);
    berCom_vs_SNR(idxS) = mean(berCom_iter);
    berNav_std(idxS) = std(berNav_iter);
    berCom_std(idxS) = std(berCom_iter);
    berSum_vs_SNR(idxS) = berNav_vs_SNR(idxS) + berCom_vs_SNR(idxS);

    fprintf('\tPROMEDIO: BER_COM = %.3e (std=%.2e), BER_NAV = %.3e (std=%.2e)\n', ...
        berCom_vs_SNR(idxS), berCom_std(idxS), berNav_vs_SNR(idxS), berNav_std(idxS));
end

% Graficar resultados (igual que antes)
figure; errorbar(SNRvec, berCom_vs_SNR, berCom_std, 'LineWidth', 1.3); set(gca,'YScale','log'); grid on;
xlabel('SNR (dB)'); ylabel('BER'); title('BER Comunicaciones (QPSK) - media \pm std');

figure; errorbar(SNRvec, berNav_vs_SNR, berNav_std, 'LineWidth', 1.3); set(gca,'YScale','log'); grid on;
xlabel('SNR (dB)'); ylabel('BER'); title('BER Navegación (BPSK) - media \pm std');

figure; semilogy(SNRvec, berSum_vs_SNR, 'LineWidth', 1.6); grid on; xlabel('SNR (dB)'); ylabel('BER_{sum}');
title('BER suma (comunicaciones + navegación)');



%% ====== Guardar datos (opcional) ======
save('BER_sweep_results_cnpr_0db.mat','SNRvec','berCom_vs_SNR','berNav_vs_SNR','berSum_vs_SNR');





function G = getG(M,N,chanParams,padLen,padType)
% getG  Construye la matriz de canal en dominio tiempo para OTFS (robusta ante CP insuficiente).
%   G = getG(M,N,chanParams,padLen,padType)
%
% - Para ZP: se asume lmax = padLen (retardos fuera de padLen se descartan).
% - Para CP: se permite lmax = max(pathDelays) (se emite warning si padLen < lmax porque hay ISI).
%
% chanParams must contain fields:
%   pathDelays (vector), pathGains (vector), pathDopplers (vector)
%
% Notas: los pathDelays deben estar en unidades de muestras (enteros). Si vienen en otra unidad,
% conviértelos antes de llamar a getG.

    % ---- Preparación y saneamiento ----
    if ~isfield(chanParams,'pathDelays') || isempty(chanParams.pathDelays)
        warning('getG:NoDelays','chanParams.pathDelays vacío o ausente. Devuelvo G=zeros.');
        Meff = M + padLen;
        MN = Meff * N;
        G = zeros(MN, MN);
        return;
    end

    % Asegurar vectores columna y longitudes consistentes
    delays = chanParams.pathDelays(:);
    if isfield(chanParams,'pathGains'), gains = chanParams.pathGains(:); else gains = zeros(size(delays)); end
    if isfield(chanParams,'pathDopplers'), dopplers = chanParams.pathDopplers(:); else dopplers = zeros(size(delays)); end

    % Forzar enteros y no-negativos (si vienen con fracciones)
    delays = round(delays);
    delays(delays < 0) = 0;

    % Decide Meff y lmax según padType
    Meff = M + padLen;  % siempre se usa esta definición para el tamaño de símbolo con padding
    if strcmpi(padType,'ZP')
        lmax = padLen;
    elseif strcmpi(padType,'CP')
        % Para CP: dimensionar g para cubrir todos los delays detectados.
        lmax = max(delays);
        if lmax > padLen
            warning('getG:CP_insufficient', ...
                'padLen (%d) < max(pathDelays) (%d). El CP es insuficiente: habrá ISI y pérdida de circularidad. Se construirá G considerando los delays reales.', ...
                padLen, lmax);
        end
    else
        % Otros: tomar lmax según maximum de delays
        lmax = max(delays);
    end

    % Definir tamaños
    MN = Meff * N;
    P = numel(delays);

    % Evitar delays absurdos mayores o iguales a MN (no tiene sentido indexar)
    tooLarge = delays >= MN;
    if any(tooLarge)
        warning('getG:DelaysTooLarge','Se descartaron %d delay(s) >= MN (%d).', sum(tooLarge), MN);
        delays(tooLarge) = []; gains(tooLarge) = []; dopplers(tooLarge) = [];
        if isempty(delays)
            G = zeros(MN, MN);
            return;
        end
        lmax = max(lmax, max(delays)); % recomputar por si cambió
    end

    % Inicializa g: filas = 0..lmax, columnas = 0..MN-1
    g = zeros(lmax+1, MN);

    % ---- Acumulación de contribuciones de cada path (solo paths válidos) ----
    nvec = 0:(MN-1);
    for p = 1:numel(delays)
        lp = delays(p);
        % comprobar rango
        if lp > lmax || lp < 0
            continue; % debería no ocurrir por saneamiento previo
        end
        gp = gains(p);
        vp = dopplers(p);

        % vector de fase y ganancia para ese retardo
        % uso la misma fórmula que en tu versión original
        phaseVec = exp(1i * 2*pi/MN * vp .* (nvec - lp));
        g(lp+1, :) = g(lp+1, :) + gp .* phaseVec;
    end

    % ---- Construcción de la matriz G (MN x MN) sumando diagonales desplazadas ----
    G = zeros(MN, MN);

    uniqueDelays = unique(delays);
    for l = uniqueDelays.'
        if l < 0
            continue;
        end
        startIdx = l + 1;
        if startIdx > size(g,1)
            % no hay fila correspondiente (por seguridad)
            continue;
        end
        vec = g(startIdx, startIdx:end); % longitud MN - l
        if isempty(vec)
            continue;
        end
        % diag(vec,-l) coloca el vector en la diagonal desplazada -l (hacia abajo)
        G = G + diag(vec, -l);
    end

    % Nota: si padType es 'CP' y padLen < max(delay) -> G modela ISI (no circularidad).
end

function y = dopplerChannel(x,fs,chanParams)
    % Form an output vector y comprising paths of x with different
    % delays, Dopplers, and complex gains
    numPaths = length(chanParams.pathDelays);
    maxPathDelay = max(chanParams.pathDelays);
    txOutSize = length(x);

    y = zeros(txOutSize+maxPathDelay,1);

    for k = 1:numPaths
        pathOut = zeros(txOutSize+maxPathDelay,1);

        % Doppler
        pathShift = frequencyOffset(x,fs,chanParams.pathDopplerFreqs(k));

        % Delay and gain
        pathOut(1+chanParams.pathDelays(k):chanParams.pathDelays(k)+txOutSize) = ...
            pathShift * chanParams.pathGains(k);

        y = y + pathOut;
    end
end
