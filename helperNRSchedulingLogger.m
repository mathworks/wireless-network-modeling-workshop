classdef helperNRSchedulingLogger < handle
    %helperNRSchedulingLogger Scheduler logging mechanism
    %   The class implements per-carrier logging mechanism. The following types
    %   of information is logged:
    %   - Logs of CQI values for UEs over the bandwidth
    %   - Logs of resource grid assignment to UEs
    %
    %   All log vectors are RNTI-indexed: position i stores the metric for the
    %   UE with RNTI i, regardless of which carrier it is connected to. This
    %   ensures all carriers use same-length vectors, simplifying cross-carrier
    %   queries.
    %
    %   helperNRSchedulingLogger Name-Value pairs:
    %
    %   LinkDirection     - Indicate the link direction in which logging is
    %                       performed. Takes values "DL", "UL", or "Both"
    %                       (default: "Both").
    %
    %   CarrierID        - Scalar or vector of carrier indices to log. If
    %                      specified, logging and queries operate only on these
    %                      carriers. Default is 1 (primary carrier).

    %   Copyright 2022-2026 The MathWorks, Inc.

    properties
        %LinkDirection Indicates the directions in which logging is performed
        % It takes values "DL","UL" and "Both". By default, the value is set to
        % "Both", indicating that logs are recorded for both directions.
        LinkDirection (1,1) string {mustBeMember(LinkDirection, ["DL", "UL", "Both"])} = "Both";

        %CarrierID Indicates index of the carrier(s) to log.
        % Scalar or vector specifying a subset of gNB carrier indices. Default is 1
        % (gNB first carrier).
        CarrierID (1,:) {mustBeInteger, mustBePositive} = 1;
    end

    properties
        %NumUEsPerCarrier Number of UEs on each carrier
        % It is a 1-by-NumCarriers row vector. Element at ith position gives the
        % number of UEs connected on gNB ith carrier.
        NumUEsPerCarrier

        %UERNTIsPerCarrier RNTIs of UEs served on each carrier
        % It is a 1-by-NumCarriers cell array. Each element is a row vector of UE
        % RNTIs served on that carrier.
        UERNTIsPerCarrier

        %NumCarriers Number of component carriers configured at the gNB
        NumCarriers

        %NumHARQ Number of HARQ processes
        % The default value is 16 HARQ processes. For 5G Terrestrial Networks (TN),
        % the maximum is 16; for 5G Non-Terrestrial Networks (NTN), it is 32.
        NumHARQ (1, 1) {mustBeInteger, mustBeBetween(NumHARQ, 1, 32)} = 16;

        %NumFrames Number of frames in simulation
        NumFrames

        %SchedulingType Type of scheduling (slot based or symbol based)
        % Value 0 means slot based and value 1 means symbol based. The
        % default value is 0
        SchedulingType (1, 1) {mustBeMember(SchedulingType, [0, 1])} = 0;

        %DuplexMode Duplexing mode
        % Frequency division duplexing (FDD) or time division duplexing (TDD)
        % Value 0 means FDD and 1 means TDD. The default value is 0
        DuplexMode (1, 1) {mustBeMember(DuplexMode, [0, 1])} = 0;

        %ResourceAllocationType Type for Resource allocation type (RAT)
        % Value 0 means RAT-0 and value 1 means RAT-1. The default value is 1
        ResourceAllocationType (1, 1) {mustBeInteger, mustBeBetween(ResourceAllocationType, 0, 1)} = 1;

        %ColumnIndexMap Mapping the column names of scheduling logs to respective column indices
        % It is a map object
        ColumnIndexMap

        %GrantLogsColumnIndexMap Mapping the column names of grant logs to respective column indices
        % It is a map object
        GrantLogsColumnIndexMap

        %NumRBs Number of resource blocks per component carrier
        % A vector of two elements and represents the number of PDSCH and
        % PUSCH RBs respectively
        NumRBs = zeros(2, 1);

        %Bandwidth Total aggregated bandwidth across all component carriers
        % A vector of two elements. First and second elements represent the
        % total downlink and uplink bandwidth respectively. For single-carrier
        % operation, this equals the single carrier bandwidth. For CA, this is
        % the sum of bandwidths across all configured component carriers.
        Bandwidth

        %RBGSizeConfig Type of RBG table to use
        % Flag used in determining the RBGsize. Value 1 represents
        % (configuration-1 RBG table) or 2 represents (configuration-2 RBG
        % table) as defined in 3GPP TS 38.214 Section 5.1.2.2.1. The
        % default value is 1
        RBGSizeConfig = 1;

        %SchedulingLog Symbol-by-symbol log of the simulation
        % It is a NumCarriers-by-2 cell array. Each row corresponds to a carrier
        % index. In FDD mode first element contains downlink scheduling information
        % and second element contains uplink scheduling information. In TDD mode
        % first element contains scheduling information of both downlink and uplink
        SchedulingLog

        %GrantLog Log of the scheduling grants
        % It is a 1-by-NumCarriers cell array. Each element contains the grant log
        % for that carrier.
        GrantLog

        %IsLogReplay Flag to decide the type of post-simulation visualization
        % whether to show plain replay of the resource assignment during
        % simulation or of the selected slot (or frame). During the
        % post-simulation visualization, setting the value to 1 just
        % replays the resource assignment of the simulation frame-by-frame
        % (or slot-by-slot). Setting value to 0 gives the option to select
        % a particular frame (or slot) to see the way resources are
        % assigned in the chosen frame (or slot)
        IsLogReplay

        %PeakDataRateDL Aggregate theoretical peak data rate in the downlink direction (Mbps)
        % For CA, this is the sum of per-carrier DL peak data rates,
        % accounting for each carrier's NRB, SCS, and TDD configuration.
        PeakDataRateDL

        %PeakDataRateUL Aggregate theoretical peak data rate in the uplink direction (Mbps)
        % For CA, this is the sum of per-carrier UL peak data rates,
        % accounting for each carrier's NRB, SCS, and TDD configuration.
        PeakDataRateUL

        %TraceIndexCounter Current log index
        TraceIndexCounter = 0;
    end

    properties (SetAccess = private)
        %UECarrierIndexMap Mapping from gNB carrier index to UE carrier index
        % It is a 1-by-NumCarriers cell array. Each element is a vector of
        % length NumUEsPerCarrier(c) containing the UE-local component carrier
        % index for each UE on that gNB carrier.
        UECarrierIndexMap

        % Enable NTN-specific logging adaptations (extended HARQ, timing advance)
        IsNTNSimulation = false;
    end

    properties (WeakHandle, SetAccess=private)
        %GNB Node object of type nrGNB
        GNB nrGNB

        %UEs Vector of node objects of type nrUE
        UEs nrUE
    end

    properties (WeakHandle,Hidden,SetAccess=protected)
        %NetworkSimulator Handle of the wirelessNetworkSimulator instance
        % Can be set through N-V pair in the constructor. If not set, will be
        % obtained by calling wirelessNetworkSimulator.getInstance().
        NetworkSimulator wirelessNetworkSimulator {mustBeScalarOrEmpty}
    end

    properties (Constant)
        %NumSym Number of symbols in a slot
        NumSym = 14;

        %NominalRBGSizePerBW Nominal RBG size table
        % It is for the specified bandwidth in accordance with
        % 3GPP TS 38.214, Section 5.1.2.2.1
        NominalRBGSizePerBW = [
            36   2   4
            72   4   8
            144  8   16
            275  16  16
            ];

        % Duplexing mode related constants
        %FDDDuplexMode Frequency division duplexing mode
        FDDDuplexMode = 0;
        %TDDDuplexMode Time division duplexing mode
        TDDDuplexMode = 1;

        % Constants related to scheduling type
        %SymbolBased Symbol based scheduling
        SymbolBased = 1;
        %SlotBased Slot based scheduling
        SlotBased = 0;

        % Constants related to downlink and uplink information. These
        % constants are used for indexing logs and identifying plots
        %DownlinkIdx Index for all downlink information
        DownlinkIdx = 1;
        %UplinkIdx Index for all uplink information
        UplinkIdx = 2;
    end

    properties (Access = private)
        %FreqAllocLabel Column name for frequency allocation, set based on resource allocation type
        FreqAllocLabel

        %NumSlotsFrame Number of slots in 10ms time frame
        NumSlotsFrame

        %CurrSlot Current slot in the frame
        CurrSlot

        %CurrFrame Current frame
        CurrFrame

        %CurrSymbol Current symbol in the slot
        CurrSymbol

        %NumLogs Number of logs to be created based on number of links
        NumLogs

        %SymbolInfo Information about how each symbol (UL/DL/Guard) is allocated
        SymbolInfo

        %SlotInfo Information about how each slot (UL/DL/Guard) is allocated
        SlotInfo

        %PlotIds IDs of the plots
        PlotIds

        %GrantCount Keeps track of count of grants sent
        GrantCount

        %RBGSize Number of RBs in an RBG. First element represents RBG
        % size for PDSCHRBs and second element represents RBG size for
        % PUSCHRBS
        RBGSize = zeros(2, 1);

        %LogInterval Represents the log interval
        % It represents the difference (in terms of number of symbols) between
        % two consecutive rows which contains valid data in SchedulingLog
        % cell array
        LogInterval

        %StepSize Represents the granularity of logs
        StepSize

        %UEMetricsUL UE metrics for each slot in the UL direction
        % It is a 1-by-NumCarriers cell array. Each element is an N-by-2 where N is
        % the number of UEs. Each column contains the following metrics:
        % Transmitted bytes and pending buffer amount bytes.
        UEMetricsUL

        %UEMetricsDL UE metrics for each slot in the DL direction
        % It is a 1-by-NumCarriers cell array. Each element is an N-by-2 array
        % where N is the total number of UEs connected with the gNB's first
        % carrier. Each column contains the following metrics: Transmitted bytes,
        % and pending buffer amount bytes.
        UEMetricsDL

        %PrevUEMetricsUL UE metrics returned in the UL direction for previous query
        % It is a 1-by-NumCarriers cell array. Each element is an N-by-2 array
        % where N is the total number of UEs connected with the gNB's first
        % carrier. Each column contains the following metrics: Transmitted bytes
        % transmitted, and pending buffer amount bytes.
        PrevUEMetricsUL

        %PrevUEMetricsDL UE metrics returned in the DL direction for previous query
        % It is a 1-by-NumCarriers cell array. Each element is an N-by-2 array
        % where N is the total number of UEs connected with the gNB's first
        % carrier. Each column contains the following metrics: Transmitted bytes
        % transmitted, and pending buffer amount bytes.
        PrevUEMetricsDL

        %UplinkChannelQuality Current channel quality for the UEs in uplink
        % It is a 1-by-NumCarriers cell array. Each element is an array of size
        % M-by-N where M and N represents the number of UEs in each cell and the
        % number of RBs respectively.
        UplinkChannelQuality

        %DownlinkChannelQuality Current channel quality for the UEs in downlink
        % It is a 1-by-NumCarriers cell array. Each element is an array of size
        % M-by-N where M and N represents the number of UEs in each cell and the
        % number of RBs respectively.
        DownlinkChannelQuality

        %HARQProcessStatusUL HARQ process status for each UE in UL
        % It is a 1-by-NumCarriers cell array. Each element is an array of size
        % M-by-N where M and N represents the number of UEs and number of HARQ
        % processes for each UE respectively. Each element stores the last received
        % new data indicator (NDI) values in the uplink.
        HARQProcessStatusUL

        %HARQProcessStatusDL HARQ process status for each UE in DL
        % It is a 1-by-NumCarriers cell array. Each element is an array of size
        % M-by-N where M and N represents the number of UEs and number of HARQ
        % processes for each UE respectively. Each element stores the last received
        % new data indicator (NDI) values in the downlink
        HARQProcessStatusDL

        %PeakDLSpectralEfficiency Theoretical peak spectral efficiency in
        % the downlink direction (bits/s/Hz). Computed as aggregate peak DL
        % data rate divided by total aggregated DL bandwidth.
        PeakDLSpectralEfficiency

        %PeakULSpectralEfficiency Theoretical peak spectral efficiency in
        % the uplink direction (bits/s/Hz). Computed as aggregate peak UL
        % data rate divided by total aggregated UL bandwidth.
        PeakULSpectralEfficiency

        %LogGranularity Granularity of logs
        % It indicates whether logging is done for each symbol or each slot
        % (1 slot = 14 symbols)
        LogGranularity = 14;

        %Events List of events registered. It contains list of periodic events
        % By default events are triggered after every slot boundary. This event
        % list contains events which depends on the traces or which
        % requires periodic trigger after each slot boundary.
        % It is a vector of structures and contains following fields
        %    CallBackFn - Call back to invoke when triggering the event
        %    TimeToInvoke - Time at which event has to be invoked
        Events = [];

        %NumDLULPatternSlots Number of slots in DL-UL pattern (for TDD mode)
        NumDLULPatternSlots

        %HasSpecialSlot Indicate the presence of special slot (for TDD mode)
        HasSpecialSlot = 0;
    end

    methods
        function obj = helperNRSchedulingLogger(numFramesSim, gNB, UEs, varargin)
            %helperNRSchedulingLogger Construct scheduling information logging object
            %
            % OBJ = helperNRSchedulingLogger(NUMFRAMESSIM, GNB, UEs) creates scheduling
            % information logging object.
            %
            % OBJ = helperNRSchedulingLogger(NUMFRAMESSIM, GNB, UEs, LINKDIRECTION) Create
            % scheduling information logging object.
            %
            % NUMFRAMESSIM is simulation time in terms of number of 10 ms frames.
            %
            % GNB is an object of type nrGNB.
            %
            % UEs is a vector of node objects of type nrUE. They must be connected to
            % the same GNB.
            %
            % LINKDIRECTION indicates the link directions in which logging is performed.
            %
            % CarrierID    - Index of the carrier(s) to log. If specified, logging is
            %                performed only for the given carrier(s). Default is 1 (gNB
            %                first carrier). This is according to the order of carriers
            %                at the gNB.

            % Initialize the properties
            for idx = 1:2:numel(varargin)
                obj.(varargin{idx}) = varargin{idx+1};
            end
            if isempty(obj.NetworkSimulator) && isempty(obj.IsLogReplay)
                obj.NetworkSimulator = wirelessNetworkSimulator.getInstance();
            end
            % Set number of frames in simulation
            obj.NumFrames = numFramesSim;

            % Trace logging
            obj.GNB = gNB;
            if isempty(UEs) % No UEs in the cell
                return;
            end

            % Identify whether it is TN gNB or NTN gNB
            obj.IsNTNSimulation = isprop(gNB, 'FeederLinkCarrierFrequency');

            % Sort UEs by RNTI so that obj.UEs(rnti) is always correct
            [~, sortOrder] = sort([UEs.RNTI]);
            obj.UEs = UEs(sortOrder);
            numTotalUEs = numel(UEs);
            obj.NumSlotsFrame = (10 * gNB.SubcarrierSpacing) / 15e3; % Number of slots in a 10 ms frame
            slotDuration = (10/obj.NumSlotsFrame)*1e-3;
            % Symbol duration for the given numerology
            symbolDuration = 1e-3/(14*(gNB.SubcarrierSpacing/15e3)); % Assuming normal cyclic prefix

            obj.NumCarriers = numel(gNB.ComponentCarrierConfig);

            % Determine which UEs are connected to each carrier
            obj.UERNTIsPerCarrier = cell(1, obj.NumCarriers);
            if isprop(gNB, 'UEInfoPerCarrier')
                for carrierIdx = 1:obj.NumCarriers
                    obj.UERNTIsPerCarrier{carrierIdx} = gNB.UEInfoPerCarrier(carrierIdx).UERNTIs;
                end
            else
                % Backward compatible: single carrier uses all the connected UEs
                obj.UERNTIsPerCarrier{1} = 1:numTotalUEs;
            end
            obj.NumUEsPerCarrier = zeros(1, obj.NumCarriers);
            for carrierIdx = 1:obj.NumCarriers
                obj.NumUEsPerCarrier(carrierIdx) = numel(obj.UERNTIsPerCarrier{carrierIdx});
            end

            % Build UE carrier index map by matching gNB DL carrier
            % frequency against each UE's ReceiveFrequency
            obj.UECarrierIndexMap = cell(1, obj.NumCarriers);
            if obj.IsNTNSimulation
                gNBDLFreq = gNB.ServiceLinkCarrierFrequency(1);
            else
                gNBDLFreq = gNB.DLCarrierFrequency;
            end
            for carrierIdx = 1:obj.NumCarriers
                connectedUEs = obj.UERNTIsPerCarrier{carrierIdx};
                numUEsCC = obj.NumUEsPerCarrier(carrierIdx);
                uePhyIdx = zeros(1, numUEsCC);
                for posIdx = 1:numUEsCC
                    ueIdx = connectedUEs(posIdx);
                    [~, uePhyIdx(posIdx)] = ismember(gNBDLFreq(carrierIdx), obj.UEs(ueIdx).ReceiveFrequency);
                end
                obj.UECarrierIndexMap{carrierIdx} = uePhyIdx;
            end

            obj.NumHARQ = gNB.NumHARQ;
            schedulerConfig = gNB.MACEntity.Scheduler.SchedulerConfig;
            obj.SchedulingType = schedulerConfig.SchedulingType;
            obj.ColumnIndexMap = containers.Map('KeyType','char','ValueType','double');
            obj.GrantLogsColumnIndexMap = containers.Map('KeyType','char','ValueType','double');

            % Maximum number of transmission layers for each UE in DL
            numLayersDL = min(gNB.NumTransmitAntennas*ones(numTotalUEs, 1),[UEs.NumReceiveAntennas]');
            % Maximum number of transmission layers for each UE in UL
            numLayersUL = min(gNB.NumReceiveAntennas*ones(numTotalUEs, 1), [UEs.NumTransmitAntennas]');

            % Set resource allocation type
            obj.ResourceAllocationType = schedulerConfig.ResourceAllocationType;
            if obj.ResourceAllocationType % RAT-1
                obj.FreqAllocLabel = 'Frequency Allocation (RBs)';
            else % RAT-0
                obj.FreqAllocLabel = 'Frequency Allocation (RBGs)';
            end

            % Verify Duplex mode and update the properties
            if strcmpi(gNB.DuplexMode, "TDD")
                obj.DuplexMode = obj.TDDDuplexMode;
            end
            if obj.DuplexMode == obj.TDDDuplexMode || obj.SchedulingType == obj.SymbolBased
                obj.LogGranularity = 1;
            end

            if strcmpi(gNB.DuplexMode, "TDD") % TDD
                obj.NumLogs = 1;
                dlulConfig = gNB.DLULConfigTDD;
                % Add 'NumDLULPatternSlots' and 'HasSpecialSlot' for optimization. To be used while updating the 'Signal Type'
                obj.NumDLULPatternSlots = dlulConfig.DLULPeriodicity*(gNB.SubcarrierSpacing/15e3);
                % Check if special slot is configured
                totalSymbols = dlulConfig.NumDLSymbols + dlulConfig.NumULSymbols;
                obj.HasSpecialSlot = totalSymbols > 0;
            else % FDD
                obj.NumLogs = 2;
            end

            % Initialize per-carrier metrics arrays.
            % Each element stores current/previous UE metrics, channel
            % quality, and HARQ NDI status.
            obj.UEMetricsUL = cell(1, obj.NumCarriers);
            obj.UEMetricsDL = cell(1, obj.NumCarriers);
            obj.PrevUEMetricsUL = cell(1, obj.NumCarriers);
            obj.PrevUEMetricsDL = cell(1, obj.NumCarriers);
            % Store current UL and DL CQI values on the RBs for the UEs
            obj.UplinkChannelQuality = cell(1, obj.NumCarriers);
            obj.DownlinkChannelQuality = cell(1, obj.NumCarriers);
            % Store the last received new data indicator (NDI) values for
            % UL and DL HARQ processes
            obj.HARQProcessStatusUL = cell(1, obj.NumCarriers);
            obj.HARQProcessStatusDL = cell(1, obj.NumCarriers);
            for carrierIdx = 1:obj.NumCarriers
                obj.UEMetricsUL{carrierIdx} = zeros(numTotalUEs, 2);
                obj.UEMetricsDL{carrierIdx} = zeros(numTotalUEs, 2);
                obj.PrevUEMetricsUL{carrierIdx} = zeros(numTotalUEs, 2);
                obj.PrevUEMetricsDL{carrierIdx} = zeros(numTotalUEs, 2);
                obj.UplinkChannelQuality{carrierIdx} = cell(numTotalUEs, 1);
                obj.DownlinkChannelQuality{carrierIdx} = cell(numTotalUEs, 1);
                obj.HARQProcessStatusUL{carrierIdx} = zeros(numTotalUEs, obj.NumHARQ);
                obj.HARQProcessStatusDL{carrierIdx} = zeros(numTotalUEs, obj.NumHARQ);
            end

            % Compute aggregate bandwidth across all component carriers
            if obj.NumCarriers > 1
                obj.Bandwidth = [sum([gNB.ComponentCarrierConfig.ChannelBandwidth]) ...
                                 sum([gNB.ComponentCarrierConfig.ChannelBandwidth])];
            else
                obj.Bandwidth = [gNB.ChannelBandwidth gNB.ChannelBandwidth];
            end

            % Calculate aggregate peak data rates as per 3GPP TR 37.910. For CA, peak
            % rate is computed per carrier (each with its own NRB, SCS, and TDD config)
            % and summed. The number of layers used for the peak DL data rate
            % calculation is taken as the average of maximum layers possible for each
            % UE. The maximum layers possible for each UE is min(gNBTxAnts, ueRxAnts)
            avgNumLayersDL = sum(numLayersDL) / numTotalUEs;
            avgNumLayersUL = sum(numLayersUL) / numTotalUEs;
            aggPeakDL = 0;
            aggPeakUL = 0;
            % Assume same SCS and duplex mode for all the carriers
            scs = gNB.ComponentCarrierConfig(1).SubcarrierSpacing/1e3;
            duplexMode = gNB.ComponentCarrierConfig(1).DuplexMode;
            for ccIdx = 1:obj.NumCarriers
                if obj.NumCarriers > 1
                    ccConfig = gNB.ComponentCarrierConfig(ccIdx);
                    ccNRB = ccConfig.NumResourceBlocks;
                else
                    ccNRB = gNB.NumResourceBlocks;
                end
                % Determine DL/UL scale factors based on duplex mode
                if strcmp(duplexMode, "TDD")
                    if obj.NumCarriers > 1
                        dlulConfig = ccConfig.DLULConfigTDD;
                    else
                        dlulConfig = gNB.DLULConfigTDD;
                    end
                    % Number of DL symbols in one DL-UL pattern
                    ccNumDLSymbols = dlulConfig.NumDLSlots*14 + dlulConfig.NumDLSymbols;
                    % Number of UL symbols in one DL-UL pattern
                    ccNumULSymbols = dlulConfig.NumULSlots*14 + dlulConfig.NumULSymbols;
                    % Number of symbols in one DL-UL pattern
                    ccNumSymbols = dlulConfig.DLULPeriodicity*(gNB.SubcarrierSpacing/15e3)*14;
                    % Normalized scalar considering the downlink symbol allocation in the frame
                    % structure
                    ccScaleFactorDL = ccNumDLSymbols/ccNumSymbols;
                    % Normalized scalar considering the uplink symbol allocation in the frame
                    % structure
                    ccScaleFactorUL = ccNumULSymbols/ccNumSymbols;

                else % FDD
                    % Normalized scalars in the DL and UL directions are 1 for FDD mode
                    ccScaleFactorDL = 1;
                    ccScaleFactorUL = 1;
                end

                % Per-carrier peak data rate (Mbps)
                aggPeakDL = aggPeakDL + 1e-6*avgNumLayersDL*ccScaleFactorDL*8*(948/1024)*(ccNRB*12)/symbolDuration;
                aggPeakUL = aggPeakUL + 1e-6*avgNumLayersUL*ccScaleFactorUL*8*(948/1024)*(ccNRB*12)/symbolDuration;
            end

            % Determine the plots and assign aggregate peak rates
            if obj.LinkDirection == "Both"
                obj.PlotIds = [obj.DownlinkIdx obj.UplinkIdx];
                obj.PeakDataRateDL = aggPeakDL;
                obj.PeakDataRateUL = aggPeakUL;
                % Calculate uplink and downlink peak spectral efficiency
                obj.PeakDLSpectralEfficiency = 1e6*obj.PeakDataRateDL/obj.Bandwidth(obj.DownlinkIdx);
                obj.PeakULSpectralEfficiency = 1e6*obj.PeakDataRateUL/obj.Bandwidth(obj.UplinkIdx);
            elseif obj.LinkDirection == "DL" % Downlink
                obj.PlotIds = obj.DownlinkIdx;
                obj.PeakDataRateDL = aggPeakDL;
                % Calculate downlink peak spectral efficiency
                obj.PeakDLSpectralEfficiency = 1e6*obj.PeakDataRateDL/obj.Bandwidth(obj.DownlinkIdx);
            else % Uplink
                obj.PlotIds = obj.UplinkIdx;
                obj.PeakDataRateUL = aggPeakUL;
                % Calculate uplink peak spectral efficiency
                obj.PeakULSpectralEfficiency = 1e6*obj.PeakDataRateUL/obj.Bandwidth(obj.UplinkIdx);
            end

            % Initialize number of RBs, RBG size, CQI and metrics properties
            for idx = 1: numel(obj.PlotIds)
                logIdx = obj.PlotIds(idx);
                obj.NumRBs(logIdx) = gNB.NumResourceBlocks; % Number of RBs in DL/UL
                % Calculate the RBGSize
                rbgSizeIndex = min(find(obj.NumRBs(logIdx) <= obj.NominalRBGSizePerBW(:, 1), 1));
                if obj.RBGSizeConfig == 1
                    obj.RBGSize(logIdx) = obj.NominalRBGSizePerBW(rbgSizeIndex, 2);
                else
                    obj.RBGSize(logIdx) = obj.NominalRBGSizePerBW(rbgSizeIndex, 3);
                end
            end

            % Initialize the scheduling logs per carrier
            obj.SchedulingLog = cell(obj.NumCarriers, 2);
            for carrierIdx = 1:obj.NumCarriers
                for idx=1:min(obj.NumLogs, numel(obj.PlotIds))
                    plotId = obj.PlotIds(idx);
                    if obj.DuplexMode == obj.FDDDuplexMode
                        logIdx = plotId; % FDD
                    else
                        logIdx = idx; % TDD
                    end
                    obj.SchedulingLog{carrierIdx, logIdx} = constructSchedulingLogFormat(obj, logIdx, numTotalUEs);
                end
            end

            % Construct the grant log format per carrier
            obj.GrantLog = cell(1, obj.NumCarriers);
            obj.GrantCount = zeros(1, obj.NumCarriers);
            for carrierIdx = 1:obj.NumCarriers
                obj.GrantLog{carrierIdx} = constructGrantLogFormat(obj, numTotalUEs);
            end

            if ~isempty(obj.IsLogReplay) && obj.SchedulingType == obj.SlotBased
                % Post simulation log visualization and slot based scheduling
                obj.StepSize = 1;
                obj.LogInterval = 1;
            else
                % Live visualization
                obj.LogInterval = obj.NumSym;
                if obj.SchedulingType % Symbol based scheduling
                    obj.StepSize = 1;
                else % Slot based scheduling
                    obj.StepSize = obj.NumSym;
                end
            end

            if isempty(obj.IsLogReplay)
                % Register periodic logging event with network simulator to log cell
                % scheduling statistics
                if strcmpi(gNB.DuplexMode, "TDD") || obj.SchedulingType == obj.SymbolBased
                    scheduleAction(obj.NetworkSimulator, @obj.logCellSchedulingStats, [], symbolDuration/2, symbolDuration);
                else
                    scheduleAction(obj.NetworkSimulator, @obj.logCellSchedulingStats, [], slotDuration/2, slotDuration);
                end

                % Register callbacks for PHY metrics from UE and gNB nodes
                % DownlinkIdx for UE (DL reception), UplinkIdx for gNB (UL reception)
                registerEventCallback(obj.UEs, "ReceptionEnded", @(eventStruct) obj.logPHYMetrics(eventStruct, obj.DownlinkIdx));
                registerEventCallback(obj.GNB, "ReceptionEnded", @(eventStruct) obj.logPHYMetrics(eventStruct, obj.UplinkIdx));
                % Create a listener object for the 'ScheduledResources' event.
                % This helps in logging the scheduling output of gNB
                addlistener(obj.GNB, 'ScheduledResources', @(src, eventData) obj.logSchedulingGrants(src, eventData));

                % Register NTN-specific callback for UE Tx time logging
                if obj.IsNTNSimulation
                    registerEventCallback(obj.UEs, "TransmissionStarted", @(eventStruct) obj.logUETxTime(eventStruct));
                end
            end
        end

        function logPHYMetrics(obj, eventStruct, linkIndex)
            %logPHYMetrics Log the SINR and signal type values
            %
            % logPHYMetrics(OBJ, EVENTSTRUCT, LINKINDEX) Logs
            % the PHY information based on the received event data
            %
            % EVENTSTRUCT - Event struct from registerEventCallback
            %
            % LINKINDEX - Integer identifying the link direction

            linkDir = obj.PlotIds;
            linkDir = linkDir - 1;
            if numel(obj.PlotIds) == 2
                linkDir = 2;
            end

            if obj.DuplexMode == obj.FDDDuplexMode
                % FDD Mode
                if linkDir ~= 1 && linkIndex == obj.DownlinkIdx
                    % If LinkDirection is for downlink or uplink and downlink
                    logPHYMetricsData(obj, eventStruct, obj.DownlinkIdx);
                end
                if linkDir ~= 0 && linkIndex == obj.UplinkIdx
                    % If LinkDirection is for uplink or uplink and downlink
                    logPHYMetricsData(obj, eventStruct, obj.UplinkIdx);
                end
            else % TDD mode: both DL and UL are stored in SchedulingLog{carrierIdx, DownlinkIdx}
                logPHYMetricsData(obj, eventStruct, linkIndex);
            end
        end

        function logPHYMetricsData(obj, eventStruct, linkIndex)
            %logPHYMetricsData Assign the Scheduling log corresponding to the linkIndex

            data = eventStruct.EventData;
            % Determine which carrier this event belongs to by matching
            % the event's carrier frequency against gNB frequencies.
            % DL (linkIndex=1) -> match against DL carrier frequencies
            % UL (linkIndex=2) -> match against UL carrier frequencies
            if linkIndex == obj.DownlinkIdx
                if obj.IsNTNSimulation
                    carrierIdx = find(obj.GNB.ServiceLinkCarrierFrequency(1) == data.CenterFrequency, 1);
                else
                    carrierIdx = find(obj.GNB.DLCarrierFrequency == data.CenterFrequency, 1);
                end
            else
                if obj.IsNTNSimulation
                    carrierIdx = find(obj.GNB.ServiceLinkCarrierFrequency(2) == data.CenterFrequency, 1);
                else
                    carrierIdx = find(obj.GNB.ULCarrierFrequency == data.CenterFrequency, 1);
                end
            end
            if isempty(carrierIdx) || ~ismember(carrierIdx, obj.CarrierID)
                return;
            end

            % In TDD mode, both DL and UL are stored in column DownlinkIdx
            if obj.DuplexMode ~= obj.FDDDuplexMode
                storageIdx = obj.DownlinkIdx;
            else
                storageIdx = linkIndex;
            end

            currFrame = data.FrameInfo(1);
            currSlot = data.FrameInfo(2);
            symbolNumSimulation = (currFrame * obj.NumSlotsFrame + currSlot) * obj.NumSym;
            rowIdx = symbolNumSimulation + 1;
            rntiIdx = data.RNTI;
            % Store the required column index for 'Signal Type'
            sigTypeCol = obj.ColumnIndexMap('Signal Type');

            if ~isinf(data.SINR)
                % Log SINR corresponding to the data transmission
                obj.SchedulingLog{carrierIdx, storageIdx}{rowIdx, obj.ColumnIndexMap('SINR (dB)')}(rntiIdx) = data.SINR;
            end

            % Get the current SignalType for the RNTI and symbol
            currSignalType = obj.SchedulingLog{carrierIdx, storageIdx}{rowIdx, sigTypeCol}(rntiIdx);
            if currSignalType == ""
                % If empty, log the new Signal Type
                signalTypeVal = data.SignalType;
            else % If already present, append new Signal Type (separated by '+')
                signalTypeVal = currSignalType + "+" + data.SignalType;
            end
            % Update SchedulingLog
            obj.SchedulingLog{carrierIdx, storageIdx}{rowIdx, sigTypeCol}(rntiIdx) = signalTypeVal;

            % Log actual UE reception time for DL in NTN simulations
            if obj.IsNTNSimulation && linkIndex == obj.DownlinkIdx
                ueRxTimeMs = eventStruct.Timestamp * 1e3;
                obj.SchedulingLog{carrierIdx, storageIdx}{rowIdx, obj.ColumnIndexMap('UE Rx Time (ms) (DL only)')}(rntiIdx) = ueRxTimeMs;
            end
        end

        function logUETxTime(obj, eventStruct)
            %logUETxTime Log actual UE transmission time for UL
            %
            % logUETxTime(OBJ, EVENTSTRUCT) logs the actual UE transmission
            % time from the TransmissionStarted event at the target PUSCH
            % slot row in the UL scheduling log.

            data = eventStruct.EventData;

            % Determine carrier index based on simulation type
            if obj.IsNTNSimulation
                carrierIdx = find(obj.GNB.ServiceLinkCarrierFrequency(2) == data.CenterFrequency, 1);
            else
                carrierIdx = find(obj.GNB.ULCarrierFrequency == data.CenterFrequency, 1);
            end
            if isempty(carrierIdx) || ~ismember(carrierIdx, obj.CarrierID)
                return;
            end

            targetFrame = data.FrameInfo(1);
            targetSlot = data.FrameInfo(2);
            targetSymbol = data.FrameInfo(3);

            % Actual UE transmission time in ms
            ueTxTimeMs = eventStruct.Timestamp * 1e3;

            % Determine storage index for UL log
            if obj.DuplexMode == obj.FDDDuplexMode
                storageIdx = obj.UplinkIdx;
            else
                storageIdx = obj.DownlinkIdx;
            end

            % Compute row index in the log
            rowIdx = (targetFrame * obj.NumSlotsFrame + targetSlot) * obj.NumSym + targetSymbol + 1;
            colIdx = obj.ColumnIndexMap('UE Tx Time (ms) (UL only)');
            rntiIdx = data.RNTI;

            if rowIdx >= 1 && rowIdx <= size(obj.SchedulingLog{carrierIdx, storageIdx}, 1)
                obj.SchedulingLog{carrierIdx, storageIdx}{rowIdx, colIdx}(rntiIdx) = ueTxTimeMs;
            end
        end

        function [dlMetrics, ulMetrics, cellMetrics] = getMACMetrics(obj, firstSlot, lastSlot, rntiList)
            %getMACMetrics Returns the MAC metrics
            %
            % [DLMETRICS, ULMETRICS, CELLMETRICS] = getMACMetrics(OBJ, FIRSTSLOT,
            % LASTSLOT, RNTILIST) Returns the MAC metrics of the UEs with
            % specified RNTIs within the cell for both uplink and downlink
            % direction across obj.CarrierID carriers.
            %
            % FIRSTSLOT - Represents the starting slot number for
            % querying the metrics
            %
            % LASTSLOT -  Represents the ending slot for querying the metrics
            %
            % RNTILIST - Radio network temporary identifiers of the UEs
            %
            % DLMETRICS and ULMETRICS are struct arrays of size
            % [numel(rntiList), numel(CarrierID)] with fields:
            %   RNTI             - Radio network temporary identifier of the UE
            %   TransmittedBytes - Total number of bytes transmitted (newTx and reTx
            %                      combined)
            %   BufferStatus     - Current buffer status of the UE
            %   AssignedRBCount  - Number of resource blocks assigned to the UE
            %   RBsScheduled     - Total number resource blocks scheduled
            %
            % CELLMETRICS is a structure vector with following properties and contains
            % cell-wide metrics in downlink and uplink respectively
            %   DLTransmittedBytes - Total DL bytes (summed across carriers)
            %   DLRBsScheduled     - Total DL RBs scheduled (summed across carriers)
            %   ULTransmittedBytes - Total UL bytes (summed across carriers)
            %   ULRBsScheduled     - Total UL RBs scheduled (summed across carriers)

            carrierIndices = obj.CarrierID;
            numCarriersQuery = numel(carrierIndices);
            numTotalUEs = numel(obj.UEs);

            % Calculate the actual log start and end index
            stepLogStartIdx = (firstSlot-1) * obj.LogInterval + 1;
            stepLogEndIdx = lastSlot*obj.LogInterval;

            % Create structure for both DL and UL per carrier
            outStruct = struct('RNTI', 0, 'TransmittedBytes', 0, 'BufferStatus', 0, ...
                'AssignedRBCount', 0, 'RBsScheduled', 0);
            outputStruct = repmat(outStruct, [numel(rntiList) 2 numCarriersQuery]);

            % Store column index maps in variables and reuse in
            % calculations
            columnIndexMap = obj.ColumnIndexMap;
            freqAllocation = columnIndexMap(obj.FreqAllocLabel);
            txBytes = columnIndexMap('Transmitted Bytes');
            bufferStatusUEs = columnIndexMap('Buffer Status of UEs (bytes)');
            linktype = columnIndexMap('Tx Type');

            % Cell-wide metrics (summed across queried carriers)
            cellMetrics.DLTransmittedBytes = 0;
            cellMetrics.ULTransmittedBytes = 0;
            cellMetrics.ULRBsScheduled = 0;
            cellMetrics.DLRBsScheduled = 0;

            % Update the DL and UL metrics properties for each carrier
            for cIdx = 1:numCarriersQuery
                carrierIdx = carrierIndices(cIdx);
                assignedRBsStep = zeros(numTotalUEs, 2);
                macTxStep = zeros(numTotalUEs, 2);
                bufferStatus = zeros(numTotalUEs, 2);

                for idx = 1:min(obj.NumLogs, numel(obj.PlotIds))
                    plotId = obj.PlotIds(idx);
                    % Determine scheduling log index
                    if obj.DuplexMode == obj.FDDDuplexMode
                        schedLogIdx = plotId;
                    else
                        schedLogIdx = 1;
                    end

                    % Read the information of each slot and update the
                    % metrics properties
                    for i = stepLogStartIdx:obj.StepSize:stepLogEndIdx
                        slotLog = obj.SchedulingLog{carrierIdx, schedLogIdx}(i, :);
                        frequencyAssignment = slotLog{freqAllocation};
                        transmittedBytes = slotLog{txBytes};
                        ueBufferStatus = slotLog{bufferStatusUEs};
                        if(obj.DuplexMode == obj.TDDDuplexMode)
                            switch (slotLog{linktype})
                                case 'UL'
                                    linkIdx = 2; % Uplink information index
                                case 'DL'
                                    linkIdx = 1; % Downlink information index
                                otherwise
                                    continue;
                            end
                        else
                            linkIdx = plotId;
                        end

                        % Calculate the RBs allocated to a UE based on
                        % resource allocation type (RAT)
                        for ueIdx = 1 : numTotalUEs
                            if obj.ResourceAllocationType % RAT-1
                                numRBs = frequencyAssignment(ueIdx, 2);
                            else % RAT-0
                                numRBGs = sum(frequencyAssignment(ueIdx, :));
                                if frequencyAssignment(ueIdx, end) % If RBG is allocated
                                    % If the last RBG of BWP is assigned, then it might not
                                    % have same number of RBs as other RBG.
                                    if(mod(obj.NumRBs(plotId), obj.RBGSize(plotId)) == 0)
                                        numRBs = numRBGs * obj.RBGSize(plotId);
                                    else
                                        lastRBGSize = mod(obj.NumRBs(plotId), obj.RBGSize(plotId));
                                        numRBs = (numRBGs - 1) * obj.RBGSize(plotId) + lastRBGSize;
                                    end
                                else
                                    numRBs = numRBGs * obj.RBGSize(plotId);
                                end
                            end

                            assignedRBsStep(ueIdx, linkIdx) = assignedRBsStep(ueIdx, linkIdx) + numRBs;
                            macTxStep(ueIdx, linkIdx) = macTxStep(ueIdx, linkIdx) + transmittedBytes(ueIdx);
                            bufferStatus(ueIdx, linkIdx) = ueBufferStatus(ueIdx);
                        end
                    end
                end

                % Extract required metrics of the UEs specified in rntiList
                for idx = 1:numel(obj.PlotIds)
                    linkIdx = obj.PlotIds(idx);
                    for listIdx = 1:numel(rntiList)
                        ueIdx = rntiList(listIdx);
                        outputStruct(listIdx, linkIdx, cIdx).RNTI = rntiList(listIdx);
                        outputStruct(listIdx, linkIdx, cIdx).AssignedRBCount = assignedRBsStep(ueIdx, linkIdx);
                        outputStruct(listIdx, linkIdx, cIdx).TransmittedBytes = macTxStep(ueIdx, linkIdx);
                        outputStruct(listIdx, linkIdx, cIdx).BufferStatus = bufferStatus(ueIdx, linkIdx);
                    end
                end

                cellMetrics.DLTransmittedBytes = cellMetrics.DLTransmittedBytes + ...
                    sum([outputStruct(:, obj.DownlinkIdx, cIdx).TransmittedBytes]);
                cellMetrics.ULTransmittedBytes = cellMetrics.ULTransmittedBytes + ...
                    sum([outputStruct(:, obj.UplinkIdx, cIdx).TransmittedBytes]);
                cellMetrics.ULRBsScheduled = cellMetrics.ULRBsScheduled + ...
                    sum([outputStruct(:, obj.UplinkIdx, cIdx).AssignedRBCount]);
                cellMetrics.DLRBsScheduled = cellMetrics.DLRBsScheduled + ...
                    sum([outputStruct(:, obj.DownlinkIdx, cIdx).AssignedRBCount]);
            end
            dlMetrics = squeeze(outputStruct(:, obj.DownlinkIdx, :));
            ulMetrics = squeeze(outputStruct(:, obj.UplinkIdx, :));
        end

        function [resourceGridInfo, varargout] = getRBGridsInfo(obj, frameNumber, slotNumber, carrierIdx)
            %getRBGridsInfo Return the resource grid information
            %
            % getRBGridsInfo(OBJ, FRAMENUMBER, SLOTNUMBER, CARRIERIDX) Return the
            % resource grid status for the specified carrier(s)
            %
            % FRAMENUMBER - Frame number
            %
            % SLOTNUMBER - Slot number
            %
            % CARRIERIDX - Carrier index (optional, defaults to obj.CarrierID(1))
            %
            % RESOURCEGRIDINFO a 2x1 struct array containing resource grid
            % information for DL and UL. In FDD mode, the first element
            % contains DL resource grid information, and the second element
            % contains UL resource grid information. In TDD mode, the first
            % element contains resource grid information for both DL and
            % UL, and the second element is unused. Each element is a
            % struct with the following fields:
            %   - UEAssignment: A 2D cell array of size N-by-P, storing how
            %     UEs are assigned different time-frequency resources.
            %   - TxType: A 2D cell array of size N-by-P,
            %     storing transmission status (new-transmission or
            %     retransmission).
            %   - HarqID: A 2D cell array of size N-by-P,
            %     storing the HARQ process identifiers.
            % Dimension definitions:
            %     N: Number of slots (for slot-based scheduling) or symbols
            %     (for symbol-based scheduling)
            %     P: Number of RBs in the bandwidth

            if nargin == 3
                carrierIdx = obj.CarrierID(1);
            end
            numTotalUEs = numel(obj.UEs);

            % Initialize struct array
            if obj.SchedulingType % Symbol-based scheduling
                numRows = obj.NumSym;
            else % Slot-based scheduling
                numRows = obj.NumSlotsFrame;
            end
            resourceGridInfo = struct(...
                'UEAssignment', {cell(numRows, obj.NumRBs(1)); cell(numRows, obj.NumRBs(2))}, ...
                'TxType', {cell(numRows, obj.NumRBs(1)); cell(numRows, obj.NumRBs(2))}, ...
                'HarqID', {cell(numRows, obj.NumRBs(1)); cell(numRows, obj.NumRBs(2))} ...
                );

            % Determine log indices for scheduling
            if obj.SchedulingType % Symbol-based scheduling
                frameLogStartIdx = (frameNumber * obj.NumSlotsFrame * obj.LogInterval) + (slotNumber * obj.LogInterval);
                frameLogEndIdx = frameLogStartIdx + obj.LogInterval;
            else % Slot-based scheduling
                frameLogStartIdx = frameNumber * obj.NumSlotsFrame * obj.LogInterval;
                frameLogEndIdx = frameLogStartIdx + (obj.NumSlotsFrame * obj.LogInterval);
            end

            % Read the resource grid information from logs
            for idx = 1:min(obj.NumLogs, numel(obj.PlotIds))
                plotId = obj.PlotIds(idx);
                if obj.DuplexMode == obj.FDDDuplexMode
                    logIdx = obj.PlotIds(idx);
                else
                    logIdx = 1;
                    symSlotInfo = cell(14,1);
                end
                
                % Reset the resource grid status
                emptyGrid = cell(numRows, obj.NumRBs(logIdx));
                resourceGridInfo(logIdx).UEAssignment = emptyGrid;
                resourceGridInfo(logIdx).TxType = emptyGrid;
                resourceGridInfo(logIdx).HarqID = emptyGrid;

                % Store column index maps in variables and reuse in 
                % calculations
                columnIndexMap = obj.ColumnIndexMap;
                freqAllocation = columnIndexMap(obj.FreqAllocLabel);
                harqProcess = columnIndexMap('HARQ Process');
                linkType = columnIndexMap('Tx Type');

                slIdx = 0; % Counter to keep track of the number of symbols/slots to be plotted
                for i = frameLogStartIdx+1:obj.StepSize:frameLogEndIdx % For each symbol in the slot or each slot in the frame
                    slIdx = slIdx + 1;
                    slotLog = obj.SchedulingLog{carrierIdx, logIdx}(i, :);
                    
                    frequencyAssignment = slotLog{freqAllocation};
                    harqIds = slotLog{harqProcess};
                    txType = slotLog{linkType};
                    % Symbol or slot information
                    if obj.DuplexMode == obj.TDDDuplexMode
                        symSlotInfo{slIdx} = slotLog{columnIndexMap('Type')};
                    end
                    for j = 1 : numTotalUEs % For each UE
                        if (strcmp(txType(j), 'newTx') || strcmp(txType(j), 'newTx-Start') || strcmp(txType(j), 'newTx-InProgress') || strcmp(txType(j), 'newTx-End'))
                            type = 1; % New transmission
                        else
                            type = 2; % Retransmission
                        end

                        % Updating the resource grid status and related
                        % information
                        if obj.ResourceAllocationType % RAT-1
                            frequencyAllocation = frequencyAssignment(j, :);
                            startRBIndex = frequencyAllocation(1);
                            numRB = frequencyAllocation(2);
                            % Define the range of resource block indices
                            rbIndices = startRBIndex+1 : startRBIndex+numRB;
                            % Extract current contents
                            gridSlice = resourceGridInfo(logIdx).UEAssignment(slIdx, rbIndices);
                            reTxSlice = resourceGridInfo(logIdx).TxType(slIdx, rbIndices);
                            harqSlice = resourceGridInfo(logIdx).HarqID(slIdx, rbIndices);
                            % Append new values using cellfun
                            newGrid = cellfun(@(x) [x, j], gridSlice, 'UniformOutput', false);
                            newReTx = cellfun(@(x) [x, type], reTxSlice, 'UniformOutput', false);
                            newHarq = cellfun(@(x) [x, harqIds(j)], harqSlice, 'UniformOutput', false);
                            % Assign back to cell arrays
                            [resourceGridInfo(logIdx).UEAssignment{slIdx, rbIndices}] = deal(newGrid{:});
                            [resourceGridInfo(logIdx).TxType{slIdx, rbIndices}] = deal(newReTx{:});
                            [resourceGridInfo(logIdx).HarqID{slIdx, rbIndices}] = deal(newHarq{:});
                        else % RAT-0
                            RBGAllocationBitmap = frequencyAssignment(j, :);
                            for k=1:numel(RBGAllocationBitmap) % For all RBGs
                                if(RBGAllocationBitmap(k) == 1)
                                    % Calculate start and end RB indices
                                    startRBIndex = (k - 1) * obj.RBGSize(plotId) + 1;
                                    endRBIndex = k * obj.RBGSize(plotId);
                                    if k == numel(RBGAllocationBitmap) && mod(obj.NumRBs(plotId), obj.RBGSize(plotId)) ~= 0
                                        % If it is the last RBG and it does not have the same number of RBs as other RBGs
                                        endRBIndex = (k - 1) * obj.RBGSize(plotId) + mod(obj.NumRBs(plotId), obj.RBGSize(plotId));
                                    end
                                    % Define the range of resource block indices
                                    rbIndices = startRBIndex:endRBIndex;
                                    % Extract current contents
                                    gridSlice = resourceGridInfo(logIdx).UEAssignment(slIdx, rbIndices);
                                    reTxSlice = resourceGridInfo(logIdx).TxType(slIdx, rbIndices);
                                    harqSlice = resourceGridInfo(logIdx).HarqID(slIdx, rbIndices);
                                    % Append new values using cellfun
                                    newGrid = cellfun(@(x) [x, j], gridSlice, 'UniformOutput', false);
                                    newReTx = cellfun(@(x) [x, type], reTxSlice, 'UniformOutput', false);
                                    newHarq = cellfun(@(x) [x, harqIds(j)], harqSlice, 'UniformOutput', false);
                                    % Assign back to cell arrays
                                    [resourceGridInfo(logIdx).UEAssignment{slIdx, rbIndices}] = deal(newGrid{:});
                                    [resourceGridInfo(logIdx).TxType{slIdx, rbIndices}] = deal(newReTx{:});
                                    [resourceGridInfo(logIdx).HarqID{slIdx, rbIndices}] = deal(newHarq{:});
                                end
                            end
                        end
                    end
                end
            end
            if obj.DuplexMode == obj.TDDDuplexMode
                varargout{1} = symSlotInfo;
            end
        end

        function [dlMCSInfo, ulMCSInfo] = getMCSRBGridsInfo(obj, frameNumber, slotNumber, carrierIdx)
            %getMCSRBGridsInfo Return MCS information for the specified carrier
            %
            % getMCSRBGridsInfo(OBJ, FRAMENUMBER, SLOTNUMBER, CARRIERIDX) Return
            % resource grid MCS information
            %
            % FRAMENUMBER - Frame number
            %
            % SLOTNUMBER - Slot number
            %
            % CARRIERIDX - Carrier index (optional, defaults to obj.CarrierID(1))
            %
            % DLMCSINFO - Downlink MCS information
            %
            % ULMCSINFO - Uplink MCS information

            if nargin == 3
                carrierIdx = obj.CarrierID(1);
            end
            numTotalUEs = numel(obj.UEs);

            mcsInfo = cell(2, 1);
            lwRowIndex = frameNumber * obj.NumSlotsFrame * obj.LogInterval;
            if obj.SchedulingType % Symbol-based scheduling
                upRowIndex = lwRowIndex + (slotNumber + 1) * obj.LogInterval;
            else % Slot-based scheduling
                upRowIndex = lwRowIndex + (slotNumber * obj.LogInterval) + 1;
            end

            if (obj.DuplexMode == obj.TDDDuplexMode) % TDD
                if ~isempty(obj.SchedulingLog{carrierIdx, obj.DownlinkIdx})
                    % Get the symbols types in the current frame
                    symbolTypeInFrame = obj.SchedulingLog{carrierIdx, 1}(lwRowIndex+1:upRowIndex, obj.ColumnIndexMap('Type'));

                    % Initialize MCS info
                    mcsInfo{obj.DownlinkIdx} = -1*ones(numTotalUEs, obj.NumRBs(obj.DownlinkIdx));
                    mcsInfo{obj.UplinkIdx} = -1*ones(numTotalUEs, obj.NumRBs(obj.UplinkIdx));

                    if obj.SchedulingType % Symbol-based scheduling
                        % Find the last DL and UL symbols in the frame
                        dlIdx = find(strcmp(symbolTypeInFrame, 'DL'), 1, 'last');
                        ulIdx = find(strcmp(symbolTypeInFrame, 'UL'), 1, 'last');
                        % Assign MCS for the last DL/UL symbols
                        if ~isempty(dlIdx)
                            mcsInfo{obj.DownlinkIdx} = assignMCSInfo(obj, obj.DownlinkIdx, lwRowIndex+dlIdx, carrierIdx);
                        end
                        if ~isempty(ulIdx)
                            mcsInfo{obj.UplinkIdx} = assignMCSInfo(obj, obj.DownlinkIdx, lwRowIndex+ulIdx, carrierIdx);
                        end
                    else % Slot-based scheduling
                        % Find first symbols of all slots
                        slotFirstSymIdx = 1:obj.NumSym:numel(symbolTypeInFrame);
                        slotTypes = symbolTypeInFrame(slotFirstSymIdx);

                        % Find the latest slots where the first symbol is DL or UL
                        dlSlotIdx = find(strcmp(slotTypes, 'DL'), 1, 'last');
                        ulSlotIdx = find(strcmp(slotTypes, 'UL'), 1, 'last');

                        % Assign MCS from the first symbol of the latest DL/UL slots
                        if ~isempty(dlSlotIdx)
                            dlSymIdx = slotFirstSymIdx(dlSlotIdx);
                            mcsInfo{obj.DownlinkIdx} = assignMCSInfo(obj, obj.DownlinkIdx, lwRowIndex+dlSymIdx, carrierIdx);
                        end
                        if ~isempty(ulSlotIdx)
                            ulSymIdx = slotFirstSymIdx(ulSlotIdx);
                            mcsInfo{obj.UplinkIdx} = assignMCSInfo(obj, obj.DownlinkIdx, lwRowIndex+ulSymIdx, carrierIdx);
                        end
                    end
                end
            else
                for idx=1:numel(obj.PlotIds)
                    plotId = obj.PlotIds(idx);
                    if ~isempty(obj.SchedulingLog{carrierIdx, plotId})
                        mcsInfo{plotId} = assignMCSInfo(obj, plotId, upRowIndex, carrierIdx);
                    end
                end
            end
            dlMCSInfo = mcsInfo{obj.DownlinkIdx};
            ulMCSInfo = mcsInfo{obj.UplinkIdx};
        end

        function mcsInfo = assignMCSInfo(obj, plotId, upRowIndex, carrierIdx)
            %assignMCSInfo Assigns MCS values to allocated RBs for a given plotId and upRowIndex
            
            if nargin == 3
                carrierIdx = obj.CarrierID(1);
            end
            numTotalUEs = numel(obj.UEs);
            numRBs = obj.NumRBs(plotId);
            mcsInfo = -1 * ones(numTotalUEs, numRBs); % Initialize with -1

            % Fetch MCS and frequency allocation
            columnIndexMap = obj.ColumnIndexMap;
            mcsValues = obj.SchedulingLog{carrierIdx, plotId}{upRowIndex, columnIndexMap('MCS Index')}; % [NumUEs × 1]
            freqAlloc = obj.SchedulingLog{carrierIdx, plotId}{upRowIndex, columnIndexMap(obj.FreqAllocLabel)}; % [NumUEs × 2] for RAT1, [NumUEs × numRBG] for RAT0

            if obj.ResourceAllocationType % RAT1: freqAlloc is [NumUEs × 2] with [startRB, numRBs]
                % Extract RB ranges (handle 0-based indexing)
                startRBs = freqAlloc(:, 1) + (freqAlloc(:, 1) >= 0); % Convert 0-based to 1-based
                numRBsAllocated = freqAlloc(:, 2); % Number of RBs
                allocatedUEs = numRBsAllocated > 0; % Identify allocated UEs

                if ~any(allocatedUEs)
                    return; % No allocated UEs; return -1 matrix
                end

                % Filter allocated UEs
                startRBs = startRBs(allocatedUEs);
                numRBsAllocated = numRBsAllocated(allocatedUEs);
                mcsValues = mcsValues(allocatedUEs);
                ueIndicesRaw = find(allocatedUEs); % UE indices (1 to NumUEs)
                endRBs = startRBs + numRBsAllocated - 1; % Ending RB indices

                % Generate indices for all allocated RBs
                totalAllocatedRBs = sum(numRBsAllocated); % Total allocated RBs
                ueIndices = zeros(totalAllocatedRBs, 1); % Preallocate UE indices
                rbIndices = zeros(totalAllocatedRBs, 1); % Preallocate RB indices
                offset = 0;
                for i = 1:numel(ueIndicesRaw)
                    count = numRBsAllocated(i);
                    range = offset + (1:count);
                    ueIndices(range) = ueIndicesRaw(i); % Assign UE index
                    rbIndices(range) = startRBs(i):endRBs(i); % Assign RB positions
                    offset = offset + count;
                end
                mcsValuesExpanded = repelem(mcsValues, numRBsAllocated); % MCS values for each RB
            else % RAT0: freqAlloc is [NumUEs x numRBG] bitmap
                numRBG = size(freqAlloc, 2);
                allocatedUEs = any(freqAlloc, 2); % UEs with at least one RBG allocated

                if ~any(allocatedUEs)
                    return; % No allocated UEs; return -1 matrix
                end

                % Filter allocated UEs
                freqAlloc = freqAlloc(allocatedUEs, :);
                mcsValues = mcsValues(allocatedUEs);
                ueIndicesRaw = find(allocatedUEs); % UE indices (1 to NumUEs)

                % Compute RBG sizes (TR 38.214)
                P = ceil(numRBs / numRBG);
                numRBsPerRBG = P * ones(1, numRBG);
                remainder = mod(numRBs, P);
                if remainder > 0
                    numRBsPerRBG(end) = remainder;
                end

                % Compute start and end RB indices for each RBG
                startRBsRBG = [1, cumsum(numRBsPerRBG(1:end-1)) + 1]; % 1-based
                endRBsRBG = cumsum(numRBsPerRBG); % Inclusive end RB

                % Generate indices for all allocated RBs
                totalAllocatedRBs = sum(freqAlloc * numRBsPerRBG'); % Total RBs across UEs
                ueIndices = zeros(totalAllocatedRBs, 1); % Preallocate UE indices
                rbIndices = zeros(totalAllocatedRBs, 1); % Preallocate RB indices
                offset = 0;
                for i = 1:numel(ueIndicesRaw)
                    rbgMask = freqAlloc(i, :); % Bitmap for UE i
                    if ~any(rbgMask)
                        continue; % Skip if no RBGs allocated
                    end
                    numRBsUE = sum(rbgMask .* numRBsPerRBG); % Total RBs for UE
                    range = offset + (1:numRBsUE);
                    ueIndices(range) = ueIndicesRaw(i); % Assign UE index
                    % Generate RB indices for allocated RBGs
                    rbgIndices = find(rbgMask);
                    rbRanges = arrayfun(@(j) startRBsRBG(j):endRBsRBG(j), rbgIndices, 'UniformOutput', false);
                    rbIndices(range) = [rbRanges{:}]; % Concatenate RB ranges
                    offset = offset + numRBsUE;
                end
                mcsValuesExpanded = repelem(mcsValues, sum(freqAlloc .* numRBsPerRBG, 2)); % MCS values for each RB
            end

            % Assign MCS to allocated RBs using linear indexing
            linearIdx = sub2ind([numTotalUEs, numRBs], ueIndices, rbIndices);
            mcsInfo(linearIdx) = mcsValuesExpanded;
        end

        function logCellSchedulingStats(obj, ~, ~)
            %logCellSchedulingStats Log the MAC layer statistics
            %
            % logCellSchedulingStats(OBJ, ~, ~) Logs the scheduling information based
            % on the received event data

            linkDir = obj.PlotIds;
            linkDir = linkDir - 1;
            if numel(obj.PlotIds) == 2
                linkDir = 2;
            end
            gNB = obj.GNB;
            ueNode = obj.UEs;
            obj.TraceIndexCounter = obj.TraceIndexCounter + 1;
            symbolNum = (obj.TraceIndexCounter - 1) * obj.LogGranularity + 1;
            numTotalUEs = numel(obj.UEs);

            for carrierIdx = obj.CarrierID
                connectedUEs = obj.UERNTIsPerCarrier{carrierIdx};
                numUEsCC = obj.NumUEsPerCarrier(carrierIdx);
                uePhyIdx = obj.UECarrierIndexMap{carrierIdx};

                statusInfo.BufferSize = sum(gNB.MACEntity.LCHBufferStatus,2);
                scheduler = gNB.MACEntity.Scheduler;
                statusInfo.ULChannelQuality = [scheduler.UEContext.CSIMeasurementUL];
                gNBStatistics = gNB.statistics("all");

                % Read Tx bytes sent for each UE
                allTxBytes = [gNBStatistics.MAC.Destinations.TransmittedBytes]';
                obj.UEMetricsDL{carrierIdx}(:, 1) = allTxBytes;
                obj.UEMetricsDL{carrierIdx}(:, 2) = statusInfo.BufferSize; % Read pending buffer (in bytes) on gNB, for all the UEs

                % Read the NDI, DL and UL channel quality for this carrier
                % for each of the UEs
                for posIdx = 1:numUEsCC
                    ueIdx = connectedUEs(posIdx);
                    ccIdx = uePhyIdx(posIdx);
                    obj.HARQProcessStatusUL{carrierIdx}(ueIdx, :) = obj.UEs(ueIdx).MACEntity.ComponentCarrier(ccIdx).HARQNDIUL;
                    obj.HARQProcessStatusDL{carrierIdx}(ueIdx, :) = obj.UEs(ueIdx).MACEntity.ComponentCarrier(ccIdx).HARQNDIDL;
                    % Read the UL channel quality at gNB for each of the UEs for logging
                    obj.UplinkChannelQuality{carrierIdx}{ueIdx} = statusInfo.ULChannelQuality(ueIdx);
                    % Read the DL channel quality at UEs for logging
                    ueStatusInfo.DLChannelQuality = ueNode(ueIdx).MACEntity.ComponentCarrier(ccIdx).CSIMeasurement;
                    ueStatusInfo.BufferSize = sum(ueNode(ueIdx).MACEntity.LCGBufferStatus);
                    ueStatistics = ueNode(ueIdx).statistics();
                    obj.DownlinkChannelQuality{carrierIdx}{ueIdx} = ueStatusInfo.DLChannelQuality;
                    % Read transmitted bytes for the UE in the current TTI for logging
                    obj.UEMetricsUL{carrierIdx}(ueIdx, 1) = ueStatistics.MAC.TransmittedBytes;
                    obj.UEMetricsUL{carrierIdx}(ueIdx, 2) = ueStatusInfo.BufferSize; % Read pending buffer (in bytes) on UE
                end

                % Store the scheduling logs for this carrier
                if obj.DuplexMode == 1 % TDD
                    % Get current symbol type: DL/UL/Guard
                    numSlots = floor((symbolNum-1)/14);
                    dlulSlotIndex = mod(numSlots, scheduler.CellConfig(carrierIdx).NumDLULPatternSlots);
                    symbolIndex = mod(symbolNum-1, 14);
                    symbolType = scheduler.CellConfig(carrierIdx).DLULSlotFormat(dlulSlotIndex+1, symbolIndex+1);
                    if(symbolType == 0 && linkDir ~= 1) % DL
                        metrics = obj.UEMetricsDL{carrierIdx};
                        metrics(:, 1) = metrics(:, 1) - obj.PrevUEMetricsDL{carrierIdx}(:, 1);
                        obj.PrevUEMetricsDL{carrierIdx} = obj.UEMetricsDL{carrierIdx};
                        logScheduling(obj, symbolNum, metrics, obj.DownlinkChannelQuality{carrierIdx}, obj.HARQProcessStatusDL{carrierIdx}, symbolType, carrierIdx);
                    elseif(symbolType == 1 && linkDir ~= 0) % UL
                        metrics = obj.UEMetricsUL{carrierIdx};
                        metrics(:, 1) = metrics(:, 1) - obj.PrevUEMetricsUL{carrierIdx}(:, 1);
                        obj.PrevUEMetricsUL{carrierIdx} = obj.UEMetricsUL{carrierIdx};
                        logScheduling(obj, symbolNum, metrics, obj.UplinkChannelQuality{carrierIdx}, obj.HARQProcessStatusUL{carrierIdx}, symbolType, carrierIdx);
                    else % Guard
                        logScheduling(obj, symbolNum, zeros(numTotalUEs, 3), cell(numTotalUEs, 0), zeros(numTotalUEs, obj.NumHARQ), symbolType, carrierIdx);
                    end
                else
                    % Store the scheduling logs
                    if linkDir ~= 1 %  DL
                        metrics = obj.UEMetricsDL{carrierIdx};
                        metrics(:, 1) = metrics(:, 1) - obj.PrevUEMetricsDL{carrierIdx}(:, 1);
                        obj.PrevUEMetricsDL{carrierIdx} = obj.UEMetricsDL{carrierIdx};
                        logScheduling(obj, symbolNum, metrics, obj.DownlinkChannelQuality{carrierIdx}, obj.HARQProcessStatusDL{carrierIdx}, 0, carrierIdx); % DL
                    end
                    if linkDir ~= 0 % UL
                        metrics = obj.UEMetricsUL{carrierIdx};
                        metrics(:, 1) = metrics(:, 1) - obj.PrevUEMetricsUL{carrierIdx}(:, 1);
                        obj.PrevUEMetricsUL{carrierIdx} = obj.UEMetricsUL{carrierIdx};
                        logScheduling(obj, symbolNum, metrics, obj.UplinkChannelQuality{carrierIdx}, obj.HARQProcessStatusUL{carrierIdx}, 1, carrierIdx); % UL
                    end
                end
            end

            % Invoke the dependent events after every slot
            if obj.SchedulingType
                if mod(symbolNum, 14) == 0 && symbolNum > 1
                    % Invoke the events at the last symbol of the slot
                    invokeDepEvents(obj, (symbolNum/14));
                end
            else
                % Invoke the events at the first symbol of the last slot in a frame
                if mod(symbolNum-1, 14) == 0 && symbolNum > 1
                    invokeDepEvents(obj, ((symbolNum-1)/14)+1);
                end
            end
        end

        function logScheduling(obj, symbolNumSimulation, UEMetrics, UECQIs, HarqProcessStatus, type, carrierIdx)
            %logScheduling Log the scheduling operations
            %
            % logScheduling(OBJ, SYMBOLNUMSIMULATION, UEMETRICS, UECQIS,
            % HARQPROCESSSTATUS, TYPE, CARRIERIDX) Logs the scheduling
            % operations based on the input arguments
            %
            % SYMBOLNUMSIMULATION - Cumulative symbol number in the
            % simulation
            %
            % UEMETRICS - N-by-P matrix where N represents the total number of
            % UEs and P represents the number of metrics collected.
            %
            % UECQIS - N-by-1 cell array where N represents the total number of
            % UEs. Each cell contains the channel quality for that UE.
            %
            % HARQPROCESSSTATUS - N-by-M matrix where N is the total number of
            % UEs and M is the number of HARQ processes.
            %
            % TYPE - Type will be based on scheduling type.
            %        - In slot based scheduling type takes two values.
            %          type = 0, represents the downlink and type = 1,
            %          represents uplink.
            %
            %        - In symbol based scheduling type takes three values.
            %          type = 0, represents the downlink, type = 1,
            %          represents uplink and type = 2 represents guard.
            %
            % CARRIERIDX - Index of the carrier (1 to NumCarriers)

            % Determine the log index based on link type and duplex mode
            if obj.DuplexMode == obj.FDDDuplexMode
                if  type == 0
                    linkIndex = obj.DownlinkIdx; % Downlink log
                else
                    linkIndex = obj.UplinkIdx; % Uplink log
                end
            else
                % TDD
                linkIndex = 1;
            end

            % Calculate symbol number in slot (0-13), slot number in frame
            % (0-obj.NumSlotsFrame), and frame number in the simulation.
            slotDuration = 10/obj.NumSlotsFrame;
            obj.CurrSymbol = mod(symbolNumSimulation - 1, obj.NumSym);
            obj.CurrSlot = mod(floor((symbolNumSimulation - 1)/obj.NumSym), obj.NumSlotsFrame);
            obj.CurrFrame = floor((symbolNumSimulation-1)/(obj.NumSym * obj.NumSlotsFrame));
            timestamp = obj.CurrFrame * 10 + (obj.CurrSlot * slotDuration) + (obj.CurrSymbol * (slotDuration / 14));

            columnMap = obj.ColumnIndexMap;
            obj.SchedulingLog{carrierIdx, linkIndex}{symbolNumSimulation, columnMap('Timestamp (ms)')} = timestamp;
            obj.SchedulingLog{carrierIdx, linkIndex}{symbolNumSimulation, columnMap('Frame')} = obj.CurrFrame;
            obj.SchedulingLog{carrierIdx, linkIndex}{symbolNumSimulation, columnMap('Slot')} = obj.CurrSlot;
            if obj.SchedulingType % Symbol based scheduling
                obj.SchedulingLog{carrierIdx, linkIndex}{symbolNumSimulation, columnMap('Symbol Number')} = obj.CurrSymbol;
            end

            if(obj.DuplexMode == obj.TDDDuplexMode) % TDD
                % Log the type: DL/UL/Guard
                switch(type)
                    case 0
                        symbolTypeDesc = 'DL';
                    case 1
                        symbolTypeDesc = 'UL';
                    case 2
                        symbolTypeDesc = 'Guard';
                end
                obj.SchedulingLog{carrierIdx, linkIndex}{symbolNumSimulation, columnMap('Type')} = symbolTypeDesc;
            end

            obj.SchedulingLog{carrierIdx, linkIndex}{symbolNumSimulation, columnMap('Channel Quality')} = UECQIs;
            obj.SchedulingLog{carrierIdx, linkIndex}{symbolNumSimulation, columnMap('HARQ NDI Status')} = HarqProcessStatus;
            obj.SchedulingLog{carrierIdx, linkIndex}{symbolNumSimulation, columnMap('Transmitted Bytes')} = UEMetrics(:, 1); % Transmitted bytes sent by UEs
            obj.SchedulingLog{carrierIdx, linkIndex}{symbolNumSimulation, columnMap('Buffer Status of UEs (bytes)')} = UEMetrics(:, 2); % Current buffer status of UEs in bytes
        end

        function logSchedulingGrants(obj, ~, eventData)
            %logSchedulingGrants Log the scheduling grant information
            %
            % logSchedulingGrants(OBJ, EVENTSOURCE, EVENTDATA) Logs the
            % scheduling grant information for each carrier in obj.CarrierID.
            %
            % EVENTSOURCE - Event source object
            %
            % EVENTDATA - Event data

            currFrame = eventData.Data.TimingInfo(1);
            currSlot = eventData.Data.TimingInfo(2);
            currSymbol = eventData.Data.TimingInfo(3);
            symbolNumSimulation = (currFrame * obj.NumSlotsFrame + currSlot) * obj.NumSym + currSymbol;
            grantList = {};
            columnMap = obj.ColumnIndexMap;
            grantLogsColumnIndexMap = obj.GrantLogsColumnIndexMap;
            grantList{1} = eventData.Data.DLGrants;
            grantList{2} = eventData.Data.ULGrants;
            numTotalUEs = numel(obj.UEs);

            for grantIdx = 1:2
                if(obj.DuplexMode == obj.TDDDuplexMode) % TDD
                    % Grant is received always in DL
                    linkIndex = 1;
                else
                    % Depending on PlotIds linkIndex will be set
                    if isscalar(obj.PlotIds)
                        % Either one of UL or DL logging is set
                        linkIndex = obj.PlotIds;
                    else
                        % If both UL & DL logging is required
                        linkIndex = grantIdx;
                    end
                end
                resourceAssignments = grantList{grantIdx};
                for j = 1:numel(resourceAssignments)
                    carrierIdx = resourceAssignments(j).GNBCarrierIndex;
                    % Store logs only for carriers in CarrierID
                    if ismember(carrierIdx, obj.CarrierID)
                        % Fill logs w.r.t. each assignment
                        assignment = resourceAssignments(j);
                        % Calculate row number in the logs, for the Tx start
                        % symbol
                        logIndex = (currFrame * obj.NumSlotsFrame * obj.NumSym) +  ...
                            ((currSlot + assignment.SlotOffset) * obj.NumSym) + assignment.StartSymbol + 1;

                        allottedUE = assignment.RNTI;

                        % Log in TDD mode
                        if obj.DuplexMode == obj.TDDDuplexMode
                            obj.SchedulingLog{carrierIdx, linkIndex}{symbolNumSimulation+1, columnMap('Type')} = 'DL';
                        end

                        % Fill the start Tx symbol logs
                        obj.SchedulingLog{carrierIdx, linkIndex}{logIndex, columnMap(obj.FreqAllocLabel)}(allottedUE, :) = assignment.FrequencyAllocation;
                        obj.SchedulingLog{carrierIdx, linkIndex}{logIndex, columnMap('MCS Index')}(allottedUE) = assignment.MCSIndex;
                        obj.SchedulingLog{carrierIdx, linkIndex}{logIndex, columnMap('HARQ Process')}(allottedUE) = assignment.HARQID;
                        obj.SchedulingLog{carrierIdx, linkIndex}{logIndex, columnMap('NDI')}(allottedUE) = assignment.NDI;
                        if obj.SchedulingType % Symbol based scheduling
                            obj.SchedulingLog{carrierIdx, linkIndex}{logIndex, columnMap('Tx Type')}(allottedUE) = {[assignment.Type, '-Start']};
                            % Fill the logs from the symbol after Tx start, up to
                            % the symbol before Tx end
                            for k = 1:assignment.NumSymbols-2
                                obj.SchedulingLog{carrierIdx, linkIndex}{logIndex + k, columnMap(obj.FreqAllocLabel)}(allottedUE, :) = assignment.FrequencyAllocation;
                                obj.SchedulingLog{carrierIdx, linkIndex}{logIndex + k, columnMap('MCS Index')}(allottedUE) = assignment.MCSIndex;
                                obj.SchedulingLog{carrierIdx, linkIndex}{logIndex + k, columnMap('HARQ Process')}(allottedUE) = assignment.HARQID;
                                obj.SchedulingLog{carrierIdx, linkIndex}{logIndex + k, columnMap('NDI')}(allottedUE) = assignment.NDI;
                                obj.SchedulingLog{carrierIdx, linkIndex}{logIndex + k, columnMap('Tx Type')}(allottedUE) = {[assignment.Type, '-InProgress']};
                            end

                            % Fill the last Tx symbol logs
                            obj.SchedulingLog{carrierIdx, linkIndex}{logIndex + assignment.NumSymbols -1, columnMap(obj.FreqAllocLabel)}(allottedUE, :) = assignment.FrequencyAllocation;
                            obj.SchedulingLog{carrierIdx, linkIndex}{logIndex + assignment.NumSymbols -1, columnMap('MCS Index')}(allottedUE) = assignment.MCSIndex;
                            obj.SchedulingLog{carrierIdx, linkIndex}{logIndex + assignment.NumSymbols -1, columnMap('HARQ Process')}(allottedUE) = assignment.HARQID;
                            obj.SchedulingLog{carrierIdx, linkIndex}{logIndex + assignment.NumSymbols -1, columnMap('NDI')}(allottedUE) = assignment.NDI;
                            obj.SchedulingLog{carrierIdx, linkIndex}{logIndex + assignment.NumSymbols -1, columnMap('Tx Type')}(allottedUE) = {[assignment.Type, '-End']};
                        else % Slot based scheduling
                            obj.SchedulingLog{carrierIdx, linkIndex}{logIndex, columnMap('Tx Type')}(allottedUE) = {assignment.Type};
                        end
                        obj.GrantCount(carrierIdx) = obj.GrantCount(carrierIdx) + 1;
                        gc = obj.GrantCount(carrierIdx);
                        obj.GrantLog{carrierIdx}{gc, grantLogsColumnIndexMap('RNTI')} = assignment.RNTI;
                        slotNumGrant = mod(currSlot + assignment.SlotOffset, obj.NumSlotsFrame);
                        if(currSlot + assignment.SlotOffset >= obj.NumSlotsFrame)
                            numFrames = floor((currSlot + assignment.SlotOffset)/obj.NumSlotsFrame);
                            frameNumGrant = currFrame + numFrames; % Assignment is for a slot in future frame
                        else
                            frameNumGrant = currFrame;
                        end
                        obj.GrantLog{carrierIdx}{gc, grantLogsColumnIndexMap('Frame')} = frameNumGrant;
                        obj.GrantLog{carrierIdx}{gc, grantLogsColumnIndexMap('Slot')} = slotNumGrant;
                        obj.GrantLog{carrierIdx}{gc, grantLogsColumnIndexMap(obj.FreqAllocLabel)} = assignment.FrequencyAllocation;
                        obj.GrantLog{carrierIdx}{gc, grantLogsColumnIndexMap('Start Symbol')} = assignment.StartSymbol;
                        obj.GrantLog{carrierIdx}{gc, grantLogsColumnIndexMap('Num Symbols')} = assignment.NumSymbols;
                        obj.GrantLog{carrierIdx}{gc, grantLogsColumnIndexMap('MCS Index')} = assignment.MCSIndex;
                        obj.GrantLog{carrierIdx}{gc, grantLogsColumnIndexMap('NumLayers')} = assignment.NumLayers;
                        obj.GrantLog{carrierIdx}{gc, grantLogsColumnIndexMap('HARQ Process')} = assignment.HARQID;
                        obj.GrantLog{carrierIdx}{gc, grantLogsColumnIndexMap('NDI')} = assignment.NDI;
                        obj.GrantLog{carrierIdx}{gc, grantLogsColumnIndexMap('RV')} = assignment.RV;
                        obj.GrantLog{carrierIdx}{gc, grantLogsColumnIndexMap('Tx Type')} = assignment.Type;
                        if(isfield(assignment, 'FeedbackSlotOffset'))
                            % DL grant
                            obj.GrantLog{carrierIdx}{gc, grantLogsColumnIndexMap('Feedback Slot Offset (DL grants only)')} = assignment.FeedbackSlotOffset;
                            obj.GrantLog{carrierIdx}{gc, grantLogsColumnIndexMap('Grant Type')} = 'DL';
                        else
                            % UL grant
                            obj.GrantLog{carrierIdx}{gc, grantLogsColumnIndexMap('Grant Type')} = 'UL';
                        end
                    end
                end
            end
        end

        function varargout = getSchedulingLogs(obj)
            %getSchedulingLogs Get the per-symbol logs of the whole simulation
            %
            % [DL, UL] = getSchedulingLogs(OBJ) Returns the
            % scheduling logs for the specified carrier(s). If CARRIERIDX is
            % not specified, defaults to obj.CarrierID. CARRIERIDX can be
            % a scalar or vector of carrier indices.

            carrierIdx = obj.CarrierID;
            % Get keys of columns (i.e. column names) in sorted order of values (i.e. column indices)
            numTotalUEs = numel(obj.UEs);
            if numTotalUEs == 0
                varargout = {[],[]};
                return;
            end
            [~, idx] = sort(cell2mat(values(obj.ColumnIndexMap)));
            columnTitles = keys(obj.ColumnIndexMap);
            columnTitles = columnTitles(idx);

            numCarriersQuery = numel(carrierIdx);
            % Each output is a cell array with one element per carrier
            varargout = cell(obj.NumLogs, 1);
            for logIdx = 1:obj.NumLogs
                varargout{logIdx} = cell(1, numCarriersQuery);
            end

            for cIdx = 1:numCarriersQuery
                c = carrierIdx(cIdx);
                for logIdx = 1:obj.NumLogs
                    if isempty(obj.SchedulingLog{c, logIdx})
                        continue;
                    end
                    if obj.SchedulingType
                        % Symbol based scheduling
                        finalLogIndex = (obj.CurrFrame)*obj.NumSlotsFrame*obj.NumSym + (obj.CurrSlot)*obj.NumSym + obj.CurrSymbol + 1;
                        obj.SchedulingLog{c, logIdx} = obj.SchedulingLog{c, logIdx}(1:finalLogIndex, :);
                        varargout{logIdx}{cIdx} = [columnTitles; obj.SchedulingLog{c, logIdx}(1:finalLogIndex, :)];
                    else
                        % Slot based scheduling
                        finalLogIndex = (obj.CurrFrame)*obj.NumSlotsFrame*obj.NumSym + (obj.CurrSlot+1)*obj.NumSym;
                        obj.SchedulingLog{c, logIdx} = obj.SchedulingLog{c, logIdx}(1:finalLogIndex, :);
                        % For slot based scheduling: keep 1 row per slot
                        finalLog = obj.SchedulingLog{c, logIdx}(1:obj.NumSym:finalLogIndex, :);

                        if obj.HasSpecialSlot % If there is a special slot (for TDD mode)
                            gNB = obj.GNB;
                            dlulConfig = gNB.DLULConfigTDD;
                            logSize = size(finalLog, 1);
                            % Calculate the indices for special slots within the DL/UL pattern
                            specialSlotIndicies = dlulConfig.NumDLSlots:obj.NumDLULPatternSlots:logSize;
                            for sidx = 1:numel(specialSlotIndicies)
                                % Update the 'Type' column for each special slot
                                finalLog{specialSlotIndicies(sidx)+1, obj.ColumnIndexMap('Type')} = 'S';
                            end
                        end
                        varargout{logIdx}{cIdx} = [columnTitles; finalLog];
                    end
                end
            end

            % If scalar carrier, unwrap the cell array for backward compatibility
            if numCarriersQuery == 1
                for logIdx = 1:obj.NumLogs
                    varargout{logIdx} = varargout{logIdx}{1};
                end
            end
        end

        function logs = getGrantLogs(obj)
            %getGrantLogs Get the scheduling assignment logs for the specified carrier(s)
            %
            % LOGS = getGrantLogs(OBJ) Returns the grant logs
            % for the specified carrier(s).
            
            carrierIdx = obj.CarrierID;
            % Get keys of columns (i.e. column names) in sorted order of values (i.e. column indices)
            numTotalUEs = numel(obj.UEs);
            if numTotalUEs == 0
                logs = [];
                return;
            end
            [~, idx] = sort(cell2mat(values(obj.GrantLogsColumnIndexMap)));
            columnTitles = keys(obj.GrantLogsColumnIndexMap);
            columnTitles = columnTitles(idx);

            numCarriersQuery = numel(carrierIdx);
            logs = cell(1, numCarriersQuery);
            for cIdx = 1:numCarriersQuery
                c = carrierIdx(cIdx);
                gc = obj.GrantCount(c);
                obj.GrantLog{c} = obj.GrantLog{c}(1:gc, :);
                logs{cIdx} = [columnTitles; obj.GrantLog{c}];
            end

            % If scalar carrier, unwrap the cell array for backward compatibility
            if numCarriersQuery == 1
                logs = logs{1};
            end
        end

        function [dlStats, ulStats] = getPerformanceIndicators(obj)
            %getPerformanceIndicators Outputs the aggregate data rate, spectral
            % efficiency values across all carriers
            %
            % DLSTATS - Row vector of length 4, with these statistics in
            %           the downlink direction: Theoretical peak data rate,
            %           achieved data rate, theoretical peak spectral
            %           efficiency, achieved spectral efficiency
            % ULSTATS - Row vector of length 4, with these statistics in
            %           the uplink direction: Theoretical peak data rate,
            %           achieved data rate, theoretical peak spectral
            %           efficiency, achieved spectral efficiency

            carrierIdx = obj.CarrierID;
            transmittedBytes = obj.ColumnIndexMap('Transmitted Bytes');
            totalDLTxBytes = 0;
            totalULTxBytes = 0;

            % Sum transmitted bytes across all queried carriers
            for cIdx = 1:numel(carrierIdx)
                c = carrierIdx(cIdx);
                if obj.DuplexMode == obj.FDDDuplexMode
                    if ismember(obj.DownlinkIdx, obj.PlotIds)
                        totalDLTxBytes = totalDLTxBytes + sum(cell2mat(obj.SchedulingLog{c, obj.DownlinkIdx}(:, transmittedBytes)));
                    end
                    if ismember(obj.UplinkIdx, obj.PlotIds)
                        totalULTxBytes = totalULTxBytes + sum(cell2mat(obj.SchedulingLog{c, obj.UplinkIdx}(:, transmittedBytes)));
                    end
                else
                    linkType = obj.ColumnIndexMap('Type');
                    dlIdx = strcmp(obj.SchedulingLog{c, 1}(:, linkType), 'DL');
                    totalDLTxBytes = totalDLTxBytes + sum(cell2mat(obj.SchedulingLog{c, 1}(dlIdx, transmittedBytes)));
                    ulIdx = strcmp(obj.SchedulingLog{c, 1}(:, linkType), 'UL');
                    totalULTxBytes = totalULTxBytes + sum(cell2mat(obj.SchedulingLog{c, 1}(ulIdx, transmittedBytes)));
                end
            end
            dlStats = zeros(1,4);
            ulStats = zeros(1,4);
            % Downlink stats
            if ismember(obj.DownlinkIdx, obj.PlotIds)
                dlStats(1) = obj.PeakDataRateDL;
                dlStats(2) = totalDLTxBytes * 8 ./ (obj.NumFrames * 0.01 * 1000 * 1000); % Mbps
                dlStats(3) = obj.PeakDLSpectralEfficiency;
                dlStats(4) = 1e6*dlStats(2)/obj.Bandwidth(obj.DownlinkIdx);
            end
            % Uplink stats
            if ismember(obj.UplinkIdx, obj.PlotIds)
                ulStats(1) = obj.PeakDataRateUL;
                ulStats(2) = totalULTxBytes * 8 ./ (obj.NumFrames * 0.01 * 1000 * 1000); % Mbps
                ulStats(3) = obj.PeakULSpectralEfficiency;
                ulStats(4) = 1e6*ulStats(2)/obj.Bandwidth(obj.UplinkIdx);
            end
        end

        function addDepEvent(obj, callbackFcn, numSlots)
            %addDepEvent Adds an event to the events list
            %
            % addDepEvent(obj, callbackFcn, numSlots) Adds an event to the
            % event list
            %
            % CALLBACKFCN - Handle of the function to be invoked
            %
            % NUMSLOTS - Periodicity at which function has to be invoked

            % Create event
            event = struct('CallbackFcn', callbackFcn, 'InvokePeriodicity', numSlots);
            obj.Events = [obj.Events  event];
        end
    end

    methods( Access = private)
        function invokeDepEvents(obj, slotNum)
            numEvents = numel(obj.Events);
            for idx=1:numEvents
                event = obj.Events(idx);
                if isempty(event.InvokePeriodicity)
                    event.CallbackFcn(slotNum);
                else
                    invokePeriodicity = event.InvokePeriodicity;
                    if mod(slotNum, invokePeriodicity) == 0
                        event.CallbackFcn(slotNum);
                    end
                end
            end
        end

        function logFormat = constructSchedulingLogFormat(obj, linkIdx, numTotalUEs)
            %constructSchedulingLogFormat Construct log format for a carrier

            columnIndex = 1;
            logFormat{1, columnIndex} = 0; % Timestamp (in milliseconds)
            obj.ColumnIndexMap('Timestamp (ms)') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = 0; % Frame number
            obj.ColumnIndexMap('Frame') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} =  0; % Slot number
            obj.ColumnIndexMap('Slot') = columnIndex;

            if(obj.SchedulingType == 1)
                % Symbol number column is only for symbol-based
                % scheduling
                columnIndex = columnIndex + 1;
                logFormat{1, columnIndex} =  0; % Symbol number
                obj.ColumnIndexMap('Symbol Number') = columnIndex;
            end
            if(obj.DuplexMode == obj.TDDDuplexMode)
                % Slot/symbol type as DL/UL/guard is only for TDD mode
                columnIndex = columnIndex + 1;
                logFormat{1, columnIndex} = 'Guard'; % Symbol type
                obj.ColumnIndexMap('Type') = columnIndex;
            end

            columnIndex = columnIndex + 1;
            if obj.ResourceAllocationType % RAT-1
                logFormat{1, columnIndex} = zeros (numTotalUEs, 2); % RB allocation for UEs
            else  % RAT-0
                logFormat{1, columnIndex} = zeros(numTotalUEs, ceil(obj.NumRBs(linkIdx) / obj.RBGSize(linkIdx))); % RBG allocation for UEs
            end
            obj.ColumnIndexMap(obj.FreqAllocLabel) = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = -1*ones(numTotalUEs, 1); % MCS for assignments
            obj.ColumnIndexMap('MCS Index') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = -1*ones(numTotalUEs, 1); % HARQ IDs for assignments
            obj.ColumnIndexMap('HARQ Process') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = -1*ones(numTotalUEs, 1); % NDI flag for assignments
            obj.ColumnIndexMap('NDI') = columnIndex;

            % Tx type of the assignments ('newTx' or 'reTx'), 'noTx' if there is no assignment
            txTypeUEs =  cell(numTotalUEs, 1);
            txTypeUEs(:) = {'noTx'};
            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = txTypeUEs;
            obj.ColumnIndexMap('Tx Type') = columnIndex;

            columnIndex = columnIndex + 1;
            if linkIdx
                % Initialize CSI report format for DL
                csiReport = struct('RankIndicator', 1, 'PMISet', [], 'CQI', zeros(1, obj.NumRBs(linkIdx)), 'CSIResourceIndicator', [], 'L1RSRP', []);
            else
                % Initialize CSI report format for UL
                csiReport = struct('RankIndicator', 1, 'TPMI', [], 'MCSIndex', 0);
            end
            logFormat{1, columnIndex} = repmat({csiReport}, numTotalUEs, 1); % Channel quality
            obj.ColumnIndexMap('Channel Quality') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = zeros(numTotalUEs, obj.NumHARQ); % HARQ process status
            obj.ColumnIndexMap('HARQ NDI Status') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = zeros(numTotalUEs, 1); % MAC bytes transmitted
            obj.ColumnIndexMap('Transmitted Bytes') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = zeros(numTotalUEs, 1); % UEs' buffer status
            obj.ColumnIndexMap('Buffer Status of UEs (bytes)') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = -Inf(numTotalUEs, 1); % SINR values
            obj.ColumnIndexMap('SINR (dB)') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = strings(numTotalUEs, 1); % Received signal type
            obj.ColumnIndexMap('Signal Type') = columnIndex;

            if obj.IsNTNSimulation
                columnIndex = columnIndex + 1;
                logFormat{1, columnIndex} = NaN(numTotalUEs, 1); % UE transmission time in ms
                obj.ColumnIndexMap('UE Tx Time (ms) (UL only)') = columnIndex;

                columnIndex = columnIndex + 1;
                logFormat{1, columnIndex} = NaN(numTotalUEs, 1); % UE reception time in ms
                obj.ColumnIndexMap('UE Rx Time (ms) (DL only)') = columnIndex;
            end

            % Initialize scheduling log for all the symbols in the
            % simulation time. The last time scheduler runs in the
            % simulation, it might assign resources for future slots which
            % are outside of simulation time. Storing those decisions too
            numSlotsSim = round(obj.NumFrames * obj.NumSlotsFrame); % Simulation time in units of slot duration
            logFormat = repmat(logFormat(1,:), (numSlotsSim + obj.NumSlotsFrame)*obj.NumSym , 1);
        end

        function logFormat = constructGrantLogFormat(obj, numTotalUEs)
            %constructGrantLogFormat Construct grant log format for a carrier

            columnIndex = 1;
            logFormat{1, columnIndex} = -1; % UE's RNTI
            obj.GrantLogsColumnIndexMap('RNTI') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = -1; % Frame number
            obj.GrantLogsColumnIndexMap('Frame') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = -1; % Slot number
            obj.GrantLogsColumnIndexMap('Slot') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = {''}; % Type: UL or DL
            obj.GrantLogsColumnIndexMap('Grant Type') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = {''}; % Frequency allocation for UEs
            obj.GrantLogsColumnIndexMap(obj.FreqAllocLabel) = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = -1; % Start Symbol
            obj.GrantLogsColumnIndexMap('Start Symbol') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = -1; % Num Symbols
            obj.GrantLogsColumnIndexMap('Num Symbols') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = -1; % MCS Value
            obj.GrantLogsColumnIndexMap('MCS Index') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = -1; % Number of layers
            obj.GrantLogsColumnIndexMap('NumLayers') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = -1; % HARQ IDs for assignments
            obj.GrantLogsColumnIndexMap('HARQ Process') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = -1; % NDI flag for assignments
            obj.GrantLogsColumnIndexMap('NDI') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = -1; % RV for assignments
            obj.GrantLogsColumnIndexMap('RV') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = {''}; % Tx type: new-Tx or re-Tx
            obj.GrantLogsColumnIndexMap('Tx Type') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = {'NA'}; % PDSCH feedback slot offset (Only applicable for DL grants)
            obj.GrantLogsColumnIndexMap('Feedback Slot Offset (DL grants only)') = columnIndex;

            % Initialize scheduling log for all the symbols in the
            % simulation time. The last time scheduler runs in the
            % simulation, it might assign resources for future slots which
            % are outside of simulation time. Storing those decisions too
            if obj.SchedulingType == 1
                maxRows = round(obj.NumFrames*obj.NumSlotsFrame)*numTotalUEs*(ceil(obj.NumSym/obj.GNB.MACEntity.Scheduler.TTIGranularity));
            else
                maxRows = round(obj.NumFrames*obj.NumSlotsFrame)*numTotalUEs;
            end
            logFormat = repmat(logFormat(1,:), maxRows , 1);
        end
    end
end