%% OFDM Nav+Com: 110 Nav / 36 padding / 110 Com, Pcom/Pnav = [0,10,20] dB
clear; close all; clc;
rng('default');

% ========== PARÁMETROS BASE CONTROLABLES ==========
M = 256;                    % Número de subcarriers
Nsym = 16;                  % Número de símbolos
cpLen = 140;                 % Longitud del prefijo cíclico
df = 120e3;                 % Espaciado entre subcarriers (Hz) - PARÁMETRO CONTROLABLE
fc = 20e9;                  % Frecuencia del carrier (Hz) - PARÁMETRO CONTROLABLE

% ========== CÁLCULOS DERIVADOS ==========
fs = M * df;                % Frecuencia de muestreo (Hz)
T_symbol = 1/df;            % Duración del símbolo OFDM (s)
T_cp = cpLen/fs;            % Duración del prefijo cíclico (s)
T_total = T_symbol + T_cp;  % Duración total del símbolo OFDM + CP (s)

SNRvec = -5:1:30;
nSNR = numel(SNRvec);
nIter = 50;

% ========== PARÁMETROS DEL CANAL (actualizados para usar fc) ==========
% Los retardos en segundos (convertidos a muestras en la simulación)
chanParams.pathDelays   = [0 0 ceil((1.4824e-6)*M*df)]; % Retardos en segundos
chanParams.pathGains    = [10^(-0.394/10) 10^(-10.618/10) 10^(-23.373/10)];

chanParams.pathGains  = [1, 0.6*exp(1i*0.1), 0.3*exp(-1i*0.3)];

% Los Doppler pueden definirse como antes o en relación con fc
% Opción 1: Doppler absoluto (Hz)
chanParams.pathDopplers = [0, -3, 5];
chanParams.pathDopplerFreqs = chanParams.pathDopplers * 1/(Nsym*T_total);

% Opción 2: Doppler relativo a fc (para movilidad)
% velocities = [30, -18, 48]; % m/s
% c = 3e8; % velocidad de la luz
% chanParams.pathDopplerFreqs = (velocities/c) * fc;

% ========== LISTA DE MODULACIONES (AHORA PARA AMBOS: NAV & COM) ==========
modList = {
    struct('name','BPSK','type','PSK','M',2);
    struct('name','QPSK','type','PSK','M',4);
    struct('name','8PSK','type','PSK','M',8);
    struct('name','16QAM','type','QAM','M',16);
    struct('name','64QAM','type','QAM','M',64);
};
nMods = numel(modList);

% ELIMINADO: modNav fijo - ahora ambos usan la misma modulación

navIdx = 1:110;
padIdx = 111:146;
comIdx = 147:256;

ratio_dB = [0, 10, 20];
nRatios = numel(ratio_dB);

% ========== ACTUALIZACIÓN DE VARIABLES BER ==========
% Ahora BER_nav también depende del esquema de modulación
BER_com_mean   = zeros(nRatios, nMods, nSNR);
BER_com_std    = zeros(nRatios, nMods, nSNR);
BER_nav_mean   = zeros(nRatios, nMods, nSNR);  % Cambiado: ahora tiene dimensión nMods
BER_nav_std    = zeros(nRatios, nMods, nSNR);  % Cambiado: ahora tiene dimensión nMods

BER_total_mean = zeros(nRatios, nMods, nSNR);
BER_total_std  = zeros(nRatios, nMods, nSNR);

maxDelay = max(chanParams.pathDelays);
Lh = maxDelay + 1;

fprintf('Configuración OFDM:\n');
fprintf('  Subcarriers: %d\n', M);
fprintf('  Δf: %.1f kHz\n', df/1e3);
fprintf('  fc: %.2f GHz\n', fc/1e9);
fprintf('  fs: %.2f MHz\n', fs/1e6);
fprintf('  T_symbol: %.2f μs\n', T_symbol*1e6);
fprintf('  T_cp: %.2f μs\n', T_cp*1e6);
fprintf('  Retardos: %s muestras\n', mat2str(chanParams.pathDelays));

