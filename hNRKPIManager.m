classdef hNRKPIManager < handle
    %hNRKPIManager Implements the functionality needed to collect relevant
    %information and calculate 5G NR Key Performance Indicators (KPIs)
    %   This class is responsible for collecting and calculating both
    %   connection-level (from gNB to UE and vice versa) and cell-level (for each
    %   gNB) KPIs. The connection-level KPIs provided by this class include
    %   application layer latency (applicable for non-full buffer traffic),
    %   user-perceived throughput at the application layer (applicable only for
    %   FTP), and block error rate (BLER) at the physical layer. The cell-level KPIs
    %   offered are the MAC layer's physical resource block (PRB) usage (expressed
    %   as a percentage) and the physical layer's BLER for both uplink and downlink.
    %   These parameters can be queried for a specific interval during the
    %   simulation or at the end of simulation.
    %
    %   KPIOBJ = hNRKPIManager creates a default 5G NR KPI object.
    %
    %   KPIOBJ = hNRKPIManager(Name=Value) creates a 5G NR KPI object with the
    %   specified property Name set to the specified Value. You can specify
    %   additional name-value arguments in any order as (Name1=Value1, ...,
    %   NameN=ValueN).
    %
    %   hNRKPIManager properties (configurable through name-value pairs only):
    %
    %   KPIString   - String array specifying KPIs to monitor.
    %   Node        - Cell array of nodes to monitor.
    %   LogInterval - KPI monitoring interval in seconds.
    %
    %   hNRKPIManager methods:
    %
    %   kpi - Returns the specified KPI for a link (source to destination) or for a
    %         single source node (cell-specific).

    %   Copyright 2025-2026 The MathWorks, Inc.

    properties (SetAccess = private)
        %KPIString String array specifying KPIs to monitor. The allowed values are
        %'app-latency', 'app-user-perceived-throughput', 'mac-prb-usage', and
        %'phy-bler'
        KPIString (1, :)

        %Node List of nodes to monitor
        Node = {}

        %LogInterval Default interval for monitoring KPIs. Units are in seconds.
        %   Its default value is 10 ms. To record KPI only at the end of the
        %   simulation, set the LogInterval as Inf.
        LogInterval (1, 1) {mustBeGreaterThanOrEqual(LogInterval, 1e-6)} = 10e-3;
    end

    properties (Constant, Access = private)
        %ValidKPIList Set of valid KPIs
        ValidKPIList = ["app-latency" "app-user-perceived-throughput", "mac-prb-usage" "phy-bler"];
    end

    properties (WeakHandle, Access = private)
        %GNB List of GNBs to monitor. A cell array of size N-by-1 where N is
        %the number of GNB nodes
        GNB nrGNB

        %UE List of UEs to monitor. A cell array of size N-by-1 where N is the
        %number of UE nodes
        UE nrUE

        %NetworkSimulator Simulator object of type wirelessNetworkSimulator
        NetworkSimulator wirelessNetworkSimulator
    end

    properties (Access = private)
        %NumGNBs Number of GNBs to monitor
        NumGNBs

        %NumUEs Number of UEs to monitor
        NumUEs

        %NodeIDList ID of nodes to monitor. A cell array of size N-by-1 where N is the
        %total number of nodes added
        NodeIDList

        %NumAppReceivedPackets Number of application packets received per connection. An
        %array of size M-N-P where M and N are the number of nodes to monitor and P is
        %the number of intervals for data collection. The number of intervals are equal
        %to ceil(simulation time/log interval). The element at index (i,j,k) corresponds
        %to the KPI data collected for packets received from source node i to
        %destination node j during log interval k
        NumAppReceivedPackets

        %TotalAppReceivedLatency Total latency of application packets received per
        %connection. An array of size M-N-P where M and N are the number of nodes to
        %monitor and P is the number of intervals for data collection. The number of
        %intervals are equal to ceil(simulation time/log interval). The element at index
        %(i,j,k) corresponds to the app latency between source node i and destination
        %node j during log interval k
        TotalAppReceivedLatency

        %NumRBsUsedPerCell Number of resource blocks used per cell. An array of size
        %M-N-P where M is the number of GNB nodes to monitor, N is the number of links
        %(downlink and uplink), and P is the number of intervals for data collection.
        %The number of intervals are equal to ceil(simulation time/log interval). The
        %element at index (i, j, k) specifies the number of resource blocks used by gNB
        %i for transmitting traffic over link j during log interval k
        NumRBsUsedPerCell

        %NumAvailableRBsPerCell Number of resource blocks available per cell. An array
        %of size M-N-P where M is the number of GNB nodes to monitor, N is the number of
        %links (downlink and uplink), and P is the number of intervals for data
        %collection. The number of intervals are equal to ceil(simulation time/log
        %interval). The element at index (i, j, k) specifies the number of resource
        %blocks available at gNB i for transmitting traffic over link j during log
        %interval k
        NumAvailableRBsPerCell

        %NumReceivedPacketsPerCell Number of packets received per cell. An array of size
        %M-N-P where M is the number of GNB nodes to monitor, N is the number of links
        %(downlink and uplink), and P is the number of intervals for data collection.
        %The number of intervals are equal to ceil(simulation time/log interval). The
        %element at index (i,j,k) corresponds to the number of PHY packets sent/received
        %by gNB node i over link j during log interval k
        NumReceivedPacketsPerCell

        %NumDecodeFailuresPerCell Number of decode failures per cell. An array of size
        %M-N-P where M is the number of GNB nodes to monitor, N is the number of links
        %(downlink and uplink), and P is the number of intervals for data collection.
        %The number of intervals are equal to ceil(simulation time/log interval). The
        %element at index (i,j,k) corresponds to the number of PHY packets decode
        %failures occured over link j for gNB node i during log interval k
        NumDecodeFailuresPerCell

        %NumReceivedPackets Number of packets received per connection. An array of size
        %M-N-P where M and N are the number of nodes to monitor and P is the number of
        %intervals for data collection. The number of intervals are equal to
        %ceil(simulation time/log interval). The element at index (i,j,k) corresponds to
        %the number of PHY packets received from source node i to destination node j
        %during log interval k
        NumReceivedPackets

        %NumDecodeFailures Number of decode failures per connection. An array of size
        %M-N-P where M and N are the number of nodes to monitor and P is the number of
        %intervals for data collection. The number of intervals are equal to
        %ceil(simulation time/log interval). The element at index (i,j,k) corresponds to
        %the number of PHY decode failures between source node i and destination node j
        %during log interval k
        NumDecodeFailures

        %UserPerceivedThroughputContext User perceived throughput (UPT) context for each
        %received file. An array of size N-N-P where M and N are the number of nodes to
        %monitor and P is the number of intervals for data collection. The number of
        %intervals are equal to ceil(simulation time/log interval). An element at
        %(i,j,k) holds the information of UPT context from source node i to destination
        %node j during the log interval k
        UserPerceivedThroughputContext

        %TrafficStatsForUPT Structure that holds for the context for UPT KPI. This
        %structure contains these fields.
        %   TrafficID - Traffic identifier between source and destination nodes.
        %   FileID    - File identifier.
        %   FileSize  - Size of FTP file (in bytes) as a scalar.
        %   ReceivedBytes - Number of bytes received corresponding to the file.
        %   RxStartTime   - Reception start time (in seconds).
        %   RxEndTime     - Reception end time (in seconds).
        %   ReceivedBytesWithOH - Number of bytes received (including TCP/IP overhead)
        %                         corresponding to the file.
        TrafficStatsForUPT = struct('TrafficID', [], 'FileID', [], ...
            'FileSize', 0, 'ReceivedBytes', 0, 'ReceivedBytesWithOH', 0, ...
            'RxStartTime', [], 'RxEndTime', []);

        %LastDataCollectionTime Time when KPI data was last collected
        LastDataCollectionTime = -1

        %LastIntervalIdx Last KPI logged interval index
        LastIntervalIdx = 0
    end

    properties (Constant, Hidden)
        %Downlink Identifier for downlink
        Downlink = 1;

        %Uplink Identifier for uplink
        Uplink = 2;
    end

    methods
        % Constructor
        function obj = hNRKPIManager(varargin)

            % Parse optional arguments and set properties
            for idx = 1:2:numel(varargin)
                obj.(varargin{idx}) = varargin{idx+1};
            end

            if iscell(obj.KPIString)
                error("KPIString must be provided as a row vector of strings or as a character vector.");
            else
                if ischar(obj.KPIString)
                    obj.KPIString = wnet.internal.matchString(obj.KPIString, obj.ValidKPIList);
                else
                    obj.KPIString = arrayfun(@(x) wnet.internal.matchString(x, obj.ValidKPIList), obj.KPIString);
                end
            end
            if iscell(obj.Node)
                nrNodeTypes = cellfun(@(x) isa(x(1), "nr5g.internal.nrNode"), obj.Node);
            else
                nrNodeTypes = arrayfun(@(x) isa(x, "nr5g.internal.nrNode"), obj.Node);
                obj.Node = arrayfun(@(x) x, obj.Node, "UniformOutput",false);
            end
            if ~all(nrNodeTypes)
                error("Node must be 'nrGNB' or 'nrUE'.")
            end

            % Initialize GNB and UE lists based on node types
            gNBIndices = cellfun(@(subNode)isa(subNode(1), "nrGNB"), obj.Node);
            gNBNodes = cell2mat(obj.Node(gNBIndices));
            ueNodes = cell2mat(obj.Node(~gNBIndices));
            if ~isempty(gNBNodes)
                obj.GNB = gNBNodes;
            end
            if ~isempty(ueNodes)
                obj.UE = ueNodes;
            end

            if isempty(obj.NetworkSimulator)
                % Get the network simulator instance, if not passed as N-V pair
                try
                    obj.NetworkSimulator = wirelessNetworkSimulator.getInstance();
                catch
                    % Error when there is no valid wireless network simulator instance
                    error("Initialize the wireless network simulator using 'wirelessNetworkSimulator.init' before creating the KPI manager instance.");
                end
            end
            % Schedule a pre-simulation action with the specified interval
            schedulePreSimulationAction(obj.NetworkSimulator, @obj.initLiveKPIContext, []);
        end

        function kpiValue = kpi(obj, sourceNode, destinationNode, kpiString, options)
            %kpi Return the key performance indicator (KPI) value for a specified KPI
            %between a source and destination node
            %
            %   KPIVALUE = kpi(OBJ, SOURCENODE, DESTINATIONNODE, KPISTRING, Name=Value)
            %   returns the KPI value, KPIVALUE, specified by KPISTRING, from the source
            %   node(s) represented by OBJ to the DESTINATIONNODE. The function supports
            %   calculations where either the source node or the destination node can be a
            %   vector, allowing for multiple KPI calculations across different connections.
            %   Additionally, if DESTINATIONNODE is empty, the function calculates KPIs at
            %   the cell level. The calculation of the KPI is determined by the OPTIONS
            %   provided.
            %
            %   KPIVALUE        - The calculated value of the specified KPI. If multiple
            %                     source-destination pairs are provided, kpiValue will be a
            %                     row vector containing the KPI value for each connection.
            %
            %   SOURCENODE      - Vector of source node objects from which the KPI is
            %                     measured. Each element in OBJ represents a source node.
            %
            %   DESTINATIONNODE - Vector of destination node objects to which the KPI is
            %                     measured. Each element in DESTINATIONNODE represents a
            %                     destination node. If empty, the KPI is calculated at the
            %                     cell level.
            %
            %   KPISTRING       - KPIs to be measured, specified as one of these options.
            %
            %                     "app-user-perceived-throughput" - Throughput measured at
            %                                                       application layer for
            %                                                       FTP traffic. Its units
            %                                                       are in Mbps.
            %                     "app-latency"   - Latency measured at the application
            %                                       layer. Its units are in seconds.
            %                     "phy-bler"      - BLER measured at the physical layer.
            %                     "mac-prb-usage" - PRB usage ratio measured at the MAC layer.
            %
            %   Name-Value Arguments:
            %
            %   StartTime - The start time of the interval over which the KPI is calculated.
            %               Defaults to 0.
            %
            %   EndTime   - The end time of the interval over which the KPI is calculated.
            %               Defaults to Inf.
            %
            %   LinkType  - Specifies the link type for cell-level KPIs as "DL" or "UL".
            %               This argument applies when KPISTRING is set to "mac-prb-usage"
            %               and "phy-bler". Defaults to "DL".

            arguments
                obj (1,1)
                sourceNode (1, :) nr5g.internal.nrNode
                destinationNode (1,:)
                kpiString (1,1) string
                options.StartTime (1,1) {mustBeNumeric, mustBeGreaterThanOrEqual(options.StartTime, 0)} = 0
                options.EndTime (1,1) {mustBeNumeric} = obj.LastDataCollectionTime;
                options.LinkType (1,1) {mustBeMember(options.LinkType,["DL","UL"])} = "DL";
            end

            currentTime = obj.NetworkSimulator.CurrentTime;
            endTime = options.EndTime;
            if currentTime < endTime
                error("'EndTime' must be less than or equal to the current simulation time");
            end

            startTime = options.StartTime;
            if startTime >= endTime
                error("'StartTime' must be less than the 'EndTime'");
            end

            % Validate inputs
            [kpiString, numSources, numDestinations] = validateKPIInputs(obj, ...
                sourceNode, destinationNode, kpiString);

            % Initialize kpiValue(s). If there are multiple sourceNode-destinationNode
            % connections provided as input, the function will populate the kpiValue(s) in a
            % row vector
            if numSources > numDestinations
                numKPIs = numSources;
            else
                numKPIs = numDestinations;
            end
            kpiValue = zeros(1,numKPIs);

            % If the log interval is set as Inf, then the log interval index
            % corresponding to both the start and end times will be 1, as KPIs are
            % logged only at the the end of the simulation
            if obj.LogInterval == Inf
                if options.StartTime ~= 0
                    error("'StartTime' must be equal to 0 when LogInterval is Inf as KPI is logged only at the end of the simulation");
                end
                if abs(obj.NetworkSimulator.EndTime - options.EndTime) > 1e-9
                    error("'EndTime' must be equal to simulation end time when LogInterval is Inf as KPI is logged only at the end of the simulation");
                end
                startTimeIndex = 1;
                endTimeIndex = 1;
            else
                % Validate the 'StartTime' w.r.t the 'LogInterval'
                logInterval = obj.LogInterval;
                roundedStartTime = round(startTime/logInterval) * logInterval;
                if abs(roundedStartTime - startTime) > 1e-9
                    error("'StartTime' must be a multiple of log interval");
                end

                % Calculate the log interval index corresponding to the start and end times
                startTimeIndex = round(startTime/logInterval) + 1;
                endTimeIndex = round(endTime/logInterval);
                roundedEndTime = endTimeIndex*logInterval;
                isSimEndTimeMatch = abs(obj.NetworkSimulator.EndTime - endTime) <= 1e-9;
                isMultipleOfLogInterval = abs(roundedEndTime - endTime) <= 1e-9;
                if ~isMultipleOfLogInterval && ~isSimEndTimeMatch
                    error("'EndTime' must be a multiple of log interval or the simulation end time");
                end
                if ~isMultipleOfLogInterval
                    % If EndTime is not a multiple of log interval, set the end time index to
                    % the ceiling of (EndTime/LogInterval)
                    endTimeIndex = ceil(endTime/logInterval);
                end
            end

            intervalIndices = startTimeIndex:endTimeIndex;
            currentSourceNode = sourceNode;
            currentDestinationNode = destinationNode;

            % Iterate through all sourceNode-destinationNode connections to obtain the
            % requested KPI
            for kpiIdx = 1:numKPIs
                % Determine the current source and destination nodes
                if numSources > 1
                    currentSourceNode = sourceNode(kpiIdx);
                else
                    if numDestinations == 0
                        currentDestinationNode = [];
                    else
                        currentDestinationNode = destinationNode(kpiIdx);
                    end
                end

                % Calculate the KPI based on the specified kpiString
                if kpiString == "app-latency"
                    kpiValue(kpiIdx) = calculateLatency(obj, currentSourceNode, currentDestinationNode, intervalIndices);
                elseif kpiString == "app-user-perceived-throughput"
                    kpiValue(kpiIdx) = calculateUPT(obj, currentSourceNode, currentDestinationNode, intervalIndices);
                elseif kpiString == "phy-bler"
                    kpiValue(kpiIdx) = calculateBLER(obj, currentSourceNode, currentDestinationNode, options.LinkType, intervalIndices);
                elseif kpiString == "mac-prb-usage"
                    kpiValue(kpiIdx) = calculatePRBUsage(obj, currentSourceNode, options.LinkType, intervalIndices);
                end
            end
        end
    end

    methods (Hidden)
        function initLiveKPIContext(obj, ~, ~)
            %initLiveKPIContext Initialize the context for different KPIs

            % Calculate the total number of intervals, including the start time
            numIntervals = ceil(1/obj.LogInterval) + 1;
            if obj.LogInterval ~= Inf
                % Schedule an action to collect KPIs at regular intervals
                scheduleAction(obj.NetworkSimulator, @(~,~) obj.collectKPIData, [], obj.LogInterval, obj.LogInterval);
            end

            % Get IDs of nodes registered with KPI manager
            obj.NodeIDList = [[obj.GNB.ID] [obj.UE.ID]];

            % Get the number of UEs and gNBs
            obj.NumGNBs = numel(obj.GNB);
            obj.NumUEs = numel(obj.UE);
            numNodes = obj.NumGNBs + obj.NumUEs;

            % Initialize matrices to store KPI data for each gNB and interval
            obj.NumReceivedPacketsPerCell = zeros(obj.NumGNBs, 2, numIntervals);
            obj.NumDecodeFailuresPerCell = zeros(obj.NumGNBs, 2, numIntervals);

            % Initialize matrices to store KPI data for each node pair and interval
            obj.NumReceivedPackets = zeros(numNodes, numNodes, numIntervals);
            obj.NumDecodeFailures = zeros(numNodes, numNodes, numIntervals);
            obj.NumAppReceivedPackets = zeros(numNodes, numNodes, numIntervals);
            obj.TotalAppReceivedLatency = zeros(numNodes, numNodes, numIntervals);

            % Initialize matrices to store resource block usage data for each gNB on each
            % link and interval
            obj.NumRBsUsedPerCell = zeros(obj.NumGNBs, 2, numIntervals); % 2 indicates number of links (UL + DL)
            obj.NumAvailableRBsPerCell = zeros(obj.NumGNBs, 2, numIntervals);

            % Schedule a post simulation action to collect the data for the last log
            % interval if simulation time is not a multiple of log interval
            schedulePostSimulationAction(obj.NetworkSimulator, @obj.collectKPIData, []);

            % Register events for the specified events
            if strcmpi(obj.KPIString, "app-user-perceived-throughput")
                obj.UserPerceivedThroughputContext = cell(numNodes, numNodes, numIntervals);
                if ~isempty(obj.GNB)
                    addlistener(obj.GNB, "AppDataReceived", @obj.processAppRxPacket);
                end

                if ~isempty(obj.UE)
                    addlistener(obj.UE, "AppDataReceived", @obj.processAppRxPacket);
                end
            end
        end

        function collectKPIData(obj, ~, ~)
            %collectKPIData Collect KPI data from network nodes at specific intervals

            % Get the current simulation time from the network simulator
            currentTime = obj.NetworkSimulator.CurrentTime;

            % Check if data has already been collected at this time
            if currentTime - obj.LastDataCollectionTime < 1e-9
                return; % Exit if data for the current time has already been collected
            end

            % Update the last data collection time to the current time
            obj.LastDataCollectionTime = currentTime;
            % Increment the LastIntervalIdx and set it as current interval index
            obj.LastIntervalIdx = obj.LastIntervalIdx + 1;
            intervalIdx = obj.LastIntervalIdx;

            % Iterate over each gNB (gNodeB)
            for gNBIdx = 1:obj.NumGNBs
                gNBNode = obj.GNB(gNBIdx);

                % Iterate over each KPI string
                for idx = 1:numel(obj.KPIString)
                    kpiString = obj.KPIString(idx);

                    if kpiString == "mac-prb-usage"
                        linkDir = ["DL" "UL"];
                        for linkIdx = [obj.Downlink obj.Uplink]
                            % Get PRB usage context for the gNB node
                            [~,numRBsUsed, numAvailableRBs] = kpi(gNBNode.MACEntity, "prbUsage", linkDir(linkIdx));
                            % Update KPI for number of RBs used and number of available RBs
                            updateKPI(obj, ["NumRBsUsedPerCell" "NumAvailableRBsPerCell"], gNBIdx, linkIdx, ...
                                intervalIdx, [numRBsUsed numAvailableRBs]);
                        end
                    elseif kpiString == "phy-bler"
                        for linkIdx = [obj.Downlink obj.Uplink]
                            % Get BLER context for the gNB node
                            [numReceivedPackets, numDecodeFailures] = obj.getBLERContext(gNBNode, [], linkIdx);
                            % Update KPI for number of received packets per cell and number of decode
                            % failures per cell
                            updateKPI(obj, ["NumReceivedPacketsPerCell" "NumDecodeFailuresPerCell"], gNBIdx, linkIdx, ...
                                intervalIdx, [numReceivedPackets numDecodeFailures]);
                        end

                        % Iterate over each UE
                        for ueIdx = 1:obj.NumUEs
                            ueNode = obj.UE(ueIdx);
                            connectionIdx = ueIdx + obj.NumGNBs;

                            % BLER for downlink
                            [numReceivedPackets, numDecodeFailures] = obj.getBLERContext(gNBNode, ueNode, obj.Downlink);
                            % Update KPI for number of received packets and number of decode failures
                            updateKPI(obj, ["NumReceivedPackets" "NumDecodeFailures"], gNBIdx, connectionIdx, ...
                                intervalIdx, [numReceivedPackets numDecodeFailures]);

                            % BLER for uplink
                            [numReceivedPackets, numDecodeFailures] = obj.getBLERContext(ueNode, gNBNode, obj.Uplink);
                            % Update KPI for number of received packets and number of decode failures
                            updateKPI(obj, ["NumReceivedPackets" "NumDecodeFailures"], connectionIdx, gNBIdx, ...
                                intervalIdx, [numReceivedPackets numDecodeFailures]);
                        end
                    elseif kpiString == "app-latency"
                        for ueIdx = 1:obj.NumUEs
                            ueNode = obj.UE(ueIdx);
                            connectionIdx = ueIdx + obj.NumGNBs;

                            % Get application latency context for downlink
                            [totalLatency, numReceivedPackets] = obj.getAppLatencyContext(gNBNode, ueNode);
                            % Update KPI for number of application received packets and total application
                            % received latency
                            updateKPI(obj, ["NumAppReceivedPackets" "TotalAppReceivedLatency"], gNBIdx, connectionIdx, ...
                                intervalIdx, [numReceivedPackets totalLatency]);

                            % Get application latency context for uplink
                            [totalLatency, numReceivedPackets] = obj.getAppLatencyContext(ueNode, gNBNode);
                            % Update KPI for number of application received packets and total application
                            % received latency
                            updateKPI(obj, ["NumAppReceivedPackets" "TotalAppReceivedLatency"], connectionIdx, gNBIdx, ...
                                intervalIdx, [numReceivedPackets totalLatency]);
                        end
                    end
                end
            end
        end
	end
	
	methods (Access = private)
        function [totalLatency, receivedPackets] = getAppLatencyContext(~, sourceNode, destinationNode)
            %getAppLatencyContext Return the packet latency (in seconds) for the connection
            %between the sourceNode and the destinationNode

            % Initialize latency to a default value of 0
            totalLatency = 0;
            receivedPackets = 0;

            % Access detailed statistics of the destination node's traffic
            dstStats = statistics(destinationNode.TrafficManager, true);

            % Iterate over each destination's statistics to find the matching source node
            for idx = 1:numel(dstStats.Destinations)
                % Check if the current destination's NodeID matches the sourceNode's ID
                if dstStats.Destinations(idx).NodeID == sourceNode.ID
                    % Update latency with the total latency for the matching source node
                    totalLatency = dstStats.Destinations(idx).TotalPacketLatency;
                    % Update the number of received packets for the matching source node
                    receivedPackets = dstStats.Destinations(idx).ReceivedPackets;
                    return; % Using return instead of break for immediate exit
                end
            end
        end

        function [numPXSCHPackets, numPXSCHFailures] = getBLERContext(obj, sourceNode, destinationNode, linkType)
            %getBLERContext Return the Block Error Rate (BLER) between the source node and
            %the destination node. If the destination node is empty, the BLER is calculated
            %at the cell level

            % Initialize packet and failure counters to zero
            numPXSCHPackets = 0;
            numPXSCHFailures = 0;

            % Check if the destination node is empty to calculate BLER at the cell level
            if isempty(destinationNode)
                % Iterate over each carrier PHY for the source node (gNB)
                for carrierIdx = 1:numel(sourceNode.PhyEntity)
                    % Access PHY statistics for the current carrier
                    carrierPHYStats = statistics(sourceNode.PhyEntity(carrierIdx));

                    % Check if the link type is downlink
                    if linkType == obj.Downlink
                        % Sum the transmitted packets for downlink
                        numPXSCHPackets = numPXSCHPackets + sum([carrierPHYStats.TransmittedPackets]);

                        % Read PDSCH failure count only once as MAC is common
                        if carrierIdx == 1
                            numPXSCHFailures = sourceNode.MACEntity.NumPDSCHNACKs;
                        end
                    else
                        % Sum the received packets for uplink
                        numPXSCHPackets = numPXSCHPackets + sum([carrierPHYStats.ReceivedPackets]);
                        % Sum the decode failures for uplink
                        numPXSCHFailures = numPXSCHFailures + sum([carrierPHYStats.DecodeFailures]);
                    end
                end
            else
                % Iterate over each carrier PHY for the destination node
                for carrierIdx = 1:numel(destinationNode.PhyEntity)
                    % Access PHY statistics for the current carrier
                    carrierPHYStat = statistics(destinationNode.PhyEntity(carrierIdx));
                    % Check if the link type is downlink
                    if linkType == obj.Downlink
                        % Sum the decode failures for the destination node
                        numPXSCHFailures = numPXSCHFailures + carrierPHYStat(carrierIdx).DecodeFailures;
                        % Sum the received packets for the destination node
                        numPXSCHPackets = numPXSCHPackets + carrierPHYStat(carrierIdx).ReceivedPackets;
                    else
                        for idx = 1:numel(carrierPHYStat) % For each connected UE
                            if sourceNode.ID == carrierPHYStat(idx).UEID % UE matched
                                numPXSCHFailures = numPXSCHFailures + carrierPHYStat(idx).DecodeFailures;
                                numPXSCHPackets = numPXSCHPackets + carrierPHYStat(idx).ReceivedPackets;
                                break;
                            end
                        end
                    end
                end
            end
        end

        function updateKPI(obj, kpiMatrixName, idx1, idx2, intervalIdx, value)
            %updateKPI Update the KPI matrix with the new value, considering previous
            %intervals

            for kpiIdx = 1:numel(kpiMatrixName)
                kpiName = kpiMatrixName (kpiIdx);
                if intervalIdx > 1
                    obj.(kpiName)(idx1, idx2, intervalIdx) = value(kpiIdx) - sum(obj.(kpiName)(idx1, idx2, 1:intervalIdx - 1));
                else
                    obj.(kpiName)(idx1, idx2, intervalIdx) = value(kpiIdx);
                end
            end
        end

        function [kpiString, numSources, numDestinations] = validateKPIInputs(obj, sourceNode, destinationNode, kpiString)
            %validateKPIInputs Validate the inputs for KPI method

            nodeIDList = obj.NodeIDList;
            % Validate source nodes
            sourceIds = [sourceNode.ID];
            missing = ~ismember(sourceIds, nodeIDList);
            if any(missing)
                error("Source node is not present in the list of nodes being monitored.");
            end

            % Validate destination nodes
            if ~isempty(destinationNode)
                destinationIDs = [destinationNode.ID];
                missing = ~ismember(destinationIDs, nodeIDList);
                if any(missing)
                    error("Destination node is not present in the list of nodes being monitored.");
                end
            end

            numSources = size(sourceNode,2);
            numDestinations = size(destinationNode,2);
            if numSources>1 && numDestinations>1
                error("Specify the 'destinationNode' argument of the 'kpi' function " + ...
                    " as a scalar for connection-specific KPIs or empty for cell-specific KPIs.");
            end

            % Validate the KPI type against the specified layer
            if strcmpi(kpiString, "app-latency")
                % Latency KPI requires a destination node
                if numDestinations == 0
                    error("Destination node must be nonempty for the KPI: %s.", kpiString);
                end
                kpiString = "app-latency";
            elseif strcmpi(kpiString, "app-user-perceived-throughput")
                % UPT KPI requires a destination node
                if numDestinations == 0
                    error("Destination node must be nonempty for the KPI: %s.", kpiString);
                end
                kpiString = "app-user-perceived-throughput";
            elseif strcmpi(kpiString, "mac-prb-usage")
                % PRB Usage KPI is calculated at the cell level, so destination node should be
                % empty
                if ~isa(sourceNode, "nrGNB") || numDestinations > 0
                    error("Source node must be an object of type 'nrGNB' and " + ...
                        "destination node must be empty for the KPI: %s.", kpiString);
                end
                kpiString = "mac-prb-usage";
            elseif strcmpi(kpiString, "phy-bler")
                % Set KPI string for BLER
                kpiString = "phy-bler";
            else
                % Throw an error if the KPI is invalid
                error("KPI string must be 'app-latency', 'app-user-perceived-throughput', " + ...
                    "'mac-prb-usage', or 'phy-bler'.");
            end
        end

        function value = calculateLatency(obj, sourceNode, destinationNode, intervalIndices)
            %calculateLatency Calculate the average application layer latency between a
            %source and destination node

            % Find the indices of the source and destination nodes in the list of nodes
            sourceNodeIdx = obj.NodeIDList == sourceNode.ID;
            destinationNodeIdx = obj.NodeIDList == destinationNode.ID;

            % Calculate the total number of application layer packets received over the
            % specified intervals
            numAppReceivedPackets = sum(obj.NumAppReceivedPackets(sourceNodeIdx, destinationNodeIdx, intervalIndices));

            % Calculate the total latency of the received packets over the specified
            % intervals
            totalLatency = sum(obj.TotalAppReceivedLatency(sourceNodeIdx, destinationNodeIdx, intervalIndices));

            % Calculate the average latency If there are no received packets, set the
            % latency to 0
            if numAppReceivedPackets > 0
                value = totalLatency / numAppReceivedPackets;
            else
                value = 0;
            end
        end

        function value = calculateUPT(obj, sourceNode, destinationNode, intervalIndices)
            %calculateUPT Calculate the average application layer throughput between a
            %source and destination node over specified intervals.

            % Find the indices of the source and destination nodes in the node list
            sourceNodeIdx = obj.NodeIDList == sourceNode.ID;
            destinationNodeIdx = obj.NodeIDList == destinationNode.ID;

            % Extract throughput context data for the given source, destination, and
            % intervals
            fileInfo = [obj.UserPerceivedThroughputContext{sourceNodeIdx, destinationNodeIdx, intervalIndices}];

            % If no file information is found, set fileIDList to empty
            if isempty(fileInfo)
                fileIDList = [];
            else
                % Extract unique file IDs from the fileInfo structure
                fileIDList = unique([fileInfo.FileID]);
            end

            % Preallocate array to store UPT values for each file
            uptValues = zeros(numel(fileIDList), 1);

            % Loop through each file ID to calculate its throughput
            for idx = 1:numel(fileIDList)
                % Select entries matching the current file ID
                selectedFiles = [fileInfo(fileIDList(idx) == [fileInfo.FileID])];
                % Compute the start time for throughput calculation (max of RxStartTime and
                % interval start)
                rxStartTime = max(selectedFiles(1).RxStartTime, (intervalIndices(1)-1)*obj.LogInterval);

                % Get the end times for all selected files
                rxEndTime = [selectedFiles.RxEndTime];
                % Use the minimum of file RxEndTime and interval end
                rxEndTime = min(intervalIndices(end)*obj.LogInterval, rxEndTime(end));

                % Calculate throughput: sum of received bytes (in Mbits) divided by duration
                uptValues(idx) = (sum([selectedFiles.ReceivedBytes])*8e-6)/(rxEndTime - rxStartTime);
            end

            % Compute the average throughput over all files, or 0 if no values
            if numel(uptValues)
                value = sum(uptValues)/numel(uptValues);
            else
                value = 0;
            end
        end

        function value = calculateBLER(obj, sourceNode, destinationNode, linkType, intervalIndices)
            %calculateBLER Calculate the Block Error Rate (BLER) for a given source and
            %destination node

            if isempty(destinationNode)
                % Calculate cell-level BLER when no specific destination node is provided

                % Find the index of the source node in the list of GNBs
                sourceNodeIdx = arrayfun(@(x) x.ID == sourceNode.ID, obj.GNB);

                % Determine the link index based on the link type. Use index 1 for downlink and
                % 2 for uplink
                if linkType == "DL"
                    linkIdx = obj.Downlink;
                else
                    linkIdx = obj.Uplink;
                end

                % Calculate the total number of received packets over the specified intervals
                numReceivedPackets = sum(obj.NumReceivedPacketsPerCell(sourceNodeIdx, linkIdx, intervalIndices));

                % Calculate the total number of decode failures over the specified intervals
                numDecodeFailures = sum(obj.NumDecodeFailuresPerCell(sourceNodeIdx, linkIdx, intervalIndices));

                % Calculate the BLER ratio. If there are no received packets, set the BLER
                % to NaN
                value = numDecodeFailures / numReceivedPackets;
            else
                % Calculate connection-level (or node-to-node) BLER when a specific destination
                % node is provided.

                % Find the indices of the source and destination nodes in the list of nodes
                sourceNodeIdx = obj.NodeIDList == sourceNode.ID;
                destinationNodeIdx = obj.NodeIDList == destinationNode.ID;

                % Calculate the total number of received packets between the nodes over the
                % specified intervals
                numReceivedPackets = sum(obj.NumReceivedPackets(sourceNodeIdx, destinationNodeIdx, intervalIndices));

                % Calculate the total number of decode failures between the nodes over the
                % specified intervals
                numDecodeFailures = sum(obj.NumDecodeFailures(sourceNodeIdx, destinationNodeIdx, intervalIndices));

                % Calculate the BLER ratio. If there are no received packets, set the BLER
                % to NaN
                value = numDecodeFailures / numReceivedPackets;
            end
        end

        function updateUPTStatistics(obj, sourceNodeIdx, dstNodeIdx, trafficID, fileID, ...
                fileGenerationTime, pktReceptionTime, packetLength, eofMarker)

            % Calculate the start and end indices for the interval
            logIndex = floor(pktReceptionTime/obj.LogInterval) + 1;
            % Retrieve the UPT statistics for the specified node
            trafficStatsForUPT = obj.UserPerceivedThroughputContext{sourceNodeIdx, dstNodeIdx, logIndex};
            % Find if the current fileID already exists in the statistics
            if isempty(trafficStatsForUPT)
                rxContextIdx = 1;
                % If fileID does not exist, initialize UPT context for a new file
                trafficStatsForUPT = obj.TrafficStatsForUPT;
                trafficStatsForUPT.TrafficID = trafficID;
                trafficStatsForUPT.FileID = fileID;
                trafficStatsForUPT.RxStartTime = fileGenerationTime;
            else
                rxContextIdx = find((fileID == [trafficStatsForUPT.FileID]) & ...
                    (trafficID == [trafficStatsForUPT.TrafficID]), 1);
                % If fileID does not exist, initialize UPT context for a new file
                if isempty(rxContextIdx)
                    rxContextIdx = numel(trafficStatsForUPT) + 1;
                    trafficStatsForUPT(rxContextIdx) = obj.TrafficStatsForUPT;
                    trafficStatsForUPT(rxContextIdx).TrafficID = trafficID;
                    trafficStatsForUPT(rxContextIdx).FileID = fileID;
                    trafficStatsForUPT(rxContextIdx).RxStartTime = fileGenerationTime;
                end
            end

            trafficStatsForUPT(rxContextIdx).RxEndTime = pktReceptionTime;
            trafficStatsForUPT(rxContextIdx).ReceivedBytesWithOH = ...
                    trafficStatsForUPT(rxContextIdx).ReceivedBytesWithOH + packetLength;
            trafficStatsForUPT(rxContextIdx).ReceivedBytes = ...
                trafficStatsForUPT(rxContextIdx).ReceivedBytes + packetLength - networkTrafficFTP.TCPIPOverhead;
            % If an EOF marker is provided, update the file size
            if ~isempty(eofMarker)
                trafficStatsForUPT(rxContextIdx).FileSize = eofMarker.Value;
            end
            % Update the stored statistics with the new values
            obj.UserPerceivedThroughputContext{sourceNodeIdx, dstNodeIdx, logIndex} = trafficStatsForUPT;
        end

        function value = calculatePRBUsage(obj, sourceNode, linkType, intervalIndices)
            %calculatePRBUsage Calculate the Physical Resource Block (PRB) usage ratio for a
            %specified gNB

            % Find the index of the source node in the list of GNBs
            sourceNodeIdx = arrayfun(@(x) x.ID == sourceNode.ID, obj.GNB);

            % Determine the link index based on the link type. Use index 1 for downlink and
            % 2 for uplink
            if linkType == "DL"
                linkIdx = 1;
            else
                linkIdx = 2;
            end

            % Calculate the total number of resource blocks used over the specified
            % intervals
            numRBsUsed = sum(obj.NumRBsUsedPerCell(sourceNodeIdx, linkIdx, intervalIndices));

            % Calculate the total number of available resource blocks over the specified
            % intervals
            numAvailableRBs = sum(obj.NumAvailableRBsPerCell(sourceNodeIdx, linkIdx, intervalIndices));

            % Calculate the PRB usage ratio. If there are no available RBs, set the usage to
            % 0
            if numAvailableRBs > 0
                value = numRBsUsed / numAvailableRBs;
            else
                value = 0;
            end
        end
    end

    methods (Hidden)
        function registerKPI(obj, kpiString, nodeList)
            %registerKPI Register a new KPI to the list of KPIs to monitor

            % Append the new KPI string to the existing list of KPIs
            obj.KPIString = [obj.KPIString kpiString];

            % Register the given set of nodes with KPI manager
            gNBIndices = cellfun(@(subNode)isa(subNode(1), "nrGNB"), nodeList);
            obj.GNB = [obj.GNB cell2mat(nodeList(gNBIndices))];
            obj.UE = [obj.UE cell2mat(nodeList(~gNBIndices))];
        end

        function processAppRxPacket(obj, ~, eventInfo)
            %processAppRxPacket Process the received application packet

            packetInfo = eventInfo.Data;
            % Find the indices of the source and destination nodes in the list of nodes
            sourceNodeIdx = obj.NodeIDList == packetInfo.SourceNodeID;
            destinationNodeIdx = obj.NodeIDList == eventInfo.Source.ID;
 
            % Don't log any information related to unregistered nodes
            if all(sourceNodeIdx == 0) || all(destinationNodeIdx == 0)
                return;
            end

            if isfield(packetInfo, "Tags")
                [packetInfo.Tags, appTimestampTag] = ...
                    wnet.internal.packetTags.remove(packetInfo.Tags, "AppTimestamp");
                [packetInfo.Tags, appTrafficIDTag] = ...
                    wnet.internal.packetTags.remove(packetInfo.Tags, "AppTrafficID");
                % Process UPT statistics if FTPFileID tag is present
                [packetInfo.Tags, fileIDTag] = ...
                    wnet.internal.packetTags.remove(packetInfo.Tags, "FTPFileID");
                if ~isempty(fileIDTag)
                    % EOF tag processing
                    [packetInfo.Tags, eofTag] = ...
                        wnet.internal.packetTags.remove(packetInfo.Tags, "FTPEOFMarker");
                    updateUPTStatistics(obj, sourceNodeIdx, destinationNodeIdx, ...
                        appTrafficIDTag.Value, fileIDTag.Value, appTimestampTag.Value, ...
                        packetInfo.CurrentTime, packetInfo.PacketLength, eofTag);
                end
            end
        end
    end
end