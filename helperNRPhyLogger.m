classdef helperNRPhyLogger < handle
    %helperNRPhyLogger Phy statistics logging object
    %   The class implements per slot/symbol logging mechanism of the physical
    %   layer metrics. It is used to log the statistics in case of multiple
    %   carriers.
    %
    %   helperNRPhyLogger Name-Value pairs:
    %
    %   LinkDirection     - Indicate the link direction in which logging is performed
    %   CarrierID         - Indicate index of the carrier(s) to log

    %   Copyright 2022-2026 The MathWorks, Inc.

    properties
        % LinkDirection indicates the directions in which logging is performed. It
        % takes values "DL","UL" and "Both". By default, the value is set to
        % "Both", indicating that logs are recorded for both directions.
        LinkDirection (1,1) string {mustBeMember(LinkDirection, ["DL", "UL", "Both"])} = "Both";

        % CarrierID indicates index of the carrier(s) to log. If specified, logging is
        % performed only for the given carrier(s). Default is 1 (gNB first carrier).
        CarrierID (1,:) {mustBeVector, mustBePositive} = 1;
    end

    properties
        % NumCarriers Number of carriers
        NumCarriers

        % NumUEsPerCarrier Number of UEs on each carrier (1-by-NumCarriers)
        NumUEsPerCarrier

        % UERNTIsPerCarrier RNTIs of UEs served on each carrier
        % It is a 1-by-NumCarriers cell array. Each element is a row vector
        % of UE RNTIs served on that carrier.
        UERNTIsPerCarrier

        % NumSlotsFrame Number of slots in a 10ms time frame
        NumSlotsFrame

        % RxStatsLog Slot-by-slot/symbol-by-symbol log of the Rx statistics
        % It is a 1-by-NumCarriers cell array. Each element contains the
        % per-symbol log for that carrier.
        RxStatsLog

        % ColumnIndexMap Mapping the column names of logs to respective column indices
        % It is a map object
        ColumnIndexMap
    end

    properties (SetAccess = private)
        %UECarrierIndexMap Mapping from gNB carrier index to UE carrier index
        % It is a 1-by-NumCarriers cell array. Each element is a vector of length
        % NumUEsPerCarrier containing the UE carrier index for each UE on that gNB
        % carrier.
        UECarrierIndexMap
    end

    properties(Access = private)
        % CurrSlot Current slot in the frame
        % It is incremented by 1 slot for every NumSym symbols
        CurrSlot = -1

        % CurrFrame Current frame
        % It is incremented by 1 frame for every NumSlotsFrame slots
        CurrFrame = -1

        % CurrSymbol Current symbol
        % It is updated for every call to logRxStats
        CurrSymbol = -1

        %UERxStats Downlink receiver side statistics for the current symbol
        % It is a 1-by-NumCarriers cell array. Each element is an N-by-2 array
        % where N is the total number of UEs connected with the gNB's first
        % carrier. First and second columns contain the number of erroneous packets
        % received and the total number of received packets for each UE
        % respectively
        UERxStats

        %GNBRxStats Uplink receiver side statistics for the current symbol
        % It is a 1-by-NumCarriers cell array. Each element is an N-by-2 array
        % where N is the total number of UEs connected with the gNB's first
        % carrier. First and second columns contain the number of erroneous packets
        % received and the total number of received packets from each UE
        % respectively
        GNBRxStats

        %PrevCumulativeULBlkErr Cumulative uplink block error information returned in the last query
        % It is a 1-by-NumCarriers cell array. Each element is an N-by-2 array
        % where N is the total number of UEs connected with the gNB's first
        % carrier. Columns 1 and 2 contains the number of erroneously received
        % packets and total received packets, respectively
        PrevCumulativeULBlkErr

        %PrevCumulativeDLBlkErr Cumulative downlink block error information returned in the last query
        % It is a 1-by-NumCarriers cell array. Each element is an N-by-2 array
        % where N is the total number of UEs connected with the gNB's first
        % carrier.Columns 1 and 2 contains the number of erroneously received
        % packets and total received packets, respectively
        PrevCumulativeDLBlkErr

        %LogIndexCounter Current log index
        LogIndexCounter = 0;
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

    properties (Access = private, Constant, Hidden)
        % Constants related to downlink and uplink information. These
        % constants are used for indexing logs and identifying plots
        %DownlinkIdx Index for all downlink information
        DownlinkIdx = 1;
        %UplinkIdx Index for all uplink information
        UplinkIdx = 2;

        %NumSym Number of symbols in a slot
        NumSym = 14;
    end

    methods (Access = public)
        function obj = helperNRPhyLogger(numFramesSim, gNB, UEs, varargin)
            %helperNRPhyLogger Construct Phy logging object
            %
            % OBJ = helperNRPhyLogger(NUMFRAMESSIM, GNB, UEs) Create a Phy logging object
            % for logging the traces.
            %
            % OBJ = helperNRPhyLogger(NUMFRAMESSIM, GNB, UEs, LinkDirection=linkDir) Create a
            % Phy logging object for logging the traces.
            %
            % OBJ = helperNRPhyLogger(NUMFRAMESSIM, GNB, UEs, LinkDirection=linkDir, CarrierID=n) 
            % Create a Phy logging object for logging the traces on the given CarrierID.
            %
            % NumFramesSim - Simulation time in terms of number of 10 ms frames
            %
            % GNB - It is a scalar and object of type nrGNB
            %
            % UEs - It is a vector of node objects of type nrUE. They must be connected
            %       to GNB
            %
            % LinkDirection - Link direction in which logging is performed.It takes
            %                 values "DL","UL" and "Both". By default, the value is set to
            %                 "Both", indicating that logs are recorded for both directions.
            %
            % CarrierID    - Index of the carrier(s) to log. If specified, logging is
            %                performed only for the given carrier(s). Default is 1 (gNB
            %                first carrier). This is according to the order of carriers
            %                at the gNB.

            obj.GNB = gNB;
            % Sort UEs by RNTI so that obj.UEs(rnti) is always correct
            [~, sortOrder] = sort([UEs.RNTI]);
            obj.UEs = UEs(sortOrder);
            numTotalUEs = numel(UEs);
            % Initialize the properties
            for idx = 1:2:numel(varargin)
                obj.(varargin{idx}) = varargin{idx+1};
            end
            if isempty(obj.NetworkSimulator)
                obj.NetworkSimulator = wirelessNetworkSimulator.getInstance();
            end
            obj.ColumnIndexMap = containers.Map('KeyType','char','ValueType','double');
            obj.NumSlotsFrame = (10 * gNB.SubcarrierSpacing) / 15e3; % Number of slots in a 10 ms frame
            obj.NumCarriers = numel(gNB.ComponentCarrierConfig);

            % Determine which UEs are connected to each carrier
            obj.UERNTIsPerCarrier = cell(1, obj.NumCarriers);
            if isprop(gNB, 'UEInfoPerCarrier')
                for carrierIdx = 1:obj.NumCarriers
                    obj.UERNTIsPerCarrier{carrierIdx} = gNB.UEInfoPerCarrier(carrierIdx).UERNTIs;
                end
            else
                % Backward compatible: single carrier uses all the connected UEs
                obj.UERNTIsPerCarrier{1} = 1:numel(obj.UEs);
            end
            obj.NumUEsPerCarrier = zeros(1, obj.NumCarriers);
            for carrierIdx = 1:obj.NumCarriers
                obj.NumUEsPerCarrier(carrierIdx) = numel(obj.UERNTIsPerCarrier{carrierIdx});
            end

            % Build UE carrier index map by matching gNB DL carrier
            % frequency against each UE's ReceiveFrequency. This correctly
            % resolves the UE PhyEntity index regardless of the order in
            % which secondary carriers were added.
            obj.UECarrierIndexMap = cell(1, obj.NumCarriers);
            gNBDLFreq = gNB.DLCarrierFrequency;
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

            % Rx stats: one log per carrier, all using same vector length
            % (total number of UEs). Position i stores metric for UE with RNTI i.
            obj.RxStatsLog = cell(1, obj.NumCarriers);
            for carrierIdx = 1:obj.NumCarriers
                obj.RxStatsLog{carrierIdx} = constructLogFormat(obj, numFramesSim, numTotalUEs);
            end

            obj.UERxStats = cell(1, obj.NumCarriers);
            obj.GNBRxStats = cell(1, obj.NumCarriers);
            obj.PrevCumulativeULBlkErr = cell(1, obj.NumCarriers);
            obj.PrevCumulativeDLBlkErr = cell(1, obj.NumCarriers);
            for carrierIdx = 1:obj.NumCarriers
                obj.UERxStats{carrierIdx} = zeros(numTotalUEs, 2);
                obj.GNBRxStats{carrierIdx} = zeros(numTotalUEs, 2);
                obj.PrevCumulativeULBlkErr{carrierIdx} = zeros(numTotalUEs, 2);
                obj.PrevCumulativeDLBlkErr{carrierIdx} = zeros(numTotalUEs, 2);
            end

            % Register periodic logging event with network simulator
            phyLogPeriodicity = ((15e3/gNB.SubcarrierSpacing)/14) * 1e-3; % In seconds
            scheduleAction(obj.NetworkSimulator, @obj.logCellPhyStats, [], phyLogPeriodicity/2, phyLogPeriodicity);
        end

        function [dlPhyMetrics, ulPhyMetrics] = getPhyMetrics(obj, firstSlot, lastSlot, rntiList)
            %getPhyMetrics Return the Phy metrics for the configured carriers
            %
            % [DLMETRICS, ULMETRICS] = getPhyMetrics(OBJ, FIRSTSLOT,
            % LASTSLOT, RNTILIST) returns the Phy metrics of the UEs with
            % specified RNTIs for both uplink and downlink on obj.CarrierID.
            %
            % FIRSTSLOT - Represents the starting slot number for querying the metrics
            %
            % LASTSLOT  - Represents the ending slot for querying the metrics
            %
            % RNTILIST - Radio network temporary identifiers of a vector of UEs.
            %            Assumes all UEs in rntiList are present on each carrier.
            %
            % DLPHYMETRICS - Struct array of size [numel(rntiList), numel(CarrierID)].
            %                Each element contains DL metrics for one UE on one carrier.
            %                Empty when LinkDirection is "UL".
            %
            % ULPHYMETRICS - Struct array of size [numel(rntiList), numel(CarrierID)].
            %                Each element contains UL metrics for one UE on one carrier.
            %                Empty when LinkDirection is "DL".
            %
            % Each struct has the fields:
            %   RNTI           - Radio network temporary identifier of the UE
            %   DecodeFailures - Total number of decode failures
            %   TotalPackets   - Total number of packets

            carrierIndices = obj.CarrierID;
            numCarriersQuery = numel(carrierIndices);
            numUEs = numel(rntiList);
            emptyStruct = repmat(struct('RNTI',0,'TotalPackets',0,'DecodeFailures',0), [0 0]);
            stepLogStartIdx = (firstSlot-1) * obj.NumSym + 1;
            stepLogEndIdx = lastSlot * obj.NumSym;
            columnMap = obj.ColumnIndexMap;

            % Determine which directions to process
            isDL = obj.LinkDirection ~= "UL";
            isUL = obj.LinkDirection ~= "DL";

            % Initialize outputs
            if isDL
                dlPhyMetrics = repmat(struct('RNTI',0,'TotalPackets',0,'DecodeFailures',0), [numUEs, numCarriersQuery]);
            else
                dlPhyMetrics = emptyStruct;
            end
            if isUL
                ulPhyMetrics = repmat(struct('RNTI',0,'TotalPackets',0,'DecodeFailures',0), [numUEs, numCarriersQuery]);
            else
                ulPhyMetrics = emptyStruct;
            end

            for cIdx = 1:numCarriersQuery
                carrierIdx = carrierIndices(cIdx);

                % Process DL metrics only if configured
                if isDL
                    decodeFailCol = columnMap('Number of Decode Failures(DL)');
                    numPktsCol = columnMap('Number of Packets(DL)');
                    rxStatsLogs = zeros(numUEs, 2);
                    for stepIdx = stepLogStartIdx:stepLogEndIdx
                        rxStatsLogs(:, 1) = rxStatsLogs(:, 1) + obj.RxStatsLog{carrierIdx}{stepIdx, decodeFailCol}(rntiList);
                        rxStatsLogs(:, 2) = rxStatsLogs(:, 2) + obj.RxStatsLog{carrierIdx}{stepIdx, numPktsCol}(rntiList);
                    end
                    for ueIdx = 1:numUEs
                        dlPhyMetrics(ueIdx, cIdx).RNTI = rntiList(ueIdx);
                        dlPhyMetrics(ueIdx, cIdx).DecodeFailures = rxStatsLogs(ueIdx, 1);
                        dlPhyMetrics(ueIdx, cIdx).TotalPackets = rxStatsLogs(ueIdx, 2);
                    end
                end

                % Process UL metrics only if configured
                if isUL
                    decodeFailCol = columnMap('Number of Decode Failures(UL)');
                    numPktsCol = columnMap('Number of Packets(UL)');
                    rxStatsLogs = zeros(numUEs, 2);
                    for stepIdx = stepLogStartIdx:stepLogEndIdx
                        rxStatsLogs(:, 1) = rxStatsLogs(:, 1) + obj.RxStatsLog{carrierIdx}{stepIdx, decodeFailCol}(rntiList);
                        rxStatsLogs(:, 2) = rxStatsLogs(:, 2) + obj.RxStatsLog{carrierIdx}{stepIdx, numPktsCol}(rntiList);
                    end
                    for ueIdx = 1:numUEs
                        ulPhyMetrics(ueIdx, cIdx).RNTI = rntiList(ueIdx);
                        ulPhyMetrics(ueIdx, cIdx).DecodeFailures = rxStatsLogs(ueIdx, 1);
                        ulPhyMetrics(ueIdx, cIdx).TotalPackets = rxStatsLogs(ueIdx, 2);
                    end
                end
            end
        end

        function receptionLogs = getReceptionLogs(obj)
            %getReceptionLogs Return the Phy reception logs
            %
            % RECEPTIONLOGS = getReceptionLogs(OBJ) Returns the Phy reception
            % logs for the carrier specified by obj.CarrierID.
            %
            % RECEPTIONLOGS - It is an (N+1)-by-P cell, where N represents the
            % number of symbols in the simulation and P represents the number of
            % columns. The first row of the logs contains titles for the logs.
            % Each row (excluding the first row) in the logs represents a symbol
            % and contains the following information.
            %  Frame                           - Frame number.
            %  Slot                            - Slot number in the frame.
            %  Symbol number                   - Symbol number in the slot
            %  Number of Decode Failures(DL)   - Column vector of length N, where N is the
            %                                    number of UEs. Each element contains the
            %                                    number of decode failures in the downlink
            %  Number of Packets(DL)           - Column vector of length N, where N is the
            %                                    number of UEs. Each element contains the
            %                                    number of packets in the downlink
            %  Number of Decode Failures(UL)   - Column vector of length N, where N is the
            %                                    number of UEs. Each element contains the
            %                                    number of decode failures in the uplink
            %  Number of Packets(UL)           - Column vector of length N, where N is the
            %                                    number of UEs. Each element contains the
            %                                    number of packets in the uplink

            % Get keys of columns (i.e. column names) in sorted order of values (i.e. column indices)
            [~, idx] = sort(cell2mat(values(obj.ColumnIndexMap)));
            columnTitles = keys(obj.ColumnIndexMap);
            columnTitles = columnTitles(idx);

            % Most recent log index for the current simulation
            lastLogIndex = (obj.CurrFrame)*obj.NumSlotsFrame*obj.NumSym + (obj.CurrSlot+1)*obj.NumSym;
            carrierIndices = obj.CarrierID;
            receptionLogs = cell(1, numel(carrierIndices));
            for cIdx = 1:numel(carrierIndices)
                receptionLogs{cIdx} = [columnTitles; obj.RxStatsLog{carrierIndices(cIdx)}(1:lastLogIndex, :)];
            end
        end
    end

    methods (Hidden)
        function logCellPhyStats(obj, ~, ~)
            %logCellPhyStats Log the Phy layer statistics

            obj.LogIndexCounter = obj.LogIndexCounter + 1;
            numTotalUEs = numel(obj.UEs);
            for carrierIdx = obj.CarrierID
                numUEsCC = obj.NumUEsPerCarrier(carrierIdx);
                connectedUEs = obj.UERNTIsPerCarrier{carrierIdx};
                uePhyIdx = obj.UECarrierIndexMap{carrierIdx};

                % Read the DL Rx stats for each UE on this carrier
                if obj.LinkDirection ~= "UL"
                    for posIdx = 1:numUEsCC
                        ueIdx = connectedUEs(posIdx);
                        carrierPHY = obj.UEs(ueIdx).PhyEntity(uePhyIdx(posIdx));
                        ueStats = [carrierPHY.StatDecodeFailures carrierPHY.StatReceivedPackets];
                        obj.UERxStats{carrierIdx}(ueIdx, :) = ueStats - obj.PrevCumulativeDLBlkErr{carrierIdx}(ueIdx, :);
                        obj.PrevCumulativeDLBlkErr{carrierIdx}(ueIdx, :) = ueStats;
                    end
                else
                    obj.UERxStats{carrierIdx} = zeros(numTotalUEs, 2);
                end

                % Read the UL Rx stats for each UE from gNB on this carrier
                if obj.LinkDirection ~= "DL"
                    for posIdx = 1:numUEsCC
                        ueIdx = connectedUEs(posIdx);
                        gNBStats = [obj.GNB.PhyEntity(carrierIdx).StatDecodeFailures(posIdx) obj.GNB.PhyEntity(carrierIdx).StatReceivedPackets(posIdx)];
                        obj.GNBRxStats{carrierIdx}(ueIdx, :) = gNBStats - obj.PrevCumulativeULBlkErr{carrierIdx}(ueIdx, :);
                        obj.PrevCumulativeULBlkErr{carrierIdx}(ueIdx, :) = gNBStats;
                    end
                else
                    obj.GNBRxStats{carrierIdx} = zeros(numTotalUEs, 2);
                end

                % Log the UL and DL reception stats for this carrier
                logRxStats(obj, obj.LogIndexCounter, obj.UERxStats{carrierIdx}, obj.GNBRxStats{carrierIdx}, carrierIdx)
            end
        end

        function logRxStats(obj, symbolNumSimulation, ueRxStats, gNBRxStats, carrierIdx)
            %logRxStats Log the reception statistics
            %
            % logRxStats(OBJ, SYMBOLNUMSIMULATION, UERXSTATS, GNBRXSTATS, CARRIERIDX)
            % Logs the reception statistics for the specified carrier
            %
            % SYMBOLNUMSIMULATION - Symbol number in the simulation
            %
            % UERXSTATS - Represents a N-by-2 array, where N is the number of UEs. First and
            % second columns of the array contains the number of erroneous packets received
            % and the total number of received packets for each UE
            %
            % GNBRXSTATS - Represents a N-by-2 array, where N is the number of UEs. First
            % and second columns of the array contains the number of erroneous packets
            % received and the total number of received packets from each UE
            %
            % CARRIERIDX - Index of the carrier (1 to NumCarriers)

            columnMap = obj.ColumnIndexMap;
            % Calculate symbol number in slot (0-13), slot number in frame
            % (0-obj.NumSlotsFrame), frame number, and timestamp(in milliseconds) in the
            % simulation.
            slotDuration = 10/obj.NumSlotsFrame;
            obj.CurrSymbol = mod(symbolNumSimulation - 1, obj.NumSym);
            obj.CurrSlot = mod(floor((symbolNumSimulation - 1)/obj.NumSym), obj.NumSlotsFrame);
            obj.CurrFrame = floor((symbolNumSimulation-1)/(obj.NumSym * obj.NumSlotsFrame));
            timestamp = obj.CurrFrame * 10 + (obj.CurrSlot * slotDuration) + (obj.CurrSymbol * (slotDuration / 14));

            logIndex = (obj.CurrFrame * obj.NumSlotsFrame * obj.NumSym) +  ...
                (obj.CurrSlot * obj.NumSym) + obj.CurrSymbol + 1;
            obj.RxStatsLog{carrierIdx}{logIndex, columnMap('Timestamp (ms)')} = timestamp;
            obj.RxStatsLog{carrierIdx}{logIndex, columnMap('Frame')} = obj.CurrFrame;
            obj.RxStatsLog{carrierIdx}{logIndex, columnMap('Slot')} = obj.CurrSlot;
            obj.RxStatsLog{carrierIdx}{logIndex, columnMap('Symbol')} = obj.CurrSymbol;

            % Map input to RNTI positions if input is carrier-sized
            connectedUEs = obj.UERNTIsPerCarrier{carrierIdx};
            numTotalUEs = numel(obj.UEs);
            if size(ueRxStats, 1) == obj.NumUEsPerCarrier(carrierIdx) && obj.NumUEsPerCarrier(carrierIdx) ~= numTotalUEs
                dlVec = zeros(numTotalUEs, 2);
                dlVec(connectedUEs, :) = ueRxStats;
                ulVec = zeros(numTotalUEs, 2);
                ulVec(connectedUEs, :) = gNBRxStats;
            else
                dlVec = ueRxStats;
                ulVec = gNBRxStats;
            end

            % Log DL stats only if configured
            if obj.LinkDirection ~= "UL"
                obj.RxStatsLog{carrierIdx}{logIndex, columnMap('Number of Decode Failures(DL)')} = dlVec(:, 1);
                obj.RxStatsLog{carrierIdx}{logIndex, columnMap('Number of Packets(DL)')} = dlVec(:, 2);
            end
            % Log UL stats only if configured
            if obj.LinkDirection ~= "DL"
                obj.RxStatsLog{carrierIdx}{logIndex, columnMap('Number of Decode Failures(UL)')} = ulVec(:, 1);
                obj.RxStatsLog{carrierIdx}{logIndex, columnMap('Number of Packets(UL)')} = ulVec(:, 2);
            end
        end
    end

    methods(Access = private)
        function logFormat = constructLogFormat(obj, numFramesSim, numUEsCarrier)
            %constructLogFormat Construct log format for a carrier

            columnIndex = 1;
            logFormat{1, columnIndex} = 0; % Timestamp (in milliseconds)
            obj.ColumnIndexMap('Timestamp (ms)') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} = 0; % Frame number
            obj.ColumnIndexMap('Frame') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} =  0; % Slot number
            obj.ColumnIndexMap('Slot') = columnIndex;

            columnIndex = columnIndex + 1;
            logFormat{1, columnIndex} =  0; % Symbol number
            obj.ColumnIndexMap('Symbol') = columnIndex;

            % Only add DL columns if needed
            if obj.LinkDirection ~= "UL"
                columnIndex = columnIndex + 1;
                logFormat{1, columnIndex} = zeros(numUEsCarrier, 1);
                obj.ColumnIndexMap('Number of Decode Failures(DL)') = columnIndex;

                columnIndex = columnIndex + 1;
                logFormat{1, columnIndex} = zeros(numUEsCarrier, 1);
                obj.ColumnIndexMap('Number of Packets(DL)') = columnIndex;
            end

            % Only add UL columns if needed
            if obj.LinkDirection ~= "DL"
                columnIndex = columnIndex + 1;
                logFormat{1, columnIndex} = zeros(numUEsCarrier, 1);
                obj.ColumnIndexMap('Number of Decode Failures(UL)') = columnIndex;

                columnIndex = columnIndex + 1;
                logFormat{1, columnIndex} = zeros(numUEsCarrier, 1);
                obj.ColumnIndexMap('Number of Packets(UL)') = columnIndex;
            end

            % Initialize Rx stats logs for all the symbols in the simulation time
            numSlotsSim = round(numFramesSim * obj.NumSlotsFrame); % Simulation time in units of slot duration
            logFormat = repmat(logFormat(1,:), numSlotsSim*obj.NumSym, 1);
        end
    end
end