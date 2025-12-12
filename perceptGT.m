% This toolbox loads JSON files retrieved from Percept PC/RC Device, extracts, 
% saves and plots BrainSenseSurvey PSD values and Timeline data in one
% folder per session. Additionally, relevant stimulation settings that are
% assumed to be affecting the Survey are extracted and exported as an excel. 
%
%Author: Dan Kim
    %Credit: Yohann Thenaisie 02.09.2020 - Lausanne University Hospital (CHUV)

%%%%%%%%%%%%%%%%%%% Change pathname to perceptGT %%%%%%%%%%%%%%%%%%%%
addpath(genpath('C:/Users/rlaan/perceptGT'))
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

choice = bigmenu('Select input mode:', {'A folder', 'JSON files'}, ...
    'Title', 'Input Mode', 'FontSize', 20, 'ButtonWidth', 400, 'Gap', 48);

if choice == 1
    disp('User picked: All JSON files in folder');
elseif choice == 2
    disp('User picked: Manual file selection');
else
    disp('No option selected (user closed dialog)');
    return
end


%% Select a folder
if choice == 1
    % Select a folder to load
    rootPath = uigetdir("",'Select the folder containg JSON files');
    
    if rootPath == 0
        disp('No folder selected');
        return
    end
    
    jsonFiles = dir(fullfile(rootPath, '**', '*.json'));
    if isempty(jsonFiles)
        disp('No JSON files found in selected folder.');
        return
    end
    
    % Making the "Result" folder
    [upFolder,lastFolder, ~] = fileparts(rootPath);

    % If selected folder is subfolder, sub-EMOPXXXX
    if startsWith(lastFolder, "sub-")
        outputPath = fullfile(upFolder, 'Result');
        cd(upFolder)
    else % it's already the main folder (e.g., Percept_files)
        outputPath = fullfile(rootPath, 'Result');
        cd(rootPath)
    end
    
    if ~exist(outputPath, 'dir')
        mkdir(outputPath);
    end
    
    data_pathname = rootPath;
    filenames = {jsonFiles.name};

