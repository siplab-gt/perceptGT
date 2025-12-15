% === Percept PC/RC JSON pipeline (deep scan; tidy summary) ===
% Extracts settings from Percept JSONs, writes a tidy spreadsheet
% (one row per file/acquisition), and extracts BrainSense Survey
% PSD/TD into Result/sub-XXXX when present.

%%%%%%%%%%%%%%%%%%% Change pathname to perceptGT %%%%%%%%%%%%%%%%%%%%
addpath(genpath('/Users/rlaan/Capstone/'))
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% --- Keep MATLAB figures from popping up (and auto-restore at end) ---
suppressFigures = true;
if suppressFigures
    prevFigVis   = get(groot,'defaultFigureVisible');
    set(groot,'defaultFigureVisible','off');
    set(groot,'DefaultFigureCreateFcn','set(gcf,''Visible'',''off'')');
    cleanupFigVis = onCleanup(@() set(groot, ...
        'defaultFigureVisible',prevFigVis, ...
        'DefaultFigureCreateFcn',''));
end

% === TEMP enable UI for bigmenu ===
prevCF = get(groot,'DefaultFigureCreateFcn');
set(groot,'DefaultFigureCreateFcn','');
set(groot,'defaultFigureVisible','on');

choice = bigmenu('Select input mode:', ...
    {'A folder (scan for all JSONs)', ...
    'JSON files (pick manually)', ...
    'A parent folder with many subject subfolders'}, ...
    'Title','Input Mode','FontSize',20,'ButtonWidth',480,'Gap',48);

if choice == 1
    disp('User picked: All JSON files in a folder (recursive)');
elseif choice == 2
    disp('User picked: Manual file selection');
elseif choice == 3
    disp('User picked: Parent directory containing many subject folders');
else
    disp('No option selected (user closed dialog)'); return
end

% === restore UI suppression after bigmenu ===
set(groot,'defaultFigureVisible','off');
set(groot,'DefaultFigureCreateFcn', prevCF);

%% Select inputs (supports parent-folder-of-subjects)
filenames = {};

if choice == 1
    rootPath = uigetdir('', 'Select the folder containing JSON files');
    if rootPath == 0, disp('No folder selected'); return; end
    L = dir(fullfile(rootPath, '**', '*'));
    L = L(~[L.isdir]);
    paths = cellfun(@fullfile, {L.folder}, {L.name}, 'UniformOutput', false);
    filenames = paths(endsWith(lower(paths), '.json'));
    if isempty(filenames), disp('No JSON files found in selected folder.'); return; end
    fprintf('Found %d JSON files under %s\n', numel(filenames), rootPath);

elseif choice == 2
    [filenames, data_pathname] = uigetfile('*.json', 'MultiSelect', 'on');
    if isequal(filenames, 0), disp('No file selected'); return; end
    if ~iscell(filenames), filenames = {filenames}; end
    filenames = cellfun(@(n) fullfile(data_pathname, n), filenames, 'UniformOutput', false);

elseif choice == 3
    parentPath = uigetdir('', 'Select the PARENT folder (containing sub-* folders)');
    if parentPath == 0, disp('No folder selected'); return; end

    prevCF2 = get(groot,'DefaultFigureCreateFcn');
    set(groot,'DefaultFigureCreateFcn',''); set(groot,'defaultFigureVisible','on');
    answer = inputdlg({'Subfolder name pattern (glob):'}, 'Subject Folder Pattern', 1, {'sub-*'});
    set(groot,'defaultFigureVisible','off'); set(groot,'DefaultFigureCreateFcn', prevCF2);

    if isempty(answer), disp('Cancelled'); return; end
    subPattern = strtrim(answer{1}); if isempty(subPattern), subPattern = 'sub-*'; end

    subjDirs = dir(fullfile(parentPath, subPattern)); subjDirs = subjDirs([subjDirs.isdir]);
    if isempty(subjDirs)
        warning('No subject folders matching "%s" found under %s', subPattern, parentPath);
        return;
    end

    allFiles = {};
    for k = 1:numel(subjDirs)
        thisSub = fullfile(parentPath, subjDirs(k).name);
        L = dir(fullfile(thisSub, '**', '*'));
        L = L(~[L.isdir]);
        paths = cellfun(@fullfile, {L.folder}, {L.name}, 'UniformOutput', false);
        jf = paths(endsWith(lower(paths), '.json'));
        if ~isempty(jf), allFiles = [allFiles, jf]; else, fprintf('No JSON files found in %s\n', thisSub); end
    end
    filenames = unique(allFiles);
    if isempty(filenames), disp('No JSON files found in any subject folder.'); return; end
    fprintf('Found %d JSON files across %d subject folders under %s\n', numel(filenames), numel(subjDirs), parentPath);
