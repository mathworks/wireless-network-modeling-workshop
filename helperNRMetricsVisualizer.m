classdef helperNRMetricsVisualizer < handle
    %helperNRMetricsVisualizer Creates metrics visualization object
    %   The class implements visualization of the metrics. The following three
    %   types of visualizations are shown:
    %       - Display of MAC Scheduler performance metrics
    %       - Display of Phy metrics
    %       - Display of RLC metrics
    %       - Display of CDF plots for cell throughput and block error rate (BLER) metrics
    %
    %   helperNRMetricsVisualizer methods:
    %
    %   plotLiveMetrics - Updates the metric plots by querying from nodes
    %
    %   helperNRMetricsVisualizer Name-Value pairs:
    %
    %   CellOfInterest       - Cell ID to which the visualization object belongs
    %   LinkDirection        - Indicates the link direction associated to the plots to visualize
    %   PlotSchedulerMetrics - Switch to turn on/off the scheduler performance metrics plots
    %   PlotPhyMetrics       - Switch to turn on/off the PHY metrics plots
    %   PlotRLCMetrics       - Switch to turn on/off the RLC metrics plots
    %   PlotCDFMetrics       - Switch to turn on/off the CDF plots for MAC cell
    %                          throughput, BLER and application latency metrics
    %   RefreshRate          - Visualization refresh rate in Hz (updates per second)

    %   Copyright 2022-2026 The MathWorks, Inc.

    properties
        %CellOfInterest Cell id to which the visualization belongs
        CellOfInterest (1, 1) {mustBeInteger, mustBeBetween(CellOfInterest, 0, 1007,"closed")} = 1;

        %LinkDirection  Indicates the link direction associated to the plots to visualize
        % It takes the values "DL", "UL", and "Both". Default value is "Both".
        LinkDirection (1,1) string {mustBeMember(LinkDirection, ["DL", "UL", "Both"])} = "Both";

        %PlotSchedulerMetrics Switch to turn on/off the scheduler performance metrics plots
        % It is a logical scalar. Set the value as true to enable the plots. By
        % default the plots ar disabled
        PlotSchedulerMetrics (1,1) logical = false;

        %PlotPhyMetrics Switch to turn on/off the PHY metrics plots
        % It is a logical scalar. Set the value as true to enable the plots. By
        % default, the plots are disabled
        PlotPhyMetrics (1,1) logical = false;

        %PlotRLCMetrics Switch to turn on/off the RLC metrics plots
        % It is a logical scalar. Set the value as true to enable the plots. By
        % default, the plots are disabled
        PlotRLCMetrics (1,1) logical = false;

        %PlotCDFMetrics Switch to turn on/off the CDF plots for MAC cell throughput, BLER and application latency metrics
        % It is a logical scalar. Set the value as true to enable the plots. By
        % default, the plots are disabled. The CDF plots are generated using data
        % collected at each metrics step duration i.e., duration (in milliseconds)
        % of one metrics step.
        PlotCDFMetrics (1,1) logical = false;

        %RefreshRate Visualization refresh rate in Hz
        RefreshRate (1,1) double {mustBePositive, mustBeInteger} = 10;
    end

    properties(Hidden)
        %MACVisualization Timescope to display the downlink and uplink scheduler performance metrics
        MACVisualization = cell(2, 1);

        %PhyVisualization Timescope to display the downlink and uplink block error rates
        PhyVisualization

        %RLCVisualization Timescope to display RLC layer's transmitted bytes
        RLCVisualization

        %PHYCDFVisualizationFigHandle Handle of the PHY CDF visualization
        PHYCDFVisualizationFigHandle

        %MACCDFVisualizationFigHandle Handle of the MAC CDF visualization
        MACCDFVisualizationFigHandle

        %AppCDFVisualizationFigHandle Handle of the App CDF visualization
        AppCDFVisualizationFigHandle

        %AvgBLER Average block error rate (BLER) for CellOfInterest
        % Matrix of size 'MetricsStepDuration-by-2', where 2 represents the columns
        % for downlink and uplink
        AvgBLER 

        %CellThroughput Cell throughput of CellOfInterest
        % Matrix of size 'MetricsStepDuration-by-2', where 2 represents the columns
        % for downlink and uplink
        CellThroughput

        %AvgAppLatency Average application layer latency for CellOfInterest
        % Matrix of size 'MetricsStepDuration-by-2', where 2 represents the columns
        % for downlink and uplink
        AvgAppLatency

        %KPIManager Store the hNRKPIManager class object to calculate the Key Performance Indicator (KPI) i.e., "phy-bler", "app-latency"
        KPIManager hNRKPIManager
    end

    properties (Access = private)
        %ULRLCMetrics Contains RLC metrics of UEs in uplink
        % It is a column vector of length M, where M represents the number of UEs
        ULRLCMetrics

        %DLRLCMetrics Contains RLC metrics of UEs in downlink
        % It is a column vector of length M, where M represents the number of UEs
        DLRLCMetrics

        %PeakDataRateDL Theoretical peak data rate
        % A vector of two elements. First and second elements represent the
        % downlink and uplink theoretical peak data rate respectively
        PeakDataRate = zeros(2, 1);

        %TargetBLER Target BLER
        % Same value for downlink and uplink
        TargetBLER = 0.1;

        %Bandwidth Carrier bandwidth
        % A vector of two elements and represents the downlink and uplink bandwidth
        % respectively
        Bandwidth

        %UELegend Legend for the UE
        UELegend

        %MetricsStepDuration Duration (in milliseconds) of 1 metrics step
        MetricsStepDuration

        %MACTxBytes Total bytes transmitted (newTx + reTx)
        MACTxBytes

        %MACRxBytes Total bytes received
        MACRxBytes

        %DLBLERInfo Information to calculate DL block error rate
        % It is a M-by-2 matrix, where M represents the number of UEs and the
        % column1, column2 represents the total decode failures and total packets
        % received in downlink
        DLBLERInfo

        %ULBLERInfo Information to calculate UL block error rate
        % It is a M-by-2 matrix, where M represents the number of UEs and the
        % column1, column2 represents the total decode failures and total packets
        % received in uplink
        ULBLERInfo

        %ResourceShareMetrics Number of RBs allocated to each UE
        % Matrix of size 'M-by-2', where M is the number of UEs, 2 represents the
        % columns for downlink and uplink
        ResourceShareMetrics

        %NumUEs The total number of UE node objects
        NumUEs

        %LinkDirectionIdx  Indicate the link direction index associated with the metrics plots
        % It takes the values 0, 1, 2 and represent downlink, uplink, and both link
        % directions respectively. Default value is 2.
        LinkDirectionIdx

        %RefreshInterval Indicate the time duration between metric updates (in seconds)
        RefreshInterval 
    end

    properties (WeakHandle, SetAccess = private)
        %GNB Node object of type nrGNB
        GNB nrGNB

        %UEs Vector of node objects of type nrUE
        UEs nrUE
    end

    properties(Access = private)
        %PlotIDs Represent the IDs of the plots. The value 1 and 2 indicate
        %downlink and uplink plot IDs, respectively
        PlotIDs = [1 2]

        %MaxMetricLinesPerSubPlot Maximum number of metric lines can be plotted in a sub-plot of time scope
        % Time scope allows plotting only 20 metric lines per sub-plot. 2 out 20
        % metric lines set aside for plotting cell level metrics like throughput
        % metric line and peak data rate metric line. Remaining 18 metric lines
        % will be used for plotting UE level metrics.
        MaxMetricLinesPerSubPlot = 18;
    end

    properties (SetAccess=private, WeakHandle, Hidden)
        %NetworkSimulator Handle of the wirelessNetworkSimulator instance
        % This can be set through N-V pair in the constructor. If not set, it will
        % be obtained by calling wirelessNetworkSimulator.getInstance().

        NetworkSimulator wirelessNetworkSimulator {mustBeScalarOrEmpty}
    end

    properties (Access = private, Constant, Hidden)
        % Constants related to downlink and uplink information. These constants are
        % used for indexing logs and identifying plots
        %DownlinkIdx Index for all downlink information
        DownlinkIdx = 1;
        %UplinkIdx Index for all uplink information
        UplinkIdx = 2;
    end

    methods (Access = public)
        function obj = helperNRMetricsVisualizer(gNB, UEs, varargin)
            %helperNRMetricsVisualizer Constructs metrics visualization object
            %
            % OBJ = helperNRMetricsVisualizer(GNB, UES) Create metrics visualization
            % object for downlink and uplink plots.
            %
            % OBJ = helperNRMetricsVisualizer(GNB, UES, Name=Value) creates a metrics
            % visualization object, OBJ, with properties specified by one or more
            % name-value pairs. You can specify additional name-value pair arguments in
            % any order as (Name1=Value1,...,NameN=ValueN).
            %
            % GNB   - Base station node of the cell
            % UEs   - UE nodes of the cell. They must be connected to GNB
            %
            % These are the name-value pairs that can be provided through varargin.
            %
            %   CellOfInterest       - Cell ID to which the visualization object belongs
            %   LinkDirection        - Indicates the link direction associated to the plots to visualize
            %   PlotSchedulerMetrics - Switch to turn on/off the scheduler performance metrics plots
            %   PlotPhyMetrics       - Switch to turn on/off the PHY metrics plots
            %   PlotCDFMetrics       - Switch to turn on/off the CDF plots for MAC cell throughput, BLER and application latency metrics
            %   RefreshRate          - Visualization refresh rate in Hz (updates per second)
            %   NetworkSimulator     - Network simulator instance

            % Initialize the properties
            for idx = 1:2:numel(varargin)
                obj.(varargin{idx}) = varargin{idx+1};
            end

            if isempty(obj.NetworkSimulator)
                % Get the network simulator instance, if not passed as N-V pair
                try
                    obj.NetworkSimulator = wirelessNetworkSimulator.getInstance;
                catch
                    % Error when there is no valid wireless network simulator instance
                    coder.internal.error("Initialize the wireless network simulator using 'wirelessNetworkSimulator.init' before creating the metrics visualizer instance.");
                end
            end

            obj.GNB = gNB;
            obj.UEs = UEs;

            % Create legend information for the plots
            totalNumUEs = numel(UEs);
            obj.NumUEs = totalNumUEs;

            ueOfInterestList = [UEs.RNTI];
            numUEsOfInterest = numel(ueOfInterestList);
            obj.UELegend = cell(1, numUEsOfInterest);
            for idx = 1:numUEsOfInterest
                obj.UELegend{idx} = UEs(idx).Name;
            end
            obj.DLBLERInfo = zeros(totalNumUEs, 2);
            obj.ULBLERInfo = zeros(totalNumUEs, 2);

            obj.MACTxBytes = zeros(totalNumUEs, 2);
            obj.MACRxBytes = zeros(totalNumUEs, 2);
            obj.ResourceShareMetrics = zeros(totalNumUEs, 2);

            obj.ULRLCMetrics = zeros(totalNumUEs, 1);
            obj.DLRLCMetrics = zeros(totalNumUEs, 1);

            [obj.PeakDataRate(obj.DownlinkIdx), obj.PeakDataRate(obj.UplinkIdx)] = calculatePeakDataRate(obj);
            obj.Bandwidth(obj.DownlinkIdx) = obj.GNB.ChannelBandwidth;
            obj.Bandwidth(obj.UplinkIdx) = obj.GNB.ChannelBandwidth;

            % Initialize the properties for visualizing the CDF plots
            obj.AvgBLER = [];
            obj.CellThroughput = [];
            obj.AvgAppLatency = [];

            obj.RefreshInterval = 1/obj.RefreshRate;
            logInterval = 10e-3; % Default log interval
            if obj.RefreshInterval < logInterval
                logInterval = obj.RefreshInterval;
            end

            if isempty(obj.KPIManager)
                % Create the hNRKPIManager object
                obj.KPIManager = hNRKPIManager(Node={obj.GNB,obj.UEs},KPIString=["phy-bler", "app-latency"],LogInterval=logInterval);
            end

            schedulePreSimulationAction(obj.NetworkSimulator, @obj.initLiveMetricPlots, []);
        end

        function addRLCVisualization(obj)
            %addRLCVisualization Create RLC visualization
            %
            % addRLCVisualization(OBJ) Create and configure RLC
            % visualization. It creates figures for visualizing metrics
            % in both downlink and uplink.

            % Create the timescope
            if isempty(obj.RLCVisualization)
                obj.RLCVisualization = timescope('Name', 'RLC Metrics Visualization');
            end

            % Maximum number of node PHY metrics allowed to plot
            numUEs = obj.NumUEs;
            if numUEs > obj.MaxMetricLinesPerSubPlot
                numUEs = obj.MaxMetricLinesPerSubPlot;
            end
            txBytes = zeros(1, numUEs);

            set(obj.RLCVisualization, 'LayoutDimensions', [numel(obj.PlotIDs) 1], 'ShowLegend', true, 'AxesScaling', 'Updates', 'AxesScalingNumUpdates', 1, ...
                'SampleRate', obj.RefreshRate,'TimeSpanSource', 'property','ChannelNames', repmat(obj.UELegend(1:numUEs), [1 numel(obj.PlotIDs)]), 'TimeSpan', 1);

            titles = {'Downlink RLC', 'Uplink RLC'};
            % Initialize the plots
            if isscalar(obj.PlotIDs)
                obj.RLCVisualization(txBytes);
            else
                obj.RLCVisualization(txBytes, txBytes);
            end

            % Add the titles and legends
            for idx=1:numel(obj.PlotIDs)
                obj.RLCVisualization.ActiveDisplay = idx;
                obj.RLCVisualization.YLabel = "Cell-" + obj.CellOfInterest + " Tx Rate (Mbps)";
                obj.RLCVisualization.Title = titles{obj.PlotIDs(idx)};
            end
        end

        function addMACVisualization(obj)
            %addMACVisualization Create MAC visualization
            %
            % addMACVisualization(OBJ) Create and configure MAC visualization. It
            % creates figures for visualizing metrics in both downlink and uplink.

            if obj.PlotSchedulerMetrics
                numUEs = obj.NumUEs;
                % Maximum number of node MAC metrics allowed to plot
                if numUEs > obj.MaxMetricLinesPerSubPlot
                    numUEs = obj.MaxMetricLinesPerSubPlot;
                end
                nodeMetrics = zeros(1, numUEs);
                % Plot titles and Y-axis label prefix
                title = {'Downlink Scheduler Performance Metrics', ...
                    'Uplink Scheduler Performance Metrics'};
                tag = {char('Cell-' + ""+ obj.CellOfInterest + ' DL '), ...
                    char('Cell-' + "" + obj.CellOfInterest + ' UL ')};
                channelNames = [obj.UELegend(1:numUEs) 'Cell' 'Peak Data Rate' obj.UELegend(1:numUEs) obj.UELegend(1:numUEs) 'Cell' 'Peak Data Rate' obj.UELegend(1:numUEs)];

                % Create time scope and add labels
                for idx=1:numel(obj.PlotIDs)
                    windowId = obj.PlotIDs(idx);

                    if isempty(obj.MACVisualization{windowId})
                        obj.MACVisualization{windowId} = timescope('Name', title{windowId});
                    end

                    set(obj.MACVisualization{windowId}, 'LayoutDimensions',[2 2], 'ChannelNames', channelNames,...
                        'ActiveDisplay',1, 'YLabel',[tag{windowId} 'Tx rate (Mbps)'], 'ShowLegend',true,'AxesScaling', 'Updates', ...
                        'AxesScalingNumUpdates', 1, 'TimeSpanSource', 'property', 'TimeSpan', 1, ...
                        'ActiveDisplay',2, 'YLabel',[tag{windowId} 'Resource Share (%)'], ...
                        'ShowLegend',true, 'YLimits',[1 100],'AxesScaling', 'Updates','AxesScalingNumUpdates', 1, ...
                        'SampleRate', obj.RefreshRate, 'TimeSpanSource', 'property', 'TimeSpan', 1, ...
                        'ActiveDisplay',3, 'YLabel',[tag{windowId} 'Throughput (Mbps)'], 'ShowLegend',true,'AxesScaling', 'Updates', 'AxesScalingNumUpdates', 1, ...
                        'SampleRate', obj.RefreshRate, 'TimeSpanSource', 'property', 'TimeSpan', 1, ...
                        'ActiveDisplay',4, 'YLabel',[tag{windowId} 'Buffer Status (KB)'], 'ShowLegend',true,'AxesScaling', 'Updates', 'AxesScalingNumUpdates', 1, ...
                        'SampleRate', obj.RefreshRate, 'TimeSpanSource', 'property', 'TimeSpan', 1);
                    obj.MACVisualization{windowId}([nodeMetrics 0 obj.PeakDataRate(windowId)], nodeMetrics, [nodeMetrics 0 obj.PeakDataRate(windowId)], nodeMetrics);
                end
            end
        end

        function addPhyVisualization(obj)
            %addPhyVisualization Create Phy visualization
            %
            % addPhyVisualization(OBJ) Create and configure Phy visualization. It
            % creates figures for visualizing metrics in both downlink and uplink.

            if obj.PlotPhyMetrics
                % Create and configure the timescope
                if isempty(obj.PhyVisualization)
                    obj.PhyVisualization = timescope('Name', 'Block Error Rate (BLER) Visualization');
                end

                % Maximum number of node PHY metrics allowed to plot
                numUEs = obj.NumUEs;
                if numUEs > obj.MaxMetricLinesPerSubPlot
                    numUEs = obj.MaxMetricLinesPerSubPlot;
                end
                blerData = zeros(1, numUEs);
                channelNames = [obj.UELegend(1:numUEs) 'Target BLER' obj.UELegend(1:numUEs) 'Target BLER'];

                set(obj.PhyVisualization, 'LayoutDimensions', [numel(obj.PlotIDs) 1], 'ShowLegend', true, 'AxesScaling', 'Updates', 'AxesScalingNumUpdates', 1, ...
                    'SampleRate', obj.RefreshRate, 'TimeSpanSource', 'property','ChannelNames', channelNames, 'TimeSpan', 1);

                titles = {'Downlink BLER', 'Uplink BLER'};
                % Initialize the plots
                if isscalar(obj.PlotIDs)
                    obj.PhyVisualization(blerData, obj.TargetBLER);
                else
                    obj.PhyVisualization([blerData, obj.TargetBLER], [blerData, obj.TargetBLER]);
                end

                % Add the titles and legends
                for idx=1:numel(obj.PlotIDs)
                    obj.PhyVisualization.ActiveDisplay = idx;
                    obj.PhyVisualization.YLimits = [0 1];
                    obj.PhyVisualization.YLabel = "Cell-" + obj.CellOfInterest + " BLER";
                    obj.PhyVisualization.Title = titles{obj.PlotIDs(idx)};
                end
            end
        end

        function plotLiveMetrics(obj, ~, ~)
            %plotLiveMetrics Updates the metric plots by querying from nodes

            % RLC metrics visualization
            if ~isempty(obj.RLCVisualization)
                plotLiveRLCMetrics(obj);
            end

            % MAC metrics visualization
            plotLiveMACMetrics(obj);

            % PHY metrics visualization
            plotLivePhyMetrics(obj);
        end

        function plotRemLiveMetrics(obj, varargin)
            %plotRemLiveMetrics Updates the remaining metric plots by querying from nodes, if
            %simulation time isn't a multiple of refresh interval

            if mod(obj.NetworkSimulator.EndTime, obj.RefreshInterval)
                plotLiveMetrics(obj,varargin);
            end
        end

        function calculateRemLatency(obj, varargin)
            %calculateRemLatency Calculates the latency for the remaining simulation
            %time, if simulation time isn't a multiple of refresh interval

            if mod(obj.NetworkSimulator.EndTime, obj.RefreshInterval)
                calculateLatency(obj,varargin);
            end
        end

        function displayPerformanceIndicators(obj)

            currTime = obj.NetworkSimulator.CurrentTime; % Simulation time (in seconds)
            if ismember(obj.UplinkIdx, obj.PlotIDs) % Uplink stats
                ulThroughput = (obj.MACRxBytes(:, obj.UplinkIdx) .* 8) ./ (currTime * 1000 * 1000); % Mbps
                ulPeakSpectralEfficiency = 1e6*obj.PeakDataRate(obj.UplinkIdx)/obj.Bandwidth(obj.UplinkIdx);
                ulAchSpectralEfficiency = 1e6*sum(ulThroughput)/obj.Bandwidth(obj.UplinkIdx);
                fprintf("Peak UL throughput: %0.2f Mbps\nAchieved cell UL throughput: %0.2f Mbps\n", obj.PeakDataRate(obj.UplinkIdx), sum(ulThroughput));
                fprintf(['Achieved UL throughput for each UE: [' num2str(round(ulThroughput, 2)') ']']);
                fprintf("\nPeak UL spectral efficiency: %0.2f bits/s/Hz\nAchieved UL spectral efficiency for cell: %0.2f bits/s/Hz \n", ulPeakSpectralEfficiency, ulAchSpectralEfficiency);

                ulBLER = obj.ULBLERInfo(:, 1) ./ obj.ULBLERInfo(:, 2);
                ulBLER(isnan(ulBLER)) = 0;
                fprintf(['Block error rate for each UE in the UL direction: [' num2str(round(ulBLER, 3)') ']\n\n']);
            end

            if ismember(obj.DownlinkIdx, obj.PlotIDs) % Downlink stats
                dlThroughput = (obj.MACRxBytes(:, obj.DownlinkIdx) .* 8) ./ (currTime * 1000 * 1000); % Mbps
                dlPeakSpectralEfficiency = 1e6*obj.PeakDataRate(obj.DownlinkIdx)/obj.Bandwidth(obj.DownlinkIdx);
                dlAchSpectralEfficiency = 1e6*sum(dlThroughput)/obj.Bandwidth(obj.DownlinkIdx);
                fprintf("Peak DL throughput: %0.2f Mbps\nAchieved cell DL throughput: %0.2f Mbps\n", obj.PeakDataRate(obj.DownlinkIdx), sum(dlThroughput));
                fprintf(['Achieved DL throughput for each UE: [' num2str(round(dlThroughput, 2)') ']']);
                fprintf("\nPeak DL spectral efficiency: %0.2f bits/s/Hz\nAchieved DL spectral efficiency for cell: %0.2f bits/s/Hz\n", dlPeakSpectralEfficiency, dlAchSpectralEfficiency);

                dlBLER = obj.DLBLERInfo(:, 1) ./ obj.DLBLERInfo(:, 2);
                dlBLER(isnan(dlBLER)) = 0;
                fprintf(['Block error rate for each UE in the DL direction: [' num2str(round(dlBLER, 3)') ']\n\n']);
            end
        end

        function [dlPeakDataRate, ulPeakDataRate] = calculatePeakDataRate(obj)
            %calculatePeakDataRate Calculate the theoretical peak data rate value

            % Peak data rate is calculated as per 3GPP TR 37.910 which defines it as
            % the received data bits assuming error free conditions assignable to a
            % single mobile station, when all assignable radio resources for the
            % corresponding link direction are utilized.
            gNB = obj.GNB;
            scs = gNB.SubcarrierSpacing/1e3;
            % Symbol duration for the given numerology
            symbolDuration = 1e-3/(14*(scs/15)); % Assuming normal cyclic prefix

            % Maximum number of transmission layers assuming all the resources are assigned to the UE.
            numLayersDL = min(gNB.NumTransmitAntennas, max([obj.UEs.NumReceiveAntennas]));
            numLayersUL = min(gNB.NumReceiveAntennas, max([obj.UEs.NumTransmitAntennas]));

            if strcmp(gNB.DuplexMode, "TDD")
                tddConfig = gNB.DLULConfigTDD;
                % Number of DL symbols in one DL-UL pattern
                numDLSymbols = tddConfig.NumDLSlots*14 + tddConfig.NumDLSymbols;
                % Number of UL symbols in one DL-UL pattern
                numULSymbols = tddConfig.NumULSlots*14 + tddConfig.NumULSymbols;
                % Number of symbols in one DL-UL pattern
                numSymbols = tddConfig.DLULPeriodicity*(scs/15)*14;
                % Normalized scalar considering the downlink symbol
                % allocation in the frame structure
                scaleFactorDL = numDLSymbols/numSymbols;
                % Normalized scalar considering the uplink symbol allocation
                % in the frame structure
                scaleFactorUL = numULSymbols/numSymbols;
            else % FDD
                % Normalized scalars in the DL and UL directions are 1 for
                % FDD mode
                scaleFactorDL = 1;
                scaleFactorUL = 1;
            end

            % Calculate uplink and downlink peak data rates as per 3GPP TS 37.910. The
            % maximum layers possible for a UE in DL direction is min(gNBTxAnts, ueRxAnts).
            % For UL direction, it is min(UETxAnts, gNBRxAnts).
            % The peak DL, UL throughput values for each UE
            dlPeakDataRate = 1e-6*numLayersDL*scaleFactorDL*8*(948/1024)*(gNB.NumResourceBlocks*12)/symbolDuration;
            ulPeakDataRate = 1e-6*numLayersUL*scaleFactorUL*8*(948/1024)*(gNB.NumResourceBlocks*12)/symbolDuration;
        end

        function metrics = getMetrics(obj)
            %getMetrics Return the metrics after live visualization
            %
            % METRICS = getMetrics(OBJ) Returns the metrics
            %
            % METRICS - It is a structure. It has the following fields.
            %   MACMetrics - Metrics of MAC layer
            %   PhyMetrics - Metrics of Phy layer

            metrics = struct('MACMetrics',[],'PhyMetrics',[]);
            rntiList = [obj.UEs.RNTI];

            dlTxBytes = obj.MACTxBytes(:, obj.DownlinkIdx);
            dlThroughputBytes = obj.MACRxBytes(:, obj.DownlinkIdx);
            dlRBs = obj.ResourceShareMetrics(:, obj.DownlinkIdx);
            ulTxBytes = obj.MACTxBytes(:, obj.UplinkIdx);
            ulThroughputBytes = obj.MACRxBytes(:, obj.UplinkIdx);
            ulRBs = obj.ResourceShareMetrics(:, obj.UplinkIdx);
            macMetrics = table(rntiList', dlTxBytes, dlThroughputBytes, dlRBs, ...
                ulTxBytes, ulThroughputBytes, ulRBs);
            macMetrics.Properties.VariableNames = {'RNTI', 'DL Tx Bytes', ...
                'DL Throughput Bytes', 'DL RBs allocated', 'UL Tx Bytes', 'UL Throughput Bytes', 'UL RBs allocated'};
            metrics.MACMetrics = macMetrics;

            phyMetrics = table(rntiList', obj.DLBLERInfo(rntiList, 2),obj.DLBLERInfo(rntiList, 1), ...
                obj.ULBLERInfo(rntiList, 2), obj.ULBLERInfo(rntiList, 1));
            phyMetrics.Properties.VariableNames = {'RNTI', 'Number of Packets (DL)', ...
                'Decode Failures (DL)', 'Number of Packets (UL)', 'Decode Failures (UL)'};
            metrics.PhyMetrics = phyMetrics;
        end

        function [cellSE, cellBLER] = getCellMetrics(obj)
            %getCellMetrics Extract spectral efficiency (SE) and block error
            % rate (BLER) for a cell
            %
            % [CELLSE, CELLBLER] = getCellMetrics(OBJ) Returns spectral
            % efficiency and BLER value corresponding to a cell.
            %
            % CELLSE   - Spectral efficiency of the cell (bps/Hz). It is a matrix of
            %            size 'MetricsStepDuration-by-2', where 2 represents
            %            the columns for downlink and uplink.
            % CELLBLER - BLER values for the cell. It is a matrix of size
            %            'MetricsStepDuration-by-2', where 2 represents
            %            the columns for downlink and uplink.
            %
            % The metric step duration is computed based on the following formula
            % metricsStepDuration = max(numSlotsPerSecond/obj.RefreshRate, 1) * (15 / scs)

            cellSE = 1e6*obj.CellThroughput./obj.Bandwidth;
            cellBLER = obj.AvgBLER;
        end
    end

    methods(Access = private)
        function plotLiveRLCMetrics(obj)
            %plotLiveRLCMetrics Plots the RLC live metrics

            ueList = obj.UEs;
            numUEs = obj.NumUEs;
            txRate = zeros(numUEs, 2);
            ulTxBytes = zeros(numUEs, 1);
            dlTxBytes = zeros(numUEs, 1);

            if obj.LinkDirectionIdx ~= 1 % Downlink
                gNBStats = statistics(obj.GNB, "all");
                gNBRLCStats = gNBStats.RLC.Destinations;
                for idx = 1:numUEs
                    rnti = ueList(idx).RNTI;
                    dlTxBytes(idx) = gNBRLCStats(rnti).TransmittedBytes;
                    txRate(idx, 1) = ((dlTxBytes(idx) - obj.DLRLCMetrics(idx))* 8) / (obj.MetricsStepDuration * 1000);
                    obj.DLRLCMetrics(idx) = dlTxBytes(idx);
                end
            end

            if obj.LinkDirectionIdx ~= 0 % Uplink
                for idx = 1:numUEs
                    ueStats = statistics(ueList(idx));
                    ulTxBytes(idx) = ueStats.RLC.TransmittedBytes;
                    txRate(idx, 2) = ((ulTxBytes(idx) - obj.ULRLCMetrics(idx))* 8) / (obj.MetricsStepDuration * 1000);
                    obj.ULRLCMetrics(idx) = ulTxBytes(idx);
                end
            end
            updateRLCMetrics(obj, txRate);
        end

        function plotLiveMACMetrics(obj)
            %plotLiveMACMetrics Plots the MAC live metrics

            ueList = obj.UEs;
            numUEs = obj.NumUEs;
            txRate = zeros(numUEs, 2);
            throughput = zeros(numUEs, 2);
            bufferstatus = zeros(numUEs, 2);
            resourceshare = zeros(numUEs, 2);
            cellTxRate = zeros(2, 2);
            cellThroughputMetrics = zeros(2, 2);
            gNBMACStats = statistics(obj.GNB, "all").MAC.Destinations;
            if obj.LinkDirectionIdx ~= 0 % Uplink
                for ueIdx = 1:numUEs
                    rnti = ueList(ueIdx).RNTI;
                    gNBRxBytes = gNBMACStats(rnti).ReceivedBytes;
                    throughput(ueIdx, obj.UplinkIdx) = (gNBRxBytes - obj.MACRxBytes(ueIdx, obj.UplinkIdx))* 8 / (obj.MetricsStepDuration * 1000); % In Mbps
                    obj.MACRxBytes(ueIdx, obj.UplinkIdx) = gNBRxBytes;

                    ueMACStats = statistics(ueList(ueIdx)).MAC;
                    txBytes = ueMACStats.TransmittedBytes + ueMACStats.RetransmissionBytes;
                    totalNumRBs = ueMACStats.ULTransmissionRB + ueMACStats.ULRetransmissionRB;

                    % Instant metrics calculation
                    txRate(ueIdx, obj.UplinkIdx) = (txBytes - obj.MACTxBytes(ueIdx, obj.UplinkIdx))* 8 / (obj.MetricsStepDuration * 1000); % In Mbps
                    resourceshare(ueIdx, obj.UplinkIdx) =  totalNumRBs - obj.ResourceShareMetrics(ueIdx, obj.UplinkIdx);
                    ueMAC = ueList(ueIdx).MACEntity;
                    bufferSize = sum(ueMAC.LCGBufferStatus);
                    bufferstatus(ueIdx, obj.UplinkIdx) = bufferSize/1000; % In KB

                    % Save the previous metrics
                    obj.MACTxBytes(ueIdx, obj.UplinkIdx) = txBytes;
                    obj.ResourceShareMetrics(ueIdx, obj.UplinkIdx) = totalNumRBs;
                end

                % Cell level metrics
                numRBScheduled = sum(resourceshare(:, obj.UplinkIdx));
                resourceshare(:, obj.UplinkIdx) = ((resourceshare(:, obj.UplinkIdx) ./ numRBScheduled) * 100); % Percent share
                cellTxRate(1, obj.UplinkIdx) = sum(txRate(:, obj.UplinkIdx)); % Cell Tx rate
                cellTxRate(2, obj.UplinkIdx) = obj.PeakDataRate(obj.UplinkIdx); % Peak datarate
                cellThroughputMetrics(1, obj.UplinkIdx) = sum(throughput(:, obj.UplinkIdx)); % Cell throughput
                cellThroughputMetrics(2, obj.UplinkIdx) = obj.PeakDataRate(obj.UplinkIdx); % Peak datarate
            end

            gNBMAC = obj.GNB.MACEntity;
            bufferSize = sum(gNBMAC.LCHBufferStatus,2);
            if obj.LinkDirectionIdx ~= 1 % Downlink
                for ueIdx = 1:numUEs
                    ueMACStats = statistics(ueList(ueIdx)).MAC;
                    throughput(ueIdx, obj.DownlinkIdx) = (ueMACStats.ReceivedBytes - obj.MACRxBytes(ueIdx, obj.DownlinkIdx))* 8 / (obj.MetricsStepDuration * 1000); % In Mbps
                    obj.MACRxBytes(ueIdx, obj.DownlinkIdx) = ueMACStats.ReceivedBytes;
                    totalNumRBs = ueMACStats.DLTransmissionRB + ueMACStats.DLRetransmissionRB;
                    resourceshare(ueIdx, obj.DownlinkIdx) = totalNumRBs - obj.ResourceShareMetrics(ueIdx, obj.DownlinkIdx);
                    obj.ResourceShareMetrics(ueIdx, obj.DownlinkIdx) = totalNumRBs;

                    % Instant metrics calculation
                    rnti = ueList(ueIdx).RNTI;
                    txBytes = gNBMACStats(rnti).TransmittedBytes + gNBMACStats(rnti).RetransmissionBytes;
                    txRate(ueIdx, obj.DownlinkIdx) = (txBytes - obj.MACTxBytes(ueIdx, obj.DownlinkIdx))* 8 / (obj.MetricsStepDuration * 1000); % In Mbps
                    bufferstatus(ueIdx, obj.DownlinkIdx) = bufferSize(rnti) ./ 1000; % In KB

                    % Save the previous metrics
                    obj.MACTxBytes(ueIdx, obj.DownlinkIdx) = txBytes;
                end

                % Cell level metrics
                numRBScheduled = sum(resourceshare(:, obj.DownlinkIdx));
                resourceshare(:, obj.DownlinkIdx) = (resourceshare(:, obj.DownlinkIdx) ./ numRBScheduled) * 100;
                cellTxRate(1, obj.DownlinkIdx) = sum(txRate(:, obj.DownlinkIdx)); % Cell Tx rate
                cellTxRate(2, obj.DownlinkIdx) = obj.PeakDataRate(obj.DownlinkIdx); % Peak datarate
                cellThroughputMetrics(1, obj.DownlinkIdx) = sum(throughput(:, obj.DownlinkIdx)); % Cell throughput
                cellThroughputMetrics(2, obj.DownlinkIdx) = obj.PeakDataRate(obj.DownlinkIdx); % Peak datarate
            end

            txRate = [txRate; cellTxRate];
            throughput = [throughput; cellThroughputMetrics];

            % Append downlink and uplink throughput values
            obj.CellThroughput = [obj.CellThroughput; cellThroughputMetrics(1,1), cellThroughputMetrics(1,2)];

            if obj.PlotSchedulerMetrics
                updateMACMetrics(obj, txRate', resourceshare', throughput', bufferstatus');
            end
        end

        function plotLivePhyMetrics(obj)
            %plotLivePhyMetrics Plots the Phy live metrics

            ueList = obj.UEs;
            numUEs = obj.NumUEs;
            blerData = zeros(numUEs, 2);
            dlBLERInfo = zeros(numUEs, 2);
            ulBLERInfo = zeros(numUEs, 2);
            startTimeForKPICal = max(0, round(obj.NetworkSimulator.CurrentTime - obj.RefreshInterval, 9));
            endTimeForKPICal = obj.NetworkSimulator.CurrentTime;

            if obj.LinkDirectionIdx ~= 1 % Downlink
                for idx = 1:numUEs
                    uePHYStats = statistics(ueList(idx)).PHY;
                    dlBLERInfo(idx, :) = [uePHYStats.DecodeFailures uePHYStats.ReceivedPackets];
                end
                blerData(:, obj.DownlinkIdx) = kpi(obj.KPIManager, obj.GNB, obj.UEs, "phy-bler", ...
                    StartTime=startTimeForKPICal, EndTime=endTimeForKPICal,LinkType="DL");
                obj.DLBLERInfo = dlBLERInfo;
            end

            if obj.LinkDirectionIdx ~= 0 % Uplink
                gNBPHYStats = statistics(obj.GNB,"all").PHY.Destinations;
                for idx = 1:numUEs
                    rnti = ueList(idx).RNTI;
                    ulBLERInfo(idx, :) = [gNBPHYStats(rnti).DecodeFailures gNBPHYStats(rnti).ReceivedPackets];
                end
                blerData(:, obj.UplinkIdx) = kpi(obj.KPIManager, obj.UEs, obj.GNB, "phy-bler", ...
                    StartTime=startTimeForKPICal, EndTime=endTimeForKPICal, LinkType="UL");
                obj.ULBLERInfo = ulBLERInfo;
            end
            blerData = blerData';

            % Calculate average BLER in the uplink and downlink directions
            avgBLERDL = kpi(obj.KPIManager, obj.GNB, [], "phy-bler", ...
                StartTime=startTimeForKPICal, EndTime=endTimeForKPICal, LinkType="DL");
            avgBLERUL = kpi(obj.KPIManager, obj.GNB, [], "phy-bler", ...
                StartTime=startTimeForKPICal, EndTime=endTimeForKPICal, LinkType="UL");
            % Append BLER values to the AvgBLER array
            obj.AvgBLER = [obj.AvgBLER; avgBLERDL, avgBLERUL];

            if obj.PlotPhyMetrics
                updatePhyMetrics(obj, blerData, obj.TargetBLER);
            end
        end

        function calculateLatency(obj, ~, ~)
            %calculateLatency Calculate the average application layer latency

            startTimeForKPICal = max(0, round(obj.NetworkSimulator.CurrentTime - obj.RefreshInterval, 9));
            endTimeForKPICal = obj.NetworkSimulator.CurrentTime;
            numUEs = obj.NumUEs;
            dlLatency = zeros(numUEs, 1);
            ulLatency = zeros(numUEs, 1);

            % Get the average application layer latency
            if obj.LinkDirectionIdx ~= 1 % Downlink
                dlLatency = kpi(obj.KPIManager, obj.GNB, obj.UEs, "app-latency", ...
                    StartTime=startTimeForKPICal, EndTime=endTimeForKPICal);
            end
            if obj.LinkDirectionIdx ~= 0 % Uplink
                ulLatency = kpi(obj.KPIManager, obj.UEs, obj.GNB, "app-latency", ...
                    StartTime=startTimeForKPICal, EndTime=endTimeForKPICal);
            end

            % Calculate average latency in the uplink and downlink directions
            numUEDL = nnz(dlLatency);
            numUEUL = nnz(ulLatency);
            avgLatencyDL = sum(nonzeros(dlLatency))/numUEDL;
            avgLatencyUL = sum(nonzeros(ulLatency))/numUEUL;

            % Append latency values to the AvgAppLatency array
            obj.AvgAppLatency = [obj.AvgAppLatency; avgLatencyDL, avgLatencyUL];
        end

        function updateRLCMetrics(obj, txRate)
            %updateRLCMetrics Update the RLC metrics

            txRate(isnan(txRate)) = 0; % To handle NaN

            % Determine the maximum UEs to plot the metrics
            numUEs = obj.NumUEs; % Number of UEs
            if numUEs > obj.MaxMetricLinesPerSubPlot
                numUEs = obj.MaxMetricLinesPerSubPlot;
            end

            % Update the plots
            if isscalar(obj.PlotIDs)
                obj.RLCVisualization(txRate(1:numUEs, obj.PlotIDs)');
            else
                obj.RLCVisualization(txRate(1:numUEs, obj.DownlinkIdx)', txRate(1:numUEs, obj.UplinkIdx)');
            end

            if mod(obj.NetworkSimulator.CurrentTime, 1) == 0 && obj.NetworkSimulator.CurrentTime~=obj.NetworkSimulator.EndTime
                % Update the x-axis limit as per the current simulation time
                obj.RLCVisualization.TimeSpan = obj.RLCVisualization.TimeSpan + 1;
            end
        end

        function updateMACMetrics(obj, txRate, resourceshare, throughput, bufferstatus)
            %updateMACMetrics Update the MAC metric plots

            % To handle NaN
            txRate(isnan(txRate)) = 0;
            resourceshare(isnan(resourceshare)) = 0;
            throughput(isnan(throughput)) = 0;
            bufferstatus(isnan(bufferstatus)) = 0;

            % Determine the maximum UEs to plot the metrics
            numUEs = obj.NumUEs; % Number of UEs
            cellLevelMetricsIdx = [numUEs+1 numUEs+2];
            if numUEs > obj.MaxMetricLinesPerSubPlot
                numUEs = obj.MaxMetricLinesPerSubPlot;
            end
            cellLevelMetricsIdx = [(1:numUEs) cellLevelMetricsIdx];

            for plotIdx = 1:numel(obj.PlotIDs)
                plotId = obj.PlotIDs(plotIdx);
                obj.MACVisualization{plotId}(txRate(plotId, cellLevelMetricsIdx), resourceshare(plotId, 1:numUEs), throughput(plotId, cellLevelMetricsIdx), bufferstatus(plotId, 1:numUEs));
                % Update the x-axis limit as per the current simulation time
                if mod(obj.NetworkSimulator.CurrentTime, 1) == 0 && obj.NetworkSimulator.CurrentTime~=obj.NetworkSimulator.EndTime
                    obj.MACVisualization{plotId}.TimeSpan =  obj.MACVisualization{plotId}.TimeSpan + 1;
                end
            end
        end

        function updatePhyMetrics(obj, blerData, targetBLER)
            %updatePhyMetrics Update the Phy metrics

            blerData(isnan(blerData)) = 0; % To handle NaN

            % Determine the maximum UEs to plot the metrics
            numUEs = obj.NumUEs; % Number of UEs
            if numUEs > obj.MaxMetricLinesPerSubPlot
                numUEs = obj.MaxMetricLinesPerSubPlot;
            end

            % Update the plots
            if isscalar(obj.PlotIDs)
                obj.PhyVisualization(blerData(obj.PlotIDs, 1:numUEs), targetBLER);
            else
                obj.PhyVisualization([blerData(obj.DownlinkIdx, 1:numUEs), targetBLER], [blerData(obj.UplinkIdx, 1:numUEs), targetBLER]);
            end

            if mod(obj.NetworkSimulator.CurrentTime, 1) == 0 && obj.NetworkSimulator.CurrentTime~=obj.NetworkSimulator.EndTime
                % Update the x-axis limit as per the current simulation time
                obj.PhyVisualization.TimeSpan = obj.PhyVisualization.TimeSpan + 1;
            end
        end

        function initLiveMetricPlots(obj, ~, ~)
            %initLiveMetricPlots Initialize metric plots

            % Update the LinkDirectionIdx based on the LinkDirection
            switch obj.LinkDirection
                case "DL"
                    obj.LinkDirectionIdx = 0;
                case "UL"
                    obj.LinkDirectionIdx = 1;
                otherwise
                    obj.LinkDirectionIdx = 2;
            end
            if obj.LinkDirectionIdx ~= 2
                % Either UL or DL is enabled
                obj.PlotIDs = obj.LinkDirectionIdx+1;
            end

            scs = obj.GNB.SubcarrierSpacing/1e3;
            % Interval at which metrics visualization updates in terms of number of
            % slots. Make sure that metric step size is an integer
            numSlotsPerSecond = scs/15e-3;
            metricsStepSize = max(numSlotsPerSecond/obj.RefreshRate,1);
            obj.MetricsStepDuration = metricsStepSize * (15 / scs);

            % Create Phy visualization
            addPhyVisualization(obj);

            % Create MAC visualization
            addMACVisualization(obj);

            % Create RLC visualization
            if obj.PlotRLCMetrics
                addRLCVisualization(obj);
            end

            networkSimulator = obj.NetworkSimulator;
            % Register periodic plot update event with network simulator
            if ~isempty(networkSimulator) && ~isempty(obj.GNB) && ~isempty(obj.UEs)
                scheduleAction(networkSimulator, @obj.plotLiveMetrics, [], 1/obj.RefreshRate, 1/obj.RefreshRate);
                scheduleAction(networkSimulator, @obj.calculateLatency, [], 1/obj.RefreshRate, 1/obj.RefreshRate);
                % Plot the remaining metrics, if simulation time isn't a multiple of refresh interval
                schedulePostSimulationAction(networkSimulator, @obj.plotRemLiveMetrics, []);
                % Calculate the latency for the remaining simulation time
                schedulePostSimulationAction(networkSimulator, @obj.calculateRemLatency, []);
                % Update the timescope as per the simulation time
                schedulePostSimulationAction(networkSimulator, @obj.updateTimescope, []);
                if obj.PlotCDFMetrics % Plot BLER and cell throughput CDF
                    schedulePostSimulationAction(networkSimulator, @obj.plotPHYCDF, []);
                    schedulePostSimulationAction(networkSimulator, @obj.plotMACCDF, []);
                    schedulePostSimulationAction(networkSimulator, @obj.plotAppCDF, []);
                end
            end
        end

        function plotPHYCDF(obj, varargin)
            %plotPHYCDF Plot CDF plots for the BLER

            % Create the visualization for BLER CDF plots
            titles = {'Average Cell DL BLER', 'Average Cell UL BLER'};
            obj.PHYCDFVisualizationFigHandle = uifigure('Name', 'ECDF of Block Error Rate (BLER)', 'HandleVisibility', 'on');
            % Use desktop theme to support dark theme mode
            matlab.graphics.internal.themes.figureUseDesktopTheme(obj.PHYCDFVisualizationFigHandle);
            subPlotAxes = createCDFVisualization(obj, obj.PHYCDFVisualizationFigHandle);

            for idx=1:numel(obj.PlotIDs)
                ax = subPlotAxes{idx};
                if obj.LinkDirectionIdx == 1 % Only uplink visualization is on
                    idx = 2;
                end
                data = obj.AvgBLER(:,idx);
                data(isnan(data)) = []; % To handle NaN

                if isempty(data)
                    % Delete the axis, if no data to plot
                    delete(ax);
                    if ~all(isvalid([subPlotAxes{:}]))
                        % Delete the figure
                        delete(obj.PHYCDFVisualizationFigHandle);
                    end
                else
                    % Call local function to calculate and plot ecdf
                    calculateAndPlotECDF(ax, data, titles{idx}, 'Average BLER', 'BLER');
                end
            end
        end

        function plotMACCDF(obj, varargin)
            %plotMACCDF Plot CDF plots for the cell throughput and average user throughput

            % Create the visualization for cell throughput CDF plots
            titles = {'Cell DL Throughput', 'Cell UL Throughput'};
            obj.MACCDFVisualizationFigHandle = uifigure('Name', 'ECDF of Cell Throughput', 'HandleVisibility', 'on');
            % Use desktop theme to support dark theme mode
            matlab.graphics.internal.themes.figureUseDesktopTheme(obj.MACCDFVisualizationFigHandle);
            subPlotAxes = createCDFVisualization(obj, obj.MACCDFVisualizationFigHandle);

            for idx=1:numel(obj.PlotIDs)
                ax = subPlotAxes{idx};
                if obj.LinkDirectionIdx == 1 % Only uplink visualization is on
                    idx = 2;
                end
                data = obj.CellThroughput(:,idx);

                if isempty(data)
                    % Delete the axis, if no data to plot
                    delete(ax);
                    if ~all(isvalid([subPlotAxes{:}]))
                        % Delete the figure
                        delete(obj.MACCDFVisualizationFigHandle);
                    end
                else
                    % Call local function to calculate and plot ecdf
                    calculateAndPlotECDF(ax, data, titles{idx}, 'Cell Throughput', 'Cell Throughput (Mbps)');
                end
            end
        end

        function plotAppCDF(obj, varargin)
            %plotAppCDF Plot CDF plots for the average application layer latency

            % Create the visualization for BLER CDF plots
            titles = {'Average App DL Latency', 'Average App UL Latency'};
            obj.AppCDFVisualizationFigHandle = uifigure('Name', 'ECDF of Application Layer Latency', 'HandleVisibility', 'on');
            % Use desktop theme to support dark theme mode
            matlab.graphics.internal.themes.figureUseDesktopTheme(obj.AppCDFVisualizationFigHandle);
            subPlotAxes = createCDFVisualization(obj, obj.AppCDFVisualizationFigHandle);

            for idx=1:numel(obj.PlotIDs)
                ax = subPlotAxes{idx};
                if obj.LinkDirectionIdx == 1 % Only uplink visualization is on
                    idx = 2;
                end
                data = obj.AvgAppLatency(:,idx);
                data(isnan(data)) = []; % To handle NaN

                if isempty(data)
                    % Delete the axis, if no data to plot
                    delete(ax);
                    if ~all(isvalid([subPlotAxes{:}]))
                         % Delete the figure
                        delete(obj.AppCDFVisualizationFigHandle);  
                    end
                else
                    % Call local function to calculate and plot ecdf
                    calculateAndPlotECDF(ax, data, titles{idx}, 'Average Latency', 'Latency (s)');
                end
            end
        end

        function subPlotAxes = createCDFVisualization(obj, figureHandle)
            %createCDFVisualization Create visualization for a figure

            g = uigridlayout(figureHandle);
            g.RowHeight = {'1x'};
            g.ColumnWidth = {'1x'};
            panel = uipanel(g);
            panel.AutoResizeChildren = 'off';
            panel.BorderType = 'none';
            % Create subplot based on the PlotIDs
            subPlotAxes = cell(1,1);
            for idx=1:numel(obj.PlotIDs)
                subPlotAxes{idx} = subplot(numel(obj.PlotIDs),1,idx,'Parent', panel);
            end
        end


        function updateTimescope(obj, varargin)
            %updateTimescope Adjust timescopes at the end of simulation
            if obj.PlotPhyMetrics
                obj.PhyVisualization.TimeSpan = obj.NetworkSimulator.CurrentTime;
                obj.PhyVisualization.release();
            end
            if obj.PlotSchedulerMetrics
                for plotIdx = 1:numel(obj.PlotIDs)
                    plotId = obj.PlotIDs(plotIdx);
                    obj.MACVisualization{plotId}.TimeSpan = obj.NetworkSimulator.CurrentTime;
                    obj.MACVisualization{plotId}.release();
                end
            end
            if obj.PlotRLCMetrics
                obj.RLCVisualization.TimeSpan = obj.NetworkSimulator.CurrentTime;
                obj.RLCVisualization.release();
            end
        end
    end
end

function calculateAndPlotECDF(ax, data, figureTitle, legendName, xLabel)
%calculateAndPlotECDF Calculate and plot ecdf for data

dataLen = numel(data);
% Calculate the empirical cumulative distribution function F, evaluated at x,
% using the data
[x, F] = stairs(sort(data),(1:dataLen)/dataLen);
% Include a starting value, required for accurate plot
x = [x(1); x];
F = [0; F];

% Plot the estimated empirical cdf
axes(ax);
plot(x,F);
% Plot a horizontal line corresponding to 5th and 95th percentile points in the
% CDF plot
points = [5 95];
yline(points/100,'--');

title(figureTitle);
ax.YTick = 0:0.1:1;
xlabel(xLabel);
ylabel('ECDF');
legend(legendName,'Location','best');
grid on;
if isequal(xLabel,'BLER') % Set x-axis limit for BLER metric plots
    ax.XLim = [0 1];
end
end