%% In case it's JSON files
elseif choice == 2 

    % Select JSON files to load
    [filenames, data_pathname] = uigetfile('*.json', 'MultiSelect', 'on');
    
    % Check if any files were selected and process accordingly
    if isequal(filenames, 0)
        disp('No file selected');
        return
    end
    
    % If it's only one file that's selected, make it into a cell
    if ~iscell(filenames)
        filenames = {filenames};
    end
    
    % Get rid of last "\"s or "/"s
    if ismember(data_pathname(end), ['\' '/'])
    data_pathname = data_pathname(1:end-1);
    end

    % Making the "Result" folder
    [upFolder,lastFolder, ~] = fileparts(data_pathname);
    
    % If selected folder is subfolder, sub-EMOPXXXX
    if startsWith(lastFolder, "sub-")
        outputPath = fullfile(upFolder, 'Result');
        cd(upFolder)
    else % it's already the main folder (e.g., Percept_files)
        outputPath = fullfile(data_pathname, 'Result');
        cd(data_pathname)
    end

    if ~exist(outputPath, 'dir')
        mkdir(outputPath);
    end
    
end

%% Predefine the table
fieldNames = {'ImplantDate';'SessionDate';'Time Since Implant (hours)';'Time Since Followup (hours)';'Stim Settings';' ';' ';' ';' ';' ';' ';' '};
innerNames = {'';'';'';'';'Amplitude (mA)';'Pulse Width (us)';'Rate (Hz)';'Soft start stop-Status';'Soft start stop-Duration (s)';'Cycling-Status';'Cycling-On (s)';'Cycling-Off (s)'};
% Initialize table
T = table(fieldNames, innerNames, 'VariableNames', {'Field', 'Subfield'});

%% For loop for each file (each subject)
for fileId = 1:numel(filenames)
    %% Param reset for each subject
    amplitdue = NaN;
    pwidth = NaN;
    rateInHertz = NaN;
    sss_status = "";
    sss_duration = NaN;
    cycling_status = "";
    cycling_on = NaN;
    cycling_off = NaN;

    %%
    fname = filenames{fileId};
    data = jsondecode(fileread(fname));
    % Create a new folder per JSON file
    params.fname = fname;
    % Extract the subjectID
    subjectID = extractBetween(params.fname, 'sub-', '_');
    params.subjectID = subjectID{1};
    params.SessionDate = regexprep(data.SessionDate, {':', '-'}, {''});
    sessionDate_formatted = datetime(data.SessionDate,'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss''Z');
    params.save_pathname = fullfile(outputPath, ['sub-' subjectID{1}]);
    mkdir(params.save_pathname)
    params.correct4MissingSamples = false; %set as 'true' if device synchronization is required
    params.ProgrammerVersion = data.ProgrammerVersion;
    
    fprintf('---------------Processing %s--------------- \n',subjectID{1})
    % Call specific extraction functions based on JSON content
    % (Assuming these functions handle different data structures as per 'data')
    
    if isfield(data, 'DeviceInformation')
         DeviceInfoInitial = data.DeviceInformation.Initial;
         device = DeviceInfoInitial.Neurostimulator;
         implantDate = DeviceInfoInitial.ImplantDate;
         % Changing implantDate's structure for calculating the duration,
         % dur (between time implanted and today)
         implantDate_formatted = datetime(implantDate, ...
                       'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss''Z'); 
         deviceDate = DeviceInfoInitial.DeviceDateTime;
         timeSinceTherapy = (DeviceInfoInitial.AccumulatedTherapyOnTimeSinceImplant)/(60*60); %hours
         timeSinceFollowup = (DeviceInfoInitial.AccumulatedTherapyOnTimeSinceFollowup)/(60*60);%hours
    end

     % if isfield(data, 'LeadConfiguration')
     %     initial = data.LeadConfiguration.Initial
     %     final = data.LeadConfiguration.Final
     %     %1 = left, 2 = right.
     %     locationLeft = initial(1).LeadLocation%
     %     locationRight = initial(2).LeadLocation%
     %     orientationLeft = initial(1).OrientationInDegrees%
     %     orientationRight = initial(2).OrientationInDegrees%          
     % end
    

     %% For checking missing timerpoints
    % if isfield(data,'IndefiniteStreaming')
    %     TD = data.IndefiniteStreaming.TimeDomainData;
    %     lenTD = length(TD);
    %     Tick = data.IndefiniteStreaming.TicksInMses;
    %     Ticks = strsplit(Tick,',');
    %     lenTicks = length(Ticks);
    % 
    %     GPS = data.IndefiniteStreaming.GlobalPacketSizes;
    %     GPSs = strsplit(GPS,',');
    %     sumGPSs = sum(cell2mat(GPSs));
    %     lenGPS = length(GPS);
    % end

     %%
    if isfield(data, 'Groups')
        % discraded final since final settings are the ones that will be
        % newly simulating the brain, not the ones that were already done
        % for the BrainSense Survey data.

        groupTypes = {'Initial'};
        for g = 1:numel(groupTypes)
            %1=initial, 2=final
            groupData = data.Groups.(groupTypes{g});

            fprintf('\n--- Processing %s Group Settings ---\n', groupTypes{g});

            %% Finding the activegroup
            % 1 = A, 2 = B, 3 = C, 4= D.

            activeGroup = {};
            activeGroupIdx = [];
            for idx = 1:length(groupData)
                if groupData(idx).ActiveGroup == 1
                    activeGroup{end+1} = groupData(idx).GroupId;
                    activeGroupIdx(end+1) = idx;
                end
                
                if length(activeGroup) == 1;
                    parts = split(activeGroup{1},'.');
                    activeGroup = parts{end}; %Settings Group Name
                    activeGroupIdx = activeGroupIdx(1);
                end
            end
            
            
            %% Program settings variable inside Groups
            programSettings = groupData(activeGroupIdx).ProgramSettings;
            rateInHertz = programSettings.RateInHertz; %
            groupSettings = groupData(activeGroupIdx).GroupSettings;
            
            %sometimes it's the Left/RightHemisphere field, other times
            %it's the SensingChannel field. I'm not sure when one gets
            %activated over the other. When ?? is done, it's
            %SensingChannel?

            if isfield(programSettings, 'LeftHemisphere')
                %for the left hemisphere program settings
                leftP = programSettings.LeftHemisphere.Programs;
                lElectrodeState1 = leftP.ElectrodeState{1};
                lElectrodeState2 = leftP.ElectrodeState{2};
                lElectrode1 = lElectrodeState1.Electrode; %name of electrode1
                lElectrode1State = lElectrodeState1.ElectrodeStateResult; %negative or positive
                lElectrode2 = lElectrodeState2.Electrode; %name of electrode2
                lElectrode2State = lElectrodeState2.ElectrodeStateResult; %negative or positive
                
                lAmplitude = leftP.AmplitudeInMilliAmps;% I think left and right amplitude, pulsewidth are the same.
                lPulseWidth = leftP.PulseWidthInMicroSecond;%
                    
                %for the right hemisphere program settings
                rightP = programSettings.RightHemisphere.Programs;
                rElectrodeState1 = rightP.ElectrodeState{1};
                rElectrodeState2 = rightP.ElectrodeState{2};
                rElectrode1 = rElectrodeState1.Electrode; %name of electrode1
                rElectrode1State = rElectrodeState1.ElectrodeStateResult; %negative or positive
                rElectrode2 = rElectrodeState2.Electrode; %name of electrode2
                rElectrode2State = rElectrodeState2.ElectrodeStateResult; %negative or positive

                rAmplitude = rightP.AmplitudeInMilliAmps;% but just in case added these
                rPulseWidth = rightP.PulseWidthInMicroSecond;%
                
                if abs(lAmplitude-rAmplitude) < 0.5
                    amplitude = lAmplitude;
                    pwidth = lPulseWidth;
                else
                   fprintf("!Notice: Left Hemisphere amplitdue and Right Hemisphere amplitdues differ more than 0.5mA, average value is presented")
                   amplitude = (lAmplitude+rAmplitude)/2;
                   pwidth = (lPulseWidth+rPulseWidth)/2;
                   
                %GroupSettings
                sss_status = groupSettings.SoftStartStop.Enabled;
                sss_duration = groupSettings.SoftStartStop.DurationInSeconds;

                cycling_status = groupSettings.Cycling.Enabled;
                cycling_on = groupSettings.Cycling.OnDurationInMilliSeconds/10^3;
                cycling_off = groupSettings.Cycling.OffDurationInMilliSeconds/10^3;
                end

            elseif isfield(programSettings,'SensingChannel')
                sc = programSettings.SensingChannel;  
                scPulseWidth = sc.PulseWidthInMicroSecond; %pulsewidth in microseconds
                scRateInHertz = sc.RateInHertz ;%
                scSuspendAmplitude = sc.SuspendAmplitudeInMilliAmps; %amplitude, what's suspend?
                %Not sure what the lfp thresholds are
                scUpperLfpThreshold = sc.UpperLfpThreshold;%
                scLowerLfpThreshold = sc.LowerLfpThreshold;%
                %Amplitude upper & lower capture
                scUpperAmplitdue = sc.UpperCaptureAmplitudeInMilliAmps;
                scLowerAmplitdue = sc.LowerCaptureAmplitudeInMilliAmps;

                amplitude = scSuspendAmplitude;
                pwidth = scPulseWidth;
                rateInHertz = scRateInHertz;
               
            for h = 1:2  % 1 = left, 2 = right
                hemiStr = sc(h).HemisphereLocation;
                if length(hemiStr) < 4, continue; 
                end  % safety check
            
                if strcmpi(hemiStr(end-3:end), 'Left')
                    side = 'L';
                elseif strcmpi(hemiStr(end-4:end), 'Right') || strcmpi(hemiStr(end-3:end), 'ight')
                    side = 'R';
                else
                    continue;  % skip unknown hemisphere
                end
            
                % Find the positive electrode
                for i = 1:numel(sc(h).ElectrodeState)
                    state = sc(h).ElectrodeState{i}.ElectrodeStateResult;
                    if strcmpi(state(end-7:end), 'Positive')
                        electrode = sc(h).ElectrodeState{i}.Electrode;
                        if side == 'L'
                            lElectrode = electrode;
                            lElectrodeState = 'Positive';
                        else
                            rElectrode = electrode;
                            rElectrodeState = 'Positive';
                        end
                        break;  % stop after finding first positive
                    end
                end
            
                % Extract sensing setup
                sensing = sc.SensingSetup;
                freq = sensing.FrequencyInHertz;
                duration = sensing.AveragingDurationInMilliSeconds;
                chSplit = split(sensing.ChannelSignalResult.Channel, '.');
                channel = chSplit{end};
            
                % Assign to side-specific variables
                if side == 'L'
                    lssFreq = freq;
                    lssDuration = duration;
                    lssChannel = channel;
                elseif side == 'R'
                    rssFreq = freq;
                    rssDuration = duration;
                    rssChannel = channel;
                end
            end
            end
        %% GroupSettings: for soft start/stop and cycling params
            %lets denote softstartstop as sss
            softStartStop = groupSettings.SoftStartStop;
            sss_status = softStartStop.Enabled; %
            sss_duration = softStartStop.DurationInSeconds; % In seconds

            cycling = groupSettings.Cycling;
            cycling_status = cycling.Enabled; %
            cycling_on = cycling.OnDurationInMilliSeconds/(10^3); %to seconds 
            cycling_off = cycling.OffDurationInMilliSeconds/(10^3); %to seconds
        end
    end
       
     %% Making the table, displaying and exporting
     colName = subjectID{1};
     %subjectID, device, etc...
     colData = {
         implantDate_formatted;
         sessionDate_formatted;
         timeSinceTherapy;
         timeSinceFollowup;
         amplitude;
         pwidth;
         rateInHertz;
         double(sss_status); %Soft-start-stop
         sss_duration;
         double(cycling_status);
         cycling_on;
         cycling_off;
     };
     T.(colName) = colData;
     
    % Export to excel
    filename = fullfile(outputPath, 'subject_summary.xlsx');
    cfilename = fullfile(outputPath, 'subject_summary_combined.xlsx');

    % Pick which summary file to use as "oldtab" if it exists
    if exist(filename, 'file') && ~exist(cfilename,'file')
        basefile = filename
    elseif exist(cfilename, 'file')
        basefile = cfilename;
    else
        basefile = '';
    end
    
    if ~isempty(basefile)
        disp('Subject summary file already exists. Reading and combining...');
        oldtab = readtable(basefile);

        dups = intersect(T.Properties.VariableNames, oldtab.Properties.VariableNames);
        T(:, dups) = [];
        allTabs = [oldtab T];
    else
        disp('Subject summary file did not exist');
        allTabs = T;
    end
    
    if exist(cfilename,'file') || exist(filename,'file') || ~exist(filename,'file') || ~exist(cfilename,'file')
        % Deduplicate subject columns (keeping 'field' and 'subfield')
        varNames = allTabs.Properties.VariableNames;   % column names
        
        % Find subject columns (not 'field' or 'subfield')
        subjectMask = ~ismember(varNames, {'field', 'subfield'});
        
        % Get subject column names and deduplicate
        subjectNames = varNames(subjectMask);
        [~, subIdx] = unique(subjectNames, 'stable');
        
        % Indices for unique subject columns
        subjectIdxsInTable = find(subjectMask);
        uniqueSubjectIdxsInTable = subjectIdxsInTable(subIdx);
        
        % Now, final columns to keep: fields, subfields, then unique subjects
        finalIdx = [find(~subjectMask), uniqueSubjectIdxsInTable];
        
        % Reorder/deduplicate table
        allTabs = allTabs(:, finalIdx);
        
        % Now write combined/deduped table to a new file
        writetable(allTabs, cfilename);
        disp('Combined subject summary written to subject_summary_combined.xlsx');
    end

     %% LFP Data Extraction
     if isfield(data, 'LFPMontage') %Survey
        params.recordingMode = 'LFPMontage';
        %Extract and save LFP Montage PSD
        extractLFPMontage(data, params);
        
        %Extract and save LFP Montage Time Domain
        params.recordingMode = 'LfpMontageTimeDomain';
        params.nChannels = 6;
        params.channel_map = [1 2 3 ; 4 5 6];
        extractLFPMontageTD(data, params);
     end

     fprintf("Done with subject %s ! \n\n\n", params.subjectID)
end