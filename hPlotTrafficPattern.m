function plotTrafficPattern(simulationDuration,cfgPeriodic)
currentTime = 0;         % Current simulation time
packetSizeBits = cfgPeriodic.PacketSize*8;              % Convert packet size from bytes to bits
dataRateSeconds = cfgPeriodic.DataRate*1000;            % Convert data rate from kilobits/second to bits/second
timePerPacket = packetSizeBits/dataRateSeconds;         % Time to generate one packet in seconds
numPackets = ceil(simulationDuration/timePerPacket);
packetTimes = zeros(1,numPackets);
packetSizes = zeros(1,numPackets);
packetCount = 0;
% Generate Periodic Traffic
while currentTime < simulationDuration
    % Generate packet and calculate next packet generation time
    [dt,packetSize] = generate(cfgPeriodic);
    currentTime = currentTime + dt/1000; % Convert ms to seconds for the next iteration
    packetCount = packetCount + 1;
    packetTimes(packetCount) = currentTime;
    packetSizes(packetCount) = packetSize;
    fprintf("Time: %f s - Generated a periodic packet_%d of size %d bytes\n", currentTime, packetCount,packetSize);
end

figure % Creates a new figure window
stem(packetTimes, packetSizes,"filled", ...
    Marker="v",MarkerSize=6,MarkerFaceColor="b")
xlabel("Time (s)")
ylabel("Packet Size (bytes)")
title("Packet Generation Over Time")
xlim([0 simulationDuration])
ylim([0 max(packetSizes) * 1.1]) % Adjust Y-axis to clearly show packet sizes
legend("Packet Generation", "Location", "Best")
end