function channels = hNRCreateCDLChannels(channelConfig, gNB, UEs)
    %hNRCreateCDLChannels Creates CDL channels for gNB-to-UE and UE-to-gNB
    %links in a cell for single-user or multi-user scenarios. It also supports
    %single carrier or multiple component carriers.
    %
    %   CHANNELS = hNRCreateCDLChannels(CHANNELCONFIG, GNB, UES) creates
    %   uplink (UL) and downlink (DL) channels.
    %
    %   CHANNELS      - An N-by-N cell array, where N represents the number
    %                   of nodes in the cell. Each non-empty cell contains a
    %                   dictionary keyed by carrier frequency (Hz) with
    %                   nrCDLChannel objects as values.
    %
    %   CHANNELCONFIG - A structure with these fields:
    %       DelayProfile - CDL delay profile
    %       PathDelays   - Discrete path delay row vector (s)
    %   GNB           - An nrGNB object.
    %   UES           - A vector of nrUE objects.
    %
    %   For Carrier Aggregation, the function creates a separate CDL channel
    %   instance per component carrier. Non-carrier-related properties (seed,
    %   antenna geometry, angular offsets, delay profile) are shared across
    %   carriers for the same gNB-UE link. Per-carrier properties
    %   (CarrierFrequency, SampleRate) differ based on each CC's configuration.
    
    % Copyright 2024-2026 The MathWorks, Inc.
    
    numUEs = numel(UEs);
    numNodes = numel(gNB) + numUEs;
    channels = cell(numNodes, numNodes);

    % Determine if Carrier Aggregation is configured
    numCC = size(gNB.ComponentCarrierConfig,2);
    ccConfigs = gNB.ComponentCarrierConfig;

    % Compute per-carrier sample rates and frequencies
    carrierFreqs = zeros(1, numCC);
    sampleRates = zeros(1, numCC);
    scs = gNB.ComponentCarrierConfig(1).SubcarrierSpacing; % Assume same SCS for all the carriers
    for ccIdx = 1:numCC
        if numCC > 1
            ccNRB = ccConfigs(ccIdx).NumResourceBlocks;
        else
            ccNRB = gNB.NumResourceBlocks;
        end
        % Get waveform sample rate from CC configuration
        waveformInfo = nrOFDMInfo(ccNRB, scs/1e3);
        sampleRates(ccIdx) = waveformInfo.SampleRate;
    end
    
    % Create a base CDL channel model object with the desired configuration,
    % including the delay profile (CDL-A, B, C, D, or E), delay spread, and
    % Doppler frequency.
    cdlChannel = nrCDLChannel(SampleRate = sampleRates(1));

    for fname=fieldnames(channelConfig)'
        cdlChannel.(fname{1})=channelConfig.(fname{1});
    end
    cdlChannel.ChannelFiltering = false;
    cdlChannel.NormalizeChannelOutputs = false;
    
    isFDD = gNB.DuplexMode == "FDD";
    % Base Doppler shift (from channelConfig) for per-CC scaling
    baseDoppler = cdlChannel.MaximumDopplerShift;

    % Compute per-carrier DL/UL frequencies
    if isFDD
        dlFreqs = zeros(1, numCC);
        ulFreqs = zeros(1, numCC);
        if numCC > 1
            for ccIdx = 1:numCC
                ccFreq = ccConfigs(ccIdx).CarrierFrequency;
                dlFreqs(ccIdx) = ccFreq(1);
                ulFreqs(ccIdx) = ccFreq(2);
            end
        else
            dlFreqs(1) = gNB.DLCarrierFrequency;
            ulFreqs(1) = gNB.ULCarrierFrequency;
        end
    else
        % TDD: single carrier frequency per CC (same for DL and UL)
        if numCC > 1
            for ccIdx = 1:numCC
                carrierFreqs(ccIdx) = ccConfigs(ccIdx).CarrierFrequency;
            end
        else
            carrierFreqs(1) = gNB.CarrierFrequency;
        end
    end

    % Set antenna configuration for the link using the maximum of Tx
    % and Rx antenna counts at the gNB. This ensures a
    % single shared panel per node that accommodates both directions.
    if gNB.NumTransmitAntennas >= gNB.NumReceiveAntennas
        gNBArray = gNB.TransmitAntennaArray;
    else
        gNBArray = gNB.ReceiveAntennaArray;
    end

    % Use node orientations, but apply a typical 12° downtilt for gNB
    % if the orientation is at the default [0;0;0]
    gNBTxOri = gNB.TransmitArrayOrientation;
    if isequal(gNBTxOri, [0;0;0])
        gNBTxOri = [0; 12; 0];
    end

    % Apply a typical 12° downtilt for gNB if orientation is at default [0;0;0]
    gNBRxOri = gNB.ReceiveArrayOrientation;
    if isequal(gNBRxOri, [0;0;0])
        gNBRxOri = [0; 12; 0];
    end

    % Base carrier frequency for per-CC Doppler scaling (f_D scales as fc/fc_base)
    if isFDD
        baseFreq = dlFreqs(1);
    else
        baseFreq = carrierFreqs(1);
    end
    
    % For each UE, create per-carrier DL and UL channel instances
    for ueIdx = 1:numUEs
        % Shared properties (same across all carriers)
        % Create DL channel with custom delay profile
        baseChannel = hMakeCustomCDL(cdlChannel);
        % Store base seed for per-carrier seed assignment
        baseSeed = baseChannel.Seed + (ueIdx - 1);

        % Set antenna configuration for the link using the maximum of Tx
        % and Rx antenna counts at each UE. This ensures a
        % single shared panel per node that accommodates both directions.
        if UEs(ueIdx).NumReceiveAntennas >= UEs(ueIdx).NumTransmitAntennas
            ueArray = UEs(ueIdx).ReceiveAntennaArray;
        else
            ueArray = UEs(ueIdx).TransmitAntennaArray;
        end

        % Configure antenna arrays and orientations from node properties.
        baseChannel.TransmitAntennaArray = gNBArray;
        baseChannel.ReceiveAntennaArray = ueArray;

        baseChannel.TransmitArrayOrientation = gNBTxOri;
        baseChannel.ReceiveArrayOrientation = UEs(ueIdx).ReceiveArrayOrientation;
    
        % Compute the LOS angle from gNB to UE
        [~, depAngleDL] = rangeangle(UEs(ueIdx).Position', gNB.Position');
        % Configure the azimuth and zenith departure angle offsets
        baseChannel.AnglesAoD(:) = baseChannel.AnglesAoD(:) + depAngleDL(1);
        % Convert elevation angle to zenith angle
        baseChannel.AnglesZoD(:) = baseChannel.AnglesZoD(:) - baseChannel.AnglesZoD(1) + (90 - depAngleDL(2));
    
        % Compute the LOS angle from UE to gNB
        [~, arrAngleDL] = rangeangle(gNB.Position', UEs(ueIdx).Position');
        % Configure the azimuth and zenith arrival angle offsets
        baseChannel.AnglesAoA(:) = baseChannel.AnglesAoA(:) - baseChannel.AnglesAoA(1) + arrAngleDL(1);
        % Convert elevation angle to zenith angle
        baseChannel.AnglesZoA(:) = baseChannel.AnglesZoA(:) - baseChannel.AnglesZoA(1) + (90 - arrAngleDL(2));

        % Per-carrier channels stored in dictionary keyed by frequency
        dlDict = dictionary;
        ulDict = dictionary;

        for ccIdx = 1:numCC
            % Clone the shared base and set per-carrier properties
            dlChannel = clone(baseChannel);
            % Assign unique seed per carrier per UE for independent fading
            dlChannel.Seed = baseSeed + (ccIdx - 1) * numUEs;
            dlChannel.SampleRate = sampleRates(ccIdx);
            % For FDD, assign appropriate DL carrier frequency
            if isFDD
                dlChannel.CarrierFrequency = dlFreqs(ccIdx);
            else
                dlChannel.CarrierFrequency = carrierFreqs(ccIdx);
            end
            % Scale Doppler shift per carrier: f_D(cc) = f_D(base) * fc(cc)/fc(base)
            dlChannel.MaximumDopplerShift = baseDoppler * dlChannel.CarrierFrequency / baseFreq;

            % Create UL channel
            ulChannel = clone(dlChannel);
            ulChannel.swapTransmitAndReceive();
            ulChannel.TransmitArrayOrientation = UEs(ueIdx).TransmitArrayOrientation;
            ulChannel.ReceiveArrayOrientation = gNBRxOri;
            % For FDD, assign appropriate UL carrier frequency and scale Doppler
            if isFDD
                ulChannel.CarrierFrequency = ulFreqs(ccIdx);
                ulChannel.MaximumDopplerShift = baseDoppler * ulChannel.CarrierFrequency / baseFreq;
            end

            dlDict(dlChannel.CarrierFrequency) = {dlChannel};
            ulDict(ulChannel.CarrierFrequency) = {ulChannel};
        end

        channels{gNB.ID, UEs(ueIdx).ID} = dlDict;
        channels{UEs(ueIdx).ID, gNB.ID} = ulDict;
    end
end