end

% --- Tidy summary collector (one row per file) ---
rows = struct([]);         % collected records
masterOutputPath = '';     % first file's Result/ becomes the write location

%% Process each JSON
for fileId = 1:numel(filenames)
    fname = filenames{fileId};

    % ---------- Put outputs in Result next to nearest sub-* ancestor ----------
    [fileDir, ~, ~] = fileparts(fname);
    p = fileDir;
    while true
        [parent, base] = fileparts(p);
        if startsWith(base, 'sub-'), resultParent = parent; break; end
        if isempty(parent) || strcmp(parent, p), resultParent = fileDir; break; end
        p = parent;
    end
    outputPath = fullfile(resultParent, 'Result');
    if ~exist(outputPath, 'dir'), mkdir(outputPath); end
    if fileId == 1, masterOutputPath = outputPath; end
    % -------------------------------------------------------------------------

    % Defaults per file
    rateInHertz = NaN; months = NaN;
    lAmplitude = NaN; rAmplitude = NaN; lPulseWidth = NaN; rPulseWidth = NaN;
    sss_status = false; sss_duration = NaN;
    cycling_status = false; cycling_on = NaN; cycling_off = NaN;
    implantDate_formatted = NaT; timeSinceTherapy = NaN; timeSinceFollowup = NaN;

    % Read JSON robustly
    try
        rawtxt = fileread(fname);
        data = jsondecode(rawtxt);
        jsonSessionDate = NaT;
        if isfield(data,'SessionDate') && ~isempty(data.SessionDate)
            try
                jsonSessionDate = datetime(data.SessionDate,'InputFormat','yyyy-MM-dd''T''HH:mm:ss''Z');
            catch
            end
        end
    catch ME
        warning('Skipping %s (JSON decode failed): %s', fname, ME.message);
        continue
    end

    % ================= Deep scan for Survey fields anywhere =================
    foundPSD = isfield(data,'LFPMontage');
    foundTD  = isfield(data,'LfpMontageTimeDomain');

    nodes = {data}; ctxs  = {''}; guardCount = 0;
    while ~isempty(nodes) && (~foundPSD || ~foundTD) && guardCount < 100000
        guardCount = guardCount + 1;
        node = nodes{1}; nodes(1) = [];
        ctx  = ctxs{1};  ctxs(1)  = [];

        if isstruct(node)
            if numel(node) > 1
                for ii = 1:numel(node)
                    nodes{end+1} = node(ii);
                    if isempty(ctx)
                        ctxs{end+1}  = sprintf('(%d)', ii);
                    else
                        ctxs{end+1}  = sprintf('%s(%d)', ctx, ii);
                    end
                end
                continue
            end

            fns = fieldnames(node);
            fnsLower = lower(fns);
            isStreamingContext = contains(ctx, 'indefinitestreaming', 'ignorecase', true);
            looksLikeSurveyCtx = any(contains(fnsLower, {'lfpmontage','lpfmontage','montage','survey','brainsense'}));

            if ~foundPSD
                idx = find(strcmpi(fns,'LFPMontage') | strcmpi(fns,'LfpMontage'), 1);
                if ~isempty(idx)
                    data.LFPMontage = node.(fns{idx});
                    foundPSD = true;
                    fprintf('Promoted PSD from %s.%s\n', ctx, fns{idx});
                end
            end

            if ~foundTD
                idxTD = find(strcmpi(fns,'LfpMontageTimeDomain') | strcmpi(fns,'LFPMontageTimeDomain') | ...
                    strcmpi(fns,'TimeDomainData') | strcmpi(fns,'TimeDomain'), 1);
                if ~isempty(idxTD)
                    if ~isStreamingContext && (looksLikeSurveyCtx || any(contains({ctx}, {'survey','brainsense','montage'}, 'IgnoreCase', true)))
                        data.LfpMontageTimeDomain = node.(fns{idxTD});
                        foundTD = true;
                        fprintf('Promoted TD from %s.%s\n', ctx, fns{idxTD});
                    end
                end
            end

            for k = 1:numel(fns)
                val = node.(fns{k});
                if isempty(ctx), childCtx = fns{k}; else, childCtx = [ctx '.' fns{k}]; end

                if isstruct(val)
                    if numel(val) > 1
                        for ii = 1:numel(val)
                            nodes{end+1} = val(ii); ctxs{end+1} = sprintf('%s(%d)', childCtx, ii);
                        end
                    else
                        nodes{end+1} = val; ctxs{end+1} = childCtx;
                    end
                elseif iscell(val)
                    for ci = 1:numel(val)
                        v = val{ci};
                        if isstruct(v)
                            if numel(v) > 1
                                for ii = 1:numel(v)
                                    nodes{end+1} = v(ii); ctxs{end+1} = sprintf('%s{%d}', childCtx, ci);
                                end
                            else
                                nodes{end+1} = v; ctxs{end+1} = sprintf('%s{%d}', childCtx, ci);
                            end
                        end
                    end
                end
            end

        elseif iscell(node)
            for ci = 1:numel(node)
                v = node{ci};
                if isstruct(v)
                    if numel(v) > 1
                        for ii = 1:numel(v)
                            nodes{end+1} = v(ii); ctxs{end+1} = sprintf('%s{%d}', ctx, ci);
                        end
                    else
                        nodes{end+1} = v; ctxs{end+1} = sprintf('%s{%d}', ctx, ci);
                    end
                end
            end
        end
    end

    hasPSD = isfield(data,'LFPMontage');
    hasTD  = isfield(data,'LfpMontageTimeDomain');
    hasStreamingTD    = isfield(data,'IndefiniteStreaming') && isstruct(data.IndefiniteStreaming) && isfield(data.IndefiniteStreaming,'TimeDomainData');
    hasStreamingPower = isfield(data,'IndefiniteStreaming') && isstruct(data.IndefiniteStreaming) && (isfield(data.IndefiniteStreaming,'PowerDomainData') || isfield(data.IndefiniteStreaming,'PowerDomain'));

    if hasPSD || hasTD
        fprintf('Detected Survey data after deep scan: PSD=%d, TD=%d\n', hasPSD, hasTD);
    elseif hasStreamingTD || hasStreamingPower
        fprintf('Detected IndefiniteStreaming: TD=%d, Power=%d\n', hasStreamingTD, hasStreamingPower);
    else
        fprintf('No BrainSense Survey fields found in %s.\n', fname);
        try disp('Top-level fields:'), disp(fieldnames(data)'); end
    end
    % ================= End deep scan =======================================

    % ---------- subject, acq, run ----------
    params = struct(); params.fname = fname;
    [~, baseName, ~] = fileparts(fname);

    % subject ID
    m = regexpi(baseName, 'sub-([^_]+)', 'tokens', 'once');
    if ~isempty(m)
        params.subjectID = m{1};
    else
        m2 = regexpi(fname, 'sub-([^/\\_]+)', 'tokens', 'once');
        if ~isempty(m2), params.subjectID = m2{1}; else, params.subjectID = 'unknown'; end
    end
    subjectID = {params.subjectID};
    params.save_pathname = fullfile(outputPath, ['sub-' subjectID{1}]);
    if ~exist(params.save_pathname, 'dir'), mkdir(params.save_pathname); end
    
    % Device info (timing)
    if isfield(data,'DeviceInformation') && isfield(data.DeviceInformation,'Initial')
        DI = data.DeviceInformation.Initial;
        if isfield(DI,'ImplantDate') && ~isempty(DI.ImplantDate)
            try, implantDate_formatted = datetime(DI.ImplantDate,'InputFormat','yyyy-MM-dd''T''HH:mm:ss''Z'); end
        end
        if isfield(DI,'AccumulatedTherapyOnTimeSinceImplant'),  timeSinceTherapy  = DI.AccumulatedTherapyOnTimeSinceImplant  / 3600; end
        if isfield(DI,'AccumulatedTherapyOnTimeSinceFollowup'), timeSinceFollowup = DI.AccumulatedTherapyOnTimeSinceFollowup / 3600; end
        % Calculate # of months based on implant date and session date
        d1 = datetime(DI.ImplantDate,'InputFormat',"yyyy-MM-dd'T'HH:mm:ssX",'TimeZone','UTC');
        d2 = datetime(jsonSessionDate,'InputFormat',"yyyy-MM-dd'T'HH:mm:ssX",'TimeZone','UTC');
        months = double(calmonths(between(d1,d2,'months')));
        %implantDate
        %jsonSessionDate
    end

    % acq/run from filename OR full path (case-insensitive)
    mAcq = {num2str(months)};  % mAcq = regexpi(baseName, 'acq-([^_\.]+)', 'tokens', 'once');
    mRun = regexpi(baseName, 'run-([^_\.]+)', 'tokens', 'once');
    if isempty(mAcq), mAcq = regexpi(fname, 'acq-([^/\\_\.]+)', 'tokens', 'once'); end
    if isempty(mRun), mRun = regexpi(fname, 'run-([^/\\_\.]+)', 'tokens', 'once'); end

    params.sessionLabel = ''; params.runLabel = '';
    if ~isempty(mAcq), params.sessionLabel = ['acq-' mAcq{1} 'm']; end
    if ~isempty(mRun), params.runLabel     = ['run-' mRun{1}]; end
    if isempty(params.sessionLabel), params.sessionLabel = 'acq-NA'; end
    if isempty(params.runLabel),     params.runLabel     = 'run-NA'; end

    acqLabelOut = params.sessionLabel;
    runLabelOut = params.runLabel;

    % Session date (info only)
    params.SessionDate = '';
    sessionDate_formatted = NaT;
    if isfield(data,'SessionDate') && ~isempty(data.SessionDate)
        try
            params.SessionDate = regexprep(data.SessionDate, {':','-'}, {'',''});
            sessionDate_formatted = datetime(data.SessionDate,'InputFormat','yyyy-MM-dd''T''HH:mm:ss''Z');
        catch
            params.SessionDate = regexprep(char(data.SessionDate), {':','-'}, {'',''});
        end
    end




    % -------- Groups (program settings) with robust hemisphere extraction ------
    if isfield(data, 'Groups')
        groupTypes = {'Initial'}; % only "Initial" (Final=plan)
        for g = 1:numel(groupTypes)
            groupData = data.Groups.(groupTypes{g});
            % pick active group element, else first
            activeIdx = [];
            for idx = 1:numel(groupData)
                if isfield(groupData(idx),'ActiveGroup') && isequal(groupData(idx).ActiveGroup, 1)
                    activeIdx = idx; break;
                end
            end
            if isempty(activeIdx), activeIdx = 1; end
            if numel(groupData) < activeIdx, continue; end
            block = groupData(activeIdx);

            % ProgramSettings might be an array; pick ActiveProgram if present
            PS = struct();
            if isfield(block,'ProgramSettings')
                tempPS = block.ProgramSettings;
                if isstruct(tempPS) && ~isempty(tempPS)
                    if numel(tempPS) > 1
                        psIdx = 1;
                        for kps = 1:numel(tempPS)
                            if isfield(tempPS(kps),'ActiveProgram') && isequal(tempPS(kps).ActiveProgram,1)
                                psIdx = kps; break;
                            end
                        end
                        PS = tempPS(psIdx);
                    else
                        PS = tempPS;
                    end
                end
            end

            % GroupSettings for soft start / cycling
            if isfield(block,'GroupSettings'), groupSettings = block.GroupSettings; else, groupSettings = struct(); end

            % ----- HEMISPHERE EXTRACTION (inline) -----

            % Classic: LeftHemisphere/RightHemisphere.Programs
            if isfield(PS,'LeftHemisphere') && isfield(PS.LeftHemisphere,'Programs')
                L = PS.LeftHemisphere.Programs;
                if isstruct(L) && ~isempty(L)
                    if numel(L) > 1
                        ai = find(arrayfun(@(x)isfield(x,'ActiveProgram') && isequal(x.ActiveProgram,1), L),1);
                        if isempty(ai), ai = 1; end
                        L = L(ai);
                    end
                    if isfield(L,'AmplitudeInMilliAmps'),     lAmplitude  = L.AmplitudeInMilliAmps; end
                    if isfield(L,'PulseWidthInMicroSecond'),  lPulseWidth = L.PulseWidthInMicroSecond; end
                    if isfield(L,'RateInHertz') && isnan(rateInHertz), rateInHertz = L.RateInHertz; end
                end
            end
            if isfield(PS,'RightHemisphere') && isfield(PS.RightHemisphere,'Programs')
                R = PS.RightHemisphere.Programs;
                if isstruct(R) && ~isempty(R)
                    if numel(R) > 1
                        ai = find(arrayfun(@(x)isfield(x,'ActiveProgram') && isequal(x.ActiveProgram,1), R),1);
                        if isempty(ai), ai = 1; end
                        R = R(ai);
                    end
                    if isfield(R,'AmplitudeInMilliAmps'),     rAmplitude  = R.AmplitudeInMilliAmps; end
                    if isfield(R,'PulseWidthInMicroSecond'),  rPulseWidth = R.PulseWidthInMicroSecond; end
                    if isfield(R,'RateInHertz') && isnan(rateInHertz), rateInHertz = R.RateInHertz; end
                end
            end

            % Flat defaults (mirror if still empty)
            if isnan(lAmplitude) && isfield(PS,'AmplitudeInMilliAmps'),      lAmplitude  = PS.AmplitudeInMilliAmps; end
            if isnan(rAmplitude) && isfield(PS,'AmplitudeInMilliAmps'),      rAmplitude  = PS.AmplitudeInMilliAmps; end
            if isnan(lPulseWidth) && isfield(PS,'PulseWidthInMicroSecond'),  lPulseWidth = PS.PulseWidthInMicroSecond; end
            if isnan(rPulseWidth) && isfield(PS,'PulseWidthInMicroSecond'),  rPulseWidth = PS.PulseWidthInMicroSecond; end
            if isnan(rateInHertz) && isfield(PS,'RateInHertz'),              rateInHertz = PS.RateInHertz; end

            % Optional: SensingChannel fallback for rate, amp, pw (rare)
            if isfield(PS,'SensingChannel')
                sc = PS.SensingChannel;
                if isstruct(sc) && numel(sc) >= 1
                    if isfield(sc(1),'RateInHertz') && isnan(rateInHertz), rateInHertz = sc(1).RateInHertz; end
                    if isfield(sc(1),'SuspendAmplitudeInMilliAmps')
                        if isnan(lAmplitude) && isnan(rAmplitude)
                            lAmplitude = sc(1).SuspendAmplitudeInMilliAmps;
                            rAmplitude = sc(1).SuspendAmplitudeInMilliAmps;
                        end
                    end
                    if isfield(sc(1),'PulseWidthInMicroSecond') && isnan(lPulseWidth) && isnan(rPulseWidth)
                        lPulseWidth = sc(1).PulseWidthInMicroSecond;
                        rPulseWidth = sc(1).PulseWidthInMicroSecond;
                    end
                end
            end

            % Soft Start/Stop
            sss_status = false; sss_duration = NaN;
            if isfield(groupSettings,'SoftStartStop')
                sss = groupSettings.SoftStartStop;
                if isfield(sss,'Enabled'),           sss_status   = logical(sss.Enabled); end
                if isfield(sss,'DurationInSeconds'), sss_duration = sss.DurationInSeconds; end
            end

            % Cycling
            cycling_status = false; cycling_on = NaN; cycling_off = NaN;
            if isfield(groupSettings,'Cycling')
                cyc = groupSettings.Cycling;
                if isfield(cyc,'Enabled'),                   cycling_status = logical(cyc.Enabled); end
                if isfield(cyc,'OnDurationInMilliSeconds'),  cycling_on  = cyc.OnDurationInMilliSeconds/1e3; end
                if isfield(cyc,'OffDurationInMilliSeconds'), cycling_off = cyc.OffDurationInMilliSeconds/1e3; end
            end
        end
    end
    % -------------------------------------------------------------------------

    % --- Derived durations from hours (consistent with device counters) ---
    daysSinceImplant     = timeSinceTherapy  / 24;
    monthsSinceImplant   = daysSinceImplant  / 30.4375;   % Gregorian average month
    daysSinceFollowup    = timeSinceFollowup / 24;
    monthsSinceFollowup  = daysSinceFollowup / 30.4375;

    % ---- Build tidy row for this file ----
    rec = struct( ...
        'SubjectID',            string(subjectID{1}), ...
        'AcqLabel',             string(acqLabelOut), ...
        'NumFullMonths',        months, ...
        'RunLabel',             string(runLabelOut), ...
        'SessionDate',          jsonSessionDate, ...
        'ImplantDate',          implantDate_formatted, ...
        'HoursSinceImplant',    timeSinceTherapy, ...
        'DaysSinceImplant',     daysSinceImplant, ...
        'MonthsSinceImplant',   monthsSinceImplant, ...
        'HoursSinceFollowup',   timeSinceFollowup, ...
        'DaysSinceFollowup',    daysSinceFollowup, ...
        'MonthsSinceFollowup',  monthsSinceFollowup, ...
        'LeftAmplitude_mA',     lAmplitude, ...
        'RightAmplitude_mA',    rAmplitude, ...
        'LeftPulseWidth_us',    lPulseWidth, ...
        'RightPulseWidth_us',   rPulseWidth, ...
        'Rate_Hz',              rateInHertz, ...
        'SoftStartEnabled',     logical(sss_status), ...
        'SoftStartDuration_s',  sss_duration, ...
        'CyclingEnabled',       logical(cycling_status), ...
        'CyclingOn_s',          cycling_on, ...
        'CyclingOff_s',         cycling_off, ...
        'SourceFile',           string(fname) ...
    );

    % ---- Schema-safe append to rows (prevents "dissimilar structures") ----
    if isempty(rows)
        rows = rec;                              % first row defines the schema
    else
        f0 = fieldnames(rows);                   % existing schema
        f1 = fieldnames(rec);                    % new record fields

        % Add fields missing in rec (fill with [])
        missInRec = setdiff(f0, f1);
        for k = 1:numel(missInRec)
            rec.(missInRec{k}) = [];             % [] works for heterogeneous types
        end

        % Add fields missing in existing rows (fill [] for all prior elems)
        missInRows = setdiff(f1, f0);
        if ~isempty(missInRows)
            for k = 1:numel(missInRows)
                [rows.(missInRows{k})] = deal([]);
            end
            rows = orderfields(rows, rec);       % align order now that sets match
        end

        % Final order alignment & append
        rec  = orderfields(rec, rows);
        rows(end+1) = rec;                       %#ok<SAGROW>
    end

    % ---------- LFP Data Extraction (Survey only) ----------
    createdListBeforeSub  = dir(fullfile(params.save_pathname, '**', '*'));
    createdListBeforeRoot = dir(fullfile(outputPath, '*'));

    if ~(hasPSD || hasTD)
        fprintf('No BrainSense Survey fields found in %s.\n', fname);
        if hasStreamingTD || hasStreamingPower
            fprintf('Detected IndefiniteStreaming (continuous). Survey extractors will not run.\n');
        end
    else
        prev_cwd = pwd;
        if ~exist(params.save_pathname, 'dir'), mkdir(params.save_pathname); end
        cd(params.save_pathname);
        try
            if hasPSD
                params.recordingMode = 'LFPMontage';
                try, extractLFPMontage(data, params); catch ME, warning('extractLFPMontage failed: %s', ME.message); end
            end
            if hasTD
                params.recordingMode = 'LfpMontageTimeDomain';
                params.nChannels  = 6;
                params.channel_map = [1 2 3 ; 4 5 6];
                try, extractLFPMontageTD(data, params); catch ME, warning('extractLFPMontageTD failed: %s', ME.message); end
            end
            close all
        catch ME
            cd(prev_cwd); rethrow(ME);
        end
        cd(prev_cwd);

        % Consolidate stray outputs created directly under Result/
        createdListAfterRoot = dir(fullfile(outputPath, '*'));
        beforeNames = {createdListBeforeRoot.name};
        afterNames  = {createdListAfterRoot.name};
        newTopNames = setdiff(afterNames, beforeNames);
        denyList = {'subject_summary.xlsx','subject_summary_combined.xlsx','.','..'};

        for i = 1:numel(newTopNames)
            nm = newTopNames{i};
            if any(strcmpi(nm, denyList)), continue; end
            if startsWith(nm, 'sub-','IgnoreCase',true), continue; end
            src = fullfile(outputPath, nm);
            dst = fullfile(params.save_pathname, nm);
            if exist(dst, 'file') || exist(dst, 'dir')
                [p0, b0, e0] = fileparts(dst);
                dst = fullfile(p0, sprintf('%s_dupe%s', b0, e0));
            end
            try, movefile(src, dst); fprintf('Moved stray output "%s" into %s\n', nm, params.save_pathname);
            catch mErr, warning('Could not move "%s" to subject folder: %s', nm, mErr.message);
            end
        end
    end

    % ---------- Rename only outputs created for THIS acquisition ----------
    if ~isempty(params.sessionLabel)
        createdListAfterSub = dir(fullfile(params.save_pathname, '**', '*'));
        beforePaths = {};
        if ~isempty(createdListBeforeSub)
            beforePaths = fullfile({createdListBeforeSub.folder}, {createdListBeforeSub.name});
        end
        afterPaths  = fullfile({createdListAfterSub.folder},  {createdListAfterSub.name});
        newPaths    = setdiff(afterPaths, beforePaths);

        hasRun = ~strcmpi(params.runLabel,'') && ~strcmpi(params.runLabel,'run-NA');

        datePats = { ...
            '\d{8}T\d{6}Z', '\d{8}T\d{6}', '\d{8}_\d{6}', '\d{14}', '\d{8}', ...
            '\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}Z?', ...
            '\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}Z?', ...
            '\d{8}[-_]\d{2}[-_]\d{2}[-_]\d{2}' };

        subPrefix = ['sub-' params.subjectID];

        for i = 1:numel(newPaths)
            oldFull = newPaths{i};
            d = dir(oldFull);
            if isempty(d) || d.isdir, continue; end

            [oldFolder, oldName, oldExt] = fileparts(oldFull);
            newStem = oldName;
            newStem = regexprep(newStem, '[\s]+', '_');
            newStem = regexprep(newStem, '^sub-[^_]+_', '');
            subjEsc = regexptranslate('escape', params.subjectID);
            newStem = regexprep(newStem, ['^' subjEsc '[_-]+'], '');
            newStem = regexprep(newStem, '(?:^|[_-])acq-[A-Za-z0-9]+', '', 'once');
            newStem = regexprep(newStem, '(?:^|[_-])run-[A-Za-z0-9]+', '', 'once');
            while ~isempty(regexp(newStem, '(?:^|[_-])(acq|run)-[A-Za-z0-9]+', 'once'))
                newStem = regexprep(newStem, '(?:^|[_-])acq-[A-Za-z0-9]+', '');
                newStem = regexprep(newStem, '(?:^|[_-])run-[A-Za-z0-9]+', '');
            end
            for kp = 1:numel(datePats)
                tmp = regexprep(newStem, datePats{kp}, '', 'once');
                if ~strcmp(tmp, newStem), newStem = tmp; break; end
            end
            newStem = regexprep(newStem, '[_-]{2,}', '_');
            newStem = regexprep(newStem, '^_+|_+$', '');

            parts = {subPrefix};
            if ~isempty(newStem), parts{end+1} = newStem; end
            parts{end+1} = params.sessionLabel;
            if hasRun, parts{end+1} = params.runLabel; end

            newBase = strjoin(parts, '_');
            newBase = regexprep(newBase, '[_-]{2,}', '_');
            newName = [newBase oldExt];

            if strcmp([oldName oldExt], newName), continue; end

            newFull = fullfile(oldFolder, newName);
            try
                movefile(oldFull, newFull, 'f');
                fprintf('Renamed: "%s" -> "%s"\n', [oldName oldExt], newName);
            catch re
                warning('Could not rename "%s": %s', [oldName oldExt], re.message);
            end
        end
    end
end

% ---------- Write one tidy spreadsheet (one row per JSON/acq) ----------
if isempty(rows)
    warning('No rows collected. Nothing to write.');
else
    Tidy = struct2table(rows);
    % Column order to show in the sheet:
    order = {'SubjectID','AcqLabel','NumFullMonths','RunLabel','SessionDate','ImplantDate', ...
        'HoursSinceImplant','DaysSinceImplant','MonthsSinceImplant', ...
        'HoursSinceFollowup','DaysSinceFollowup','MonthsSinceFollowup', ...
        'LeftAmplitude_mA','RightAmplitude_mA', ...
        'LeftPulseWidth_us','RightPulseWidth_us','Rate_Hz', ...
        'SoftStartEnabled','SoftStartDuration_s', ...
        'CyclingEnabled','CyclingOn_s','CyclingOff_s', ...
        'SourceFile'};

    present = intersect(order, Tidy.Properties.VariableNames, 'stable');
    Tidy = Tidy(:, present);

    if ~exist(masterOutputPath,'dir'), mkdir(masterOutputPath); end
    outXLSX = fullfile(masterOutputPath, 'subject_summary_tidy.xlsx');
    outCSV  = fullfile(masterOutputPath, 'subject_summary_tidy.csv');

    writetable(Tidy, outXLSX);
    writetable(Tidy, outCSV);

    fprintf('Wrote tidy summary:\n  %s\n  %s\n', outXLSX, outCSV);
end