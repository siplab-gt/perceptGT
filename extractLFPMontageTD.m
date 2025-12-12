function extractLFPMontageTD(data, params)
%Dan Kim, 15th July 2025

% Extract parameters for this recording mode
recordingMode = params.recordingMode;
nChannels = params.nChannels;
fname = params.fname;

% Identify the different recordings
nLines = size(data.(recordingMode), 1);
FirstPacketDateTime = cell(nLines, 1);
for lineId = 1:nLines
    FirstPacketDateTime{lineId, 1} = data.(recordingMode)(lineId).FirstPacketDateTime;
end

FirstPacketDateTime = categorical(FirstPacketDateTime);
recNames = unique(FirstPacketDateTime);
nRecs = numel(recNames);

%Extract LFPs in a new structure for each recording
for recId = 1:nRecs
    datafield = data.(recordingMode)(FirstPacketDateTime == recNames(recId));
    
    LFP = struct;
    LFP.nChannels = size(datafield, 1);

    if LFP.nChannels ~= nChannels
        warning(['There are ' num2str(LFP.nChannels) ' instead of the expected ' num2str(nChannels) ' channels'])
    end
    
    LFP.channel_names = cell(1, LFP.nChannels);
    LFP.data = [];
    for chId = 1:LFP.nChannels

        %LFP.channel_names{chId} = strrep(datafield(chId).Channel, '_', ' ');
        LFP.channel_names{chId} = strrep(strrep(strrep(strrep(strrep(datafield(chId).Channel, 'ZERO', '0'), ...
        'ONE', '1'), ...
        'TWO', '2'), ...
        'THREE', '3'), ...
        '_', ' ');
        LFP.data(:, chId) = datafield(chId).TimeDomainData;
    end
    
    %Generating hemisphere information for plot titles.
    if all(contains(upper(LFP.channel_names), 'RIGHT'))
        hemiLabel = 'Right';
    elseif all(contains(upper(LFP.channel_names), 'LEFT'))
        hemiLabel = 'Left';
    else
        hemiLabel = 'Mixed';
    end

    % Generating channel lead information for plot
    %titles.
    elec_location = regexp(LFP.channel_names, '\d+', 'match');
    

    LFP.Fs = datafield(chId).SampleRateInHz;
    
    %Extract size of received packets
    GlobalPacketSizes = str2num(datafield(1).GlobalPacketSizes); %#ok<ST2NM>
    if sum(GlobalPacketSizes) ~= size(LFP.data, 1) && ~strcmpi(recordingMode, 'SenseChannelTests') && ~strcmpi(recordingMode, 'CalibrationTests')
       warning([recordingMode ': data length (' num2str(size(LFP.data, 1)) ' samples) differs from the sum of packet sizes (' num2str(sum(GlobalPacketSizes)) ' samples)'])
    end
    
    %Extract timestamps of received packets
    TicksInMses = str2num(datafield(1).TicksInMses); %#ok<ST2NM>
    if ~isempty(TicksInMses)
        LFP.firstTickInSec = TicksInMses(1)/1000; %first tick time (s)
    end 
    
    if ~isempty(TicksInMses) && params.correct4MissingSamples %TicksInMses is empty for SenseChannelTest
        TicksInS = (TicksInMses - TicksInMses(1))/1000; %convert to seconds and initiate at 0
        
        %If there are more ticks in data packets, ignore extra ticks
        nPackets = numel(GlobalPacketSizes);
        nTicks = numel(TicksInS);
        if  nPackets ~= nTicks
            warning('GlobalPacketSizes and TicksInMses have different lengths')
            
            maxPacketId = max([nPackets, nTicks]);
            nSamples = size(LFP.data, 1);
            
            %Plot
            figure; 
            ax(1) = subplot(2, 1, 1); plot(TicksInS, '.'); xlabel('Data packet ID'); ylabel('TicksInS'); xlim([0 max([nPackets nTicks])])
            ax(2) = subplot(2, 1, 2); plot(cumsum(GlobalPacketSizes), '.'); xlabel('Data packet ID'); ylabel('Cumulated sum of samples received'); xlim([0 max([nPackets nTicks])]);
            hold on; plot([0 maxPacketId], [nSamples, nSamples], '--')
            linkaxes(ax, 'x')
            
            TicksInS = TicksInS(1:nPackets);
                        
        end
        
        %Check if some ticks are missing
        isDataMissing = logical(TicksInS(end) >= sum(GlobalPacketSizes)/LFP.Fs);
        
        if isDataMissing
            LFP = correct4MissingSamples(LFP, TicksInS, GlobalPacketSizes);
        end  
                
    end
    
    LFP.time = (1:length(LFP.data))/LFP.Fs; % [s]
    if LFP.nChannels <= 2
        LFP.channel_map = 1:LFP.nChannels;
    else
        LFP.channel_map = params.channel_map;
    end
    LFP.xlabel = 'Time (s)';
    LFP.ylabel = 'LFP (uV)';
    LFP.json = fname;
    LFP.recordingMode = recordingMode;
    
    %save name
    savename = regexprep(char(recNames(recId)), {':', '-'}, {''});
    date = [savename(1:end-5)];
    %savename = [savename(1:end-5) '_' recordingMode];
    %!Dan's added code. Specification of save name for each recording mode. 
    if strcmp(recordingMode, 'IndefiniteStreaming')
        savename = [params.subjectID ' ' date ' ' recordingMode];
    elseif strcmp(recordingMode, 'BrainSenseTimeDomain')
        savename = [params.subjectID ' ' date ' ' recordingMode];
    elseif strcmp(recordingMode, 'SenseChannelTests')
        savename = [params.subjectID ' ' date ' ' recordingMode];
    elseif strcmp(recordingMode, 'CalibrationTests')
        elec_str = strjoin(elec_location{1}, '-');
        savename = [params.subjectID ' ' date ' ' recordingMode ' ' elec_str];
    elseif strcmp(recordingMode, 'LfpMontageTimeDomain')
        savename = [params.subjectID ' ' date ' ' recordingMode];
    end

    %For the save name, hemisphere side is added
    savename = [savename ' ' hemiLabel]

    %! Checking to see if it's 6 channel (not interested in intra and inter
    %values)
    if ~contains(LFP.channel_names{1}, 'segment', 'IgnoreCase', true)
        %Plot LFPs and save figure
        channelsFig = plotTseries(LFP.data, LFP);
        sgtitle([savename ' | LFP']);
        %added
        set(channelsFig, 'Units', 'inches');
        set(channelsFig, 'Position', [1, 1, 8, 6]);
        savefig(channelsFig, [params.save_pathname filesep savename '_LFP']);
        
        %Specifiy cases for different recordingModes. Also
        %renews savename for each recordingmode.
        %!Dan's added code Save as .png
        exportgraphics(channelsFig, fullfile(params.save_pathname, [savename '_LFPTimeDomain.png']), 'Resolution', 500);
    else
        %disp('----Inter and Intra ring channel signals skipped----')
        continue
    end

    %Plot spectrogram and save figure
    if ~isempty(TicksInMses) && params.correct4MissingSamples && isDataMissing %cannot compute Fourier transform on NaN
        warning('Spectrogram cannot be computed as some samples are missing.')
    else
       %checking to see if it's 6 channel (not interested in intra and inter values)
        if ~contains(LFP.channel_names{1}, 'segment', 'IgnoreCase', true)
            spectroFig = plotSpectrogram(LFP.data, LFP);
            sgtitle([savename ' | Spectrogram']);
            %added
            set(spectroFig, 'Units', 'inches');
            set(spectroFig, 'Position', [1, 1, 8, 6]);
            savefig(spectroFig, [params.save_pathname filesep savename '_Spectrogram']);
            exportgraphics(spectroFig, fullfile(params.save_pathname, [savename '_Spectrogram.png']),'Resolution',500)
        else
            continue
        end
    end
      
    %save LFPs
    save([params.save_pathname filesep savename '.mat'], 'LFP')
    disp([savename ' saved'])

end