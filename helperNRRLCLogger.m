classdef helperNRRLCLogger < handle
    %helperNRRLCLogger RLC statistics logging object
    %   The class implements per slot logging mechanism for RLC logical
    %   channels of the UEs. It is used to log the statistics per cell

    %   Copyright 2023-2025 The MathWorks, Inc.

    properties
        %NCellID Cell id to which the logging object belongs
        NCellID (1, 1) {mustBeInteger, mustBeInRange(NCellID, 0, 1007)} = 1;

        %NumUEs Count of UEs
        NumUEs

        %NumSlotsFrame Number of slots in a 10ms time frame
        NumSlotsFrame

        %RLCStatsLog Slot-by-slot log of the RLC statistics
        % It is a P-by-Q cell array, where P is the number of slots, and Q
        % is the number of columns in the logs. The column names are
        % specified as keys in ColumnIndexMap
        RLCStatsLog

        %ColumnIndexMap Mapping the column names of logs to respective column indices
        % It is a map object
        ColumnIndexMap

        %RLCStatIndexMap Mapping the column names of logs to respective column indices
        % It is a map object
        RLCStatIndexMap
    end

    properties(Access = private)
        %CurrSlot Current slot in the frame
        % It is incremented by 1 slot for every call to logRLCStats method
        CurrSlot = -1

        %CurrFrame Current frame
        % It is incremented by 1 frame for every NumSlotsFrame slots
        CurrFrame = -1

        %UERLCStats Current statistics of RLC layer at UE
        % It is a N-by-1 cell array, where N is the number of UEs. Each
        % cell element is a P-by-Q matrix, where P is the number of logical
        % channels, and Q is the number of statistics collected. Each row
        % represents statistics of a logical channel.
        UERLCStats

        %GNBRLCStats Current statistics of RLC layer at gNB
        % It is a N-by-1 cell array, where N is then number of UEs. Each
        % cell element is P-by-Q matrix, where P is the number of logical
        % channels, and Q is the number of statistics collected. Each row
        % represents statistics of a logical channel.
        GNBRLCStats

        %PrevUERLCStats Cumulative RLC statistics returned in the previous query at UE
        % It is a N-by-1 cell array, where N is then number of UEs. Each
        % cell element is a P-by-Q matrix, where P is the number of logical
        % channels, and Q is the number of statistics collected. Each row
        % represents statistics of a logical channel.
        PrevUERLCStats

        %PrevGNBRLCStats Cumulative RLC statistics returned in the previous query at gNB
        % It is a N-by-1 cell array, where N is the number of UEs. Each
        % cell element is a P-by-Q matrix, where P is the number of logical
        % channels, and Q is the number of statistics collected. Each row
        % represents statistics of a logical channel.
        PrevGNBRLCStats

        %FinalUERLCStats Cumulative statistics of RLC layer at UE for the entire simulation
        % It is  a P-by-Q matrix, where P is the number of logical
        % channels, and Q is the number of statistics collected. Each row
        % represents statistics of a logical channel.
        FinalUERLCStats

        %FinalgNBRLCStats Cumulative statistics of RLC layer at gNB for the entire simulation
        % It is  a P-by-Q matrix, where P is the number of logical
        % channels, and Q is the number of statistics collected. Each row
        % represents statistics of a logical channel.
        FinalgNBRLCStats
    end

    properties (WeakHandle, SetAccess=private)
        %GNB Node object of type nrGNB
        GNB nrGNB

        %UEs Vector of node objects of type nrUE
        UEs nrUE
    end

    properties (Access = private, Constant)
        % Constants related to downlink and uplink information
        % These constants are used for indexing logs
        %DownlinkIdx Index for all downlink information
        DownlinkIdx = 1;
        %UplinkIdx Index for all uplink information
        UplinkIdx = 2;

        %RLCStatsTitles Title for the columns of RLC statistics
        RLCStatsTitles = {'UEID', 'RNTI', 'TransmittedPackets', 'TransmittedBytes', ...
            'ReceivedPackets', 'ReceivedBytes', 'DroppedPackets', 'DroppedBytes'};
    end

    methods (Access = public)
        function obj = helperNRRLCLogger(numFramesSim, gNB, UEs, varargin)
            %helperNRRLCLogger Construct an RLC logging object
            %
            % OBJ = helperNRRLCLogger(NUMFRAMESSIM, GNB, UEs) Create an RLC logging object.
            %
            % NUMFRAMESSIM is simulation time in terms of number of 10 ms frames.
            %
            % GNB is an object of type nrGNB.
            %
            % UEs is a vector of node objects of type nrUE. They must be connected to the
            % same GNB.
            %
            % SIMPARAMETERS - It is a structure and contains simulation configuration
            % information.
            %   NumUEs  - Number of UEs
            %   NCellID - Cell identifier
            %   SCS     - Subcarrier spacing
            %

            networkSimulator = wirelessNetworkSimulator.getInstance();
            obj.GNB = gNB;
            obj.NCellID = gNB.NCellID(1);
            obj.UEs = UEs;
            obj.NumUEs = numel(UEs);
            obj.NumSlotsFrame = (10e-3 * gNB.SubcarrierSpacing) / 15; % Number of slots in a 10 ms frame

            numRows = obj.NumUEs; % Number of rows to create in logs
            % RLC Stats
            % Each row represents the statistics of each slot and last row
            % of the log represents the cumulative statistics of the entire simulation
            obj.RLCStatsLog = cell((numFramesSim * obj.NumSlotsFrame) + 1, 5);
            obj.ColumnIndexMap = containers.Map('KeyType','char','ValueType','double');
            obj.ColumnIndexMap('Timestamp') = 1;
            obj.ColumnIndexMap('Frame') = 2;
            obj.ColumnIndexMap('Slot') = 3;
            obj.ColumnIndexMap('UE RLC statistics') = 4;
            obj.ColumnIndexMap('gNB RLC statistics') = 5;
            obj.RLCStatsLog{1, obj.ColumnIndexMap('Timestamp')} = 0; % Timestamp (in milliseconds)
            obj.RLCStatsLog{1, obj.ColumnIndexMap('Frame')} = 0; % Frame number
            obj.RLCStatsLog{1, obj.ColumnIndexMap('Slot')} = 0; % Slot number
            obj.RLCStatsLog{1, obj.ColumnIndexMap('UE RLC statistics')} = cell(1, 1); % UE RLC stats
            obj.RLCStatsLog{1, obj.ColumnIndexMap('gNB RLC statistics')} = cell(1, 1); % gNB RLC stats

            % RLC stats column index map
            obj.RLCStatIndexMap = containers.Map(obj.RLCStatsTitles,1:numel(obj.RLCStatsTitles));

            % Initialize RLC stats for the current slot
            obj.UERLCStats = cell(obj.NumUEs, 1);
            obj.GNBRLCStats = cell(obj.NumUEs, 1);
            % To store RLC stats for the previous slot
            obj.PrevUERLCStats = cell(obj.NumUEs, 1);
            obj.PrevGNBRLCStats = cell(obj.NumUEs, 1);

            % Initialize the cumulative statistics of UE and gNB
            obj.FinalUERLCStats = zeros(numRows, numel(obj.RLCStatsTitles));
            obj.FinalgNBRLCStats = zeros(numRows, numel(obj.RLCStatsTitles));
            % idx = 1; % To index the number of rows created in logs
            for ueIdx = 1:obj.NumUEs
                % Update the statistics with UE ID and RNTI
                obj.FinalUERLCStats(ueIdx, 1) = obj.UEs(ueIdx).ID;
                obj.FinalUERLCStats(ueIdx, 2) = obj.UEs(ueIdx).RNTI;
                obj.FinalgNBRLCStats(ueIdx, 1) = obj.UEs(ueIdx).ID;
                obj.FinalgNBRLCStats(ueIdx, 2) = obj.UEs(ueIdx).RNTI;
            end

            % Register periodic logging event with network simulator
            slotDuration = 15/gNB.SubcarrierSpacing; % In seconds
            symbolDuration = slotDuration/14;
            scheduleAction(networkSimulator, @obj.logCellRLCStats, [], symbolDuration/2, slotDuration);
        end

        function logCellRLCStats(obj, ~, ~)
            %logCellRLCStats Log the RLC layer statistics periodically

            rlcMetrics = zeros(1, numel(obj.RLCStatsTitles));
            gNBStats = statistics(obj.GNB, "all");
            gNBRLCStats = gNBStats.RLC.Destinations;
            for ueIdx = 1:obj.NumUEs
                % Get RLC statistics
                ueStats = statistics(obj.UEs(ueIdx));
                ueRLCStatsUL = ueStats.RLC;
                rlcMetrics(1) = obj.UEs(ueIdx).ID;
                rlcMetrics(2) = obj.UEs(ueIdx).RNTI;
                for columnIdx = 3:numel(obj.RLCStatsTitles)
                    fieldName = obj.RLCStatsTitles{columnIdx};
                    rlcMetrics(columnIdx) = ueRLCStatsUL.(fieldName);
                end
                if ~isempty(obj.PrevUERLCStats{ueIdx})
                    obj.UERLCStats{ueIdx}(:, 3:end) = rlcMetrics(:, 3:end) - obj.PrevUERLCStats{ueIdx}(:, 3:end);
                    obj.PrevUERLCStats{ueIdx} = rlcMetrics;
                else
                    obj.UERLCStats{ueIdx} = rlcMetrics;
                    obj.PrevUERLCStats{ueIdx} = rlcMetrics;
                end
                ueRLCStatsDL =  gNBRLCStats(ueIdx);
                for columnIdx = 3:numel(obj.RLCStatsTitles)
                    fieldName = obj.RLCStatsTitles{columnIdx};
                    rlcMetrics(columnIdx) = ueRLCStatsDL.(fieldName);
                end
                if ~isempty(obj.PrevGNBRLCStats{ueIdx})
                    obj.GNBRLCStats{ueIdx}(:, 3:end) = rlcMetrics(:, 3:end) - obj.PrevGNBRLCStats{ueIdx}(:, 3:end);
                    obj.PrevGNBRLCStats{ueIdx} = rlcMetrics;
                else
                    obj.GNBRLCStats{ueIdx} = rlcMetrics;
                    obj.PrevGNBRLCStats{ueIdx} = rlcMetrics;
                end
            end
            logRLCStats(obj, obj.UERLCStats, obj.GNBRLCStats); % Update RLC statistics logs
        end

        function logRLCStats(obj, ueRLCStats, gNBRLCStats)
            %logRLCStats Log the RLC statistics
            %
            % logRLCStats(OBJ, UERLCSTATS, GNBRLCSTATS) Logs the RLC
            % statistics
            %
            % UERLCSTATS - Represents a N-by-1 cell, where N is the number
            % of UEs. Each element of the cell is  a P-by-Q matrix, where
            % P is the number of logical channels, and Q is the number of
            % statistics collected. Each row represents statistics of a
            % logical channel.
            %
            % GNBRLCSTATS - Represents a N-by-1 cell, where N is the number
            % of UEs. Each element of the cell is  a P-by-Q matrix, where
            % P is the number of logical channels, and Q is the number of
            % statistics collected. Each row represents statistics of a
            % logical channel of a UE at gNB.

            currUEStats = vertcat(ueRLCStats{:});
            currgNBStats = vertcat(gNBRLCStats{:});
            % Sort the rows based on RNTI and LCID
            currUEStats = sortrows(currUEStats, [obj.RLCStatIndexMap('RNTI')]);
            currgNBStats = sortrows(currgNBStats, [obj.RLCStatIndexMap('RNTI')]);

            % Move to the next slot
            obj.CurrSlot = mod(obj.CurrSlot + 1, obj.NumSlotsFrame);
            if(obj.CurrSlot == 0)
                obj.CurrFrame = obj.CurrFrame + 1; % Next frame
            end
            timestamp = obj.CurrFrame * 10 + (obj.CurrSlot * 10/obj.NumSlotsFrame);
            logIndex = obj.CurrFrame * obj.NumSlotsFrame + obj.CurrSlot + 1;
            obj.RLCStatsLog{logIndex, obj.ColumnIndexMap('Timestamp')} = timestamp;
            obj.RLCStatsLog{logIndex, obj.ColumnIndexMap('Frame')} = obj.CurrFrame;
            obj.RLCStatsLog{logIndex, obj.ColumnIndexMap('Slot')} = obj.CurrSlot;
            % Current cumulative statistics
            obj.FinalUERLCStats(:,3:end) = currUEStats(:,3:end) + obj.FinalUERLCStats(:,3:end);
            obj.FinalgNBRLCStats(:,3:end) = currgNBStats(:,3:end) + obj.FinalgNBRLCStats(:,3:end);
            % Add column titles for the current slot statistics
            obj.RLCStatsLog{logIndex, obj.ColumnIndexMap('UE RLC statistics')} = vertcat(obj.RLCStatsTitles, num2cell(currUEStats));
            obj.RLCStatsLog{logIndex,obj.ColumnIndexMap('gNB RLC statistics')} = vertcat(obj.RLCStatsTitles, num2cell(currgNBStats));
        end

        function rlcLogs = getRLCLogs(obj)
            %GETRLCLOGS Return the per slot logs
            %
            % RLCLOGS = getRLCLogs(OBJ) Returns the RLC logs
            %
            % RLCLOGS - It is (N+2)-by-P cell, where N represents the
            % number of slots in the simulation and P represents the number
            % of columns. The first row of the logs contains titles for the
            % logs. The last row of the logs contains the cumulative
            % statistics for the entire simulation. Each row (excluding
            % first and last rows) in the logs corresponds to a slot and
            % contains the following information.
            %   Timestamp - Timestamp (in milliseconds)
            %   Frame - Frame number.
            %   Slot - Slot number in the frame.
            %   UE RLC statistics - N-by-P cell, where N is the product of
            %                       number of UEs and number of logical
            %                       channels, and P is the number of
            %                       statistics collected. Each row
            %                       represents statistics of a logical
            %                       channel in a UE.
            %   gNB RLC statistics - N-by-P cell, where N is the product of
            %                      number of UEs and number of logical
            %                      channels, and P is the number of
            %                      statistics collected. Each row
            %                      represents statistics of a logical
            %                      channel of a UE at gNB.

            if obj.CurrFrame < 0 % Return empty when logging is not started
                rlcLogs = [];
                return;
            end
            headings = {'Timestamp','Frame', 'Slot', 'UE RLC statistics', 'gNB RLC statistics'};
            % Most recent log index for the current simulation
            lastLogIndex = obj.CurrFrame * obj.NumSlotsFrame + obj.CurrSlot + 1;
            % Create a row at the end of the to store the cumulative statistics of the UE
            % and gNB at the end of the simulation
            lastLogIndex = lastLogIndex + 1;
            obj.RLCStatsLog{lastLogIndex, obj.ColumnIndexMap('UE RLC statistics')} = vertcat(obj.RLCStatsTitles, num2cell(obj.FinalUERLCStats));
            obj.RLCStatsLog{lastLogIndex, obj.ColumnIndexMap('gNB RLC statistics')} = vertcat(obj.RLCStatsTitles, num2cell(obj.FinalgNBRLCStats));
            rlcLogs = [headings; obj.RLCStatsLog(1:lastLogIndex, :)];
        end
    end
end