p = gcp('nocreate');
if isempty(p), try parpool; end, end

for ir = 1:nRatios
    dBr = ratio_dB(ir);
    ratio_lin = 10^(dBr/10);
    P_nav = 1/(1+ratio_lin);
    P_com = ratio_lin/(1+ratio_lin);

    for im = 1:nMods
        modSpec = modList{im};  % MISMA MODULACIÓN PARA NAVEGACIÓN Y COMUNICACIONES

        for iS = 1:nSNR
            SNRdB = SNRvec(iS);

            bers_com_iter = zeros(1, nIter);
            bers_nav_iter = zeros(1, nIter);

            parfor it = 1:nIter
                % MISMO ESQUEMA PARA AMBOS
                k_com = log2(modSpec.M);
                k_nav = log2(modSpec.M);  % Ahora usa modSpec en lugar de modNav

                nComSymbols = numel(comIdx) * Nsym;
                nNavSymbols = numel(navIdx) * Nsym;

                bits_com = randi([0 1], nComSymbols*k_com, 1);
                bits_nav = randi([0 1], nNavSymbols*k_nav, 1);

                % MISMA MODULACIÓN PARA AMBOS
                symbols_com = modMap(bits_com, modSpec);
                symbols_nav = modMap(bits_nav, modSpec);  % Usa modSpec

                symbols_com = reshape(symbols_com, numel(comIdx), Nsym);
                symbols_nav = reshape(symbols_nav, numel(navIdx), Nsym);

                X_nav = zeros(M, Nsym);
                X_com = zeros(M, Nsym);

                X_nav(navIdx,:) = symbols_nav;
                X_com(comIdx,:) = symbols_com;

                txNav = [];
                txCom = [];

                for col = 1:Nsym
                    x1 = ifft(X_nav(:,col), M);
                    x1 = [x1(end-cpLen+1:end); x1];
                    txNav = [txNav; x1];

                    x2 = ifft(X_com(:,col), M);
                    x2 = [x2(end-cpLen+1:end); x2];
                    txCom = [txCom; x2];
                end

                tx = sqrt(P_nav)*txNav + sqrt(P_com)*txCom;

                Nt = length(tx);
                
                % ========== TIEMPO BASE CON fs ACTUALIZADA ==========
                t = (0:Nt-1).' / fs;  % Usando fs calculada desde df
                
                rx = zeros(Nt + maxDelay, 1);

                for pidx = 1:numel(chanParams.pathDelays)
                    d = chanParams.pathDelays(pidx);
                    g = chanParams.pathGains(pidx);
                    fd = chanParams.pathDopplerFreqs(pidx);

                    dop = exp(1i*2*pi*fd*t);
                    sig = tx .* dop * g;

                    idx = (1:Nt) + d;
                    rx(idx) = rx(idx) + sig;
                end

                rx = rx(1:Nt);

                P = mean(abs(tx).^2);
                noise = sqrt(P*10^(-SNRdB/10)/2)*(randn(Nt,1)+1i*randn(Nt,1));
                rx = rx + noise;

                Y = zeros(M,Nsym);
                ptr = 1;
                for col = 1:Nsym
                    rcp = rx(ptr:ptr+M+cpLen-1);
                    r = rcp(cpLen+1:end);
                    Y(:,col) = fft(r);
                    ptr = ptr + M + cpLen;
                end

                Xhat = zeros(M,Nsym);
                
                % ========== TIEMPO PARA CADA SÍMBOLO CON fs ACTUALIZADA ==========
                tc = ((0:Nsym-1)*(M+cpLen) + cpLen) / fs;

                for col = 1:Nsym
                    ht = zeros(Lh,1);
                    for pidx = 1:numel(chanParams.pathDelays)
                        d = chanParams.pathDelays(pidx) + 1;
                        g = chanParams.pathGains(pidx);
                        fd = chanParams.pathDopplerFreqs(pidx);
                        ht(d) = ht(d) + g*exp(1i*2*pi*fd*tc(col));
                    end
                    Hk = fft(ht, M);
                    Xhat(:,col) = Y(:,col) ./ (Hk + 1e-9);
                end

                % MISMA DEMODULACIÓN PARA AMBOS
                bitsHat_nav = demap(Xhat(navIdx,:), modSpec);  % Usa modSpec
                bitsHat_com = demap(Xhat(comIdx,:), modSpec);

                nErr_nav = sum(bits_nav ~= bitsHat_nav(1:length(bits_nav)));
                nErr_com = sum(bits_com ~= bitsHat_com(1:length(bits_com)));

                bers_nav_iter(it) = nErr_nav / length(bits_nav);
                bers_com_iter(it) = nErr_com / length(bits_com);
            end

            % ACTUALIZACIÓN CON DIMENSIONES CORRECTAS
            BER_nav_mean(ir,im,iS) = mean(bers_nav_iter);
            BER_nav_std(ir,im,iS)  = std(bers_nav_iter);

            BER_com_mean(ir,im,iS) = mean(bers_com_iter);
            BER_com_std(ir,im,iS)  = std(bers_com_iter);

            BER_total_iter = bers_nav_iter + bers_com_iter;
            BER_total_mean(ir,im,iS) = mean(BER_total_iter);
            BER_total_std(ir,im,iS)  = std(BER_total_iter);
        end
    end
end

save('OFDM_DATA.mat');

%% ========== GRÁFICAS ACTUALIZADAS ==========
% BER total por modulación
for ir = 1:nRatios
    figure; hold on; grid on; set(gca,'YScale','log')
    for im = 1:nMods
        plot(SNRvec, squeeze(BER_total_mean(ir,im,:)),...
            'LineWidth',1.6, 'DisplayName', modList{im}.name)
    end
    xlabel('SNR (dB)'), ylabel('BER total')
    title(sprintf('BER Total (Nav+Com) - Ratio %d dB, fc=%.1fGHz, Δf=%.1fkHz', ...
        ratio_dB(ir), fc/1e9, df/1e3))
    legend('show')
end

% BER separado: Navegación vs Comunicaciones
for ir = 1:nRatios
    figure; hold on; grid on; set(gca,'YScale','log')
    for im = 1:nMods
        plot(SNRvec, squeeze(BER_nav_mean(ir,im,:)), '--', ...
            'LineWidth',1.2, 'DisplayName', [modList{im}.name ' Nav'])
        plot(SNRvec, squeeze(BER_com_mean(ir,im,:)), '-', ...
            'LineWidth',1.6, 'DisplayName', [modList{im}.name ' Com'])
    end
    xlabel('SNR (dB)'), ylabel('BER')
    title(sprintf('BER Nav vs Com - Ratio %d dB, Misma Modulación', ratio_dB(ir)))
    legend('show')
end

%% MODMAP
function symb = modMap(bits, modSpec)
    M = modSpec.M; k = log2(M);
    ints = bi2de(reshape(bits,k,[]).','left-msb');

    switch upper(modSpec.type)
        case 'PSK'
            symb = pskmod(ints, M, 0, 'InputType','integer');
            symb = symb / sqrt(mean(abs(symb).^2));
        case 'QAM'
            symb = qammod(ints, M, 'UnitAveragePower', true, 'InputType','integer');
    end
end

%% DEMAP
function bitsHat = demap(X, modSpec)
    M = modSpec.M; k = log2(M);
    X = X(:);

    switch upper(modSpec.type)
        case 'PSK'
            ints = pskdemod(X, M, 0, 'OutputType','integer');
        case 'QAM'
            ints = qamdemod(X, M, 'UnitAveragePower',true,'OutputType','integer');
    end

    b = de2bi(ints, k, 'left-msb')';
    bitsHat = b(:);
end