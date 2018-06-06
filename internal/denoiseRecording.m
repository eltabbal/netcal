function experiment = denoiseRecording(experiment, varargin)
% DENOISERECORDING Uses PCA to remove noise from a recording
%
% USAGE:
%    experiment = denoiseRecording(experiment, varargin)
%
% INPUT arguments:
%    experiment - experiment structure
%
% INPUT optional arguments ('key' followed by its value):
%    see: denoiseRecordingOptions
%
%    training - true/false 
%
%    trainingBlock - Idx
%
% OUTPUT arguments:
%    experiment - experiment structure
%
% EXAMPLE:
%    experiment = denoiseRecording(experiment, varargin)
%
% Copyright (C) 2016-2017, Javier G. Orlandi <javierorlandi@javierorlandi.com>
%
% See also preprocessExperiment

% EXPERIMENT PIPELINE
% name: movie denoiser
% parentGroups: fluorescence: cellSort
% optionsClass: denoiseRecordingOptions
% requiredFields: handle
% producedFields: denoisedData

%--------------------------------------------------------------------------
[params, var] = processFunctionStartup(denoiseRecordingOptions, varargin{:});
% Define additional optional argument pairs
params.pbar = [];
params.training = false;
params.trainingBlock = [];
% Parse them
params = parse_pv_pairs(params, var);
params = barStartup(params, 'Running denoiser');
%--------------------------------------------------------------------------

denoisedData = [];
tabulatedValues = 0.05:0.05:1; % These come from https://arxiv.org/abs/1305.5870
tabulatedCts = [1.5066 1.5816  1.6466  1.7048 1.7580 1.8074 1.8537 1.8974 1.9389 1.9786 2.0167 2.0533 2.0887 2.1229 2.1561 2.1883 2.2197 2.2503 2.2802 2.3094];
blockSize = params.blockSize;
readSmallBlocks = params.readSmallBlocks;
frameBlockSize = params.frameBlockSize;

switch params.movie
  case 'glia'
    numFrames = length(experiment.gliaAverageT);
    width = size(experiment.gliaAverageFrame, 2);
    height = size(experiment.gliaAverageFrame, 2);
  otherwise
    numFrames = experiment.numFrames;
    width = experiment.width;
    height = experiment.height;
end

frameBlockList = 1:frameBlockSize:numFrames;
if(frameBlockList(end) < numFrames-frameBlockSize/2)
  frameBlockList = [frameBlockList, numFrames+1];
else
  frameBlockList(end) = numFrames+1;
end
if(length(frameBlockList) == 1)
  frameBlockList = [1 numFrames+1];
end
% Only run the first block in training
if(params.training)
  frameBlockList = frameBlockList(1:2);
end

currentBlock = 0;

% Let's generate the block positions
numRowBlocks = ceil((height-params.blockSize(1))/(params.blockSize(1)-params.blockOverlap(1)))+1;
numColBlocks = ceil((width-params.blockSize(2))/(params.blockSize(2)-params.blockOverlap(2)))+1;
blockRowCoordinates = 1+((1:numRowBlocks)-1)*(params.blockSize(1)-params.blockOverlap(1));
blockColCoordinates = 1+((1:numColBlocks)-1)*(params.blockSize(2)-params.blockOverlap(2));
Nblocks = numRowBlocks*numColBlocks*(length(frameBlockList)-1);

% Generate the normalization mask
mask = zeros(height, width);
for blockIt2 = 1:length(blockColCoordinates)
  for blockIt1 = 1:length(blockRowCoordinates)
    idx1 = blockRowCoordinates(blockIt1);
    idx2 = blockColCoordinates(blockIt2);
    idx1Last = min(idx1+blockSize(1)-1, height);
    idx2Last = min(idx2+blockSize(2)-1, width);
    mask(idx1:idx1Last, idx2:idx2Last) = mask(idx1:idx1Last, idx2:idx2Last)+1;
  end
end
mask = 1./mask;

% Check if the frames would fit in memory
if(~params.training)
  try
    if(params.frameBlockAverageSize > 1)
      frameData = zeros(height, width, ceil(length(frameBlockList(1):(frameBlockList(2)-1))/params.frameBlockAverageSize));
    else
      frameData = zeros(height, width, length(frameBlockList(1):frameBlockList(2))-1);
    end
  catch
    logMsg('Full frames per block do not fit in memory. Doing partial runs');
    frameData = [];
  end
else
  frameData = [];
end

for t = 1:(length(frameBlockList)-1)
  firstFrame = frameBlockList(t);
  lastFrame = frameBlockList(t+1)-1;
  % If the frames fit in memory, store them here
  if(~isempty(frameData))
    if(params.frameBlockAverageSize > 1)
      frameList = firstFrame:params.frameBlockAverageSize:lastFrame;
      Nframes = length(frameList);
      frameData = zeros(height, width, Nframes);
    else
      Nframes = length(firstFrame:lastFrame);
      frameData = zeros(height, width, Nframes);
    end
    switch params.movie
      case 'glia'
        fID = fopen([experiment.folder 'data' filesep experiment.name '_gliaAverageMovieDataFile.dat'], 'r');
        fseek(fID, 0, 'bof'); % Just in case
        fseek(fID, prod(width*height)*8*(firstFrame-1), 'bof'); % the 8 refers to BYTES . Get to the first frame of the block
      otherwise
      [fID, experiment] = openVideoStream(experiment);
    end
    if(params.training)
      ncbar.setBarTitle('Getting frames');
    elseif(params.pbar > 0)
      ncbar.setBarTitle('Running denoiser. Getting frames');
    end
    if(params.frameBlockAverageSize > 1)
      frameList = firstFrame:params.frameBlockAverageSize:lastFrame;
      Nframes = length(frameList);
      for it1 = 1:Nframes
        %[blockIt2 blockIt1 it1]
        frameData(:, :, it1) = mean(getFrameBlock(experiment, frameList(it1), fID, params.frameBlockAverageSize),3);
      end
    else
      for it1 = 1:Nframes
        switch params.movie
          case 'glia'
            %fseek(fID, prod(width*height)*8*(it1-1), 'bof'); % the 8 refers to BYTES
            tmpData = fread(fID, [height width], 'double'); % Sequential read
            frameData(:, :, it1) = tmpData;
          otherwise
            frameData(:, :, it1) = getFrame(experiment, firstFrame+it1-1, fID);
        end
      end
    end
    switch params.movie
      case 'glia'
        fclose(fID);
      otherwise
        closeVideoStream(fID);
    end
    % For some reason getting the data like this needs another tranpose
    frameData = permute(frameData, [2 1 3]);
  end
  for blockIt2 = 1:length(blockColCoordinates)
    for blockIt1 = 1:length(blockRowCoordinates)
      currentBlock = currentBlock + 1;
      if(params.training)
        if(currentBlock ~= params.trainingBlock)
          continue;
        end
      end
      BID1 = blockIt1;
      BID2 = blockIt2;

      idx1 = blockRowCoordinates(blockIt1);
      idx2 = blockColCoordinates(blockIt2);
      idx1Last = min(idx1+blockSize(1)-1, height);
      idx2Last = min(idx2+blockSize(2)-1, width);
      data = zeros(height, width);
      data(idx1:idx1Last, idx2:idx2Last) = 1;
      valid = find(data);
      if(isempty(frameData))
        % Create a list of contigous frames to recover
        if(readSmallBlocks)
          jumps = [0; find(diff(valid) > 1); length(valid)];
          pixelList = [jumps(1:end-1)+1, jumps(2:end)];
        end

        switch params.movie
          case 'glia'
            fID = fopen([experiment.folder 'data' filesep experiment.name '_gliaAverageMovieDataFile.dat'], 'r');
            fseek(fID, 0, 'bof'); % Just in case
            fseek(fID, prod(width*height)*8*(firstFrame-1), 'bof'); % the 8 refers to BYTES . Get to the first frame of the block
          otherwise
          [fID, experiment] = openVideoStream(experiment);
        end
        if(params.training)
          ncbar.setBarTitle('Getting frames');
        elseif(params.pbar > 0)
          ncbar.setBarTitle('Running denoiser. Getting frames');
        end
        if(params.frameBlockAverageSize > 1)
          frameList = firstFrame:params.frameBlockAverageSize:lastFrame;
          Nframes = length(frameList);
          fullData = zeros(length(valid), Nframes);
          for it1 = 1:Nframes
            %[blockIt2 blockIt1 it1]
            fullData(:, it1) = mean(getFrameBlock(experiment, frameList(it1), fID, params.frameBlockAverageSize, valid),2);
          end
        else
          Nframes = length(firstFrame:lastFrame);
          fullData = zeros(length(valid), Nframes);
          for it1 = 1:Nframes
            % For each block of contiguous pixels - turns out it is faster to pull
            % the whole frames
            if(readSmallBlocks)
              for it2 = 1:size(pixelList, 1)
                curPixels = pixelList(it2, 1):pixelList(it2, 2);
                switch params.movie
                  case 'glia'
                    %fseek(fID, prod(width*height)*8*(it1-1), 'bof'); % the 8 refers to BYTES
                    tmpData = fread(fID, [height width], 'double'); % Sequential read
                    fullData(curPixels, it1) = tmpData(valid(curPixels));
                  otherwise
                    fullData(curPixels, it1) = getFrame(experiment, firstFrame+it1-1, fID, valid(curPixels));
                end
              end
            else
              switch params.movie
                case 'glia'
                  %fseek(fID, prod(width*height)*8*(it1-1), 'bof'); % the 8 refers to BYTES
                  tmpData = fread(fID, [height width], 'double'); % Sequential read
                  fullData(:, it1) = tmpData(valid);
                otherwise
                  fullData(:, it1) = getFrame(experiment, firstFrame+it1-1, fID, valid);
              end
            end
            if(params.training)
              ncbar.update(it1/Nframes);
            end
          end
        end
        switch params.movie
          case 'glia'
            fclose(fID);
          otherwise
            closeVideoStream(fID);
        end
      else
        fullData = frameData(idx1:idx1Last, idx2:idx2Last, :);
        fullData = reshape(fullData, [length(valid), size(fullData, 3)]);
      end
      % Now the PCA
      fullData = permute(fullData, [2 1]); % We want frames as observations, pixels as variables
      if(params.training)
        ncbar.setBarTitle('Computing PCA');
        ncbar.setAutomaticBar();
      elseif(params.pbar > 0)
        ncbar.setBarTitle('Running denoiser. Computing PCA');
      end
      %[coeff, score, latent, tsquared, explained, mu] = pca(fullData); % Here we go
      [U, S, V] = svdecon(fullData); % Using fast SVD instead
      mu = mean(fullData, 1);
      score = U*S;
      latent = diag(S)/sum(diag(S));
      coeff = V;
      
      ct = interp1(tabulatedValues, tabulatedCts, size(fullData,1)/size(fullData,2), 'pchip');
      largestComponent = find(latent <= mean(latent)*ct, 1, 'first');
      % Apply the multiplier
      if(~isempty(params.maximumPCsMultiplier) && params.maximumPCsMultiplier > 0)
        largestComponent = round(largestComponent*params.maximumPCsMultiplier);
      else
        largestComponent = length(latent);
      end
      % Consistency checks
      if(largestComponent > length(latent))
        largestComponent = length(latent);
      elseif(largestComponent < 1)
        largestComponent = 1;
      end
       
      Ncom = largestComponent;
      
      coeff = coeff(:, 1:Ncom);
      score = score(:, 1:Ncom);
      fullLatent = latent;
      latent = latent(1:Ncom);
      % Let's store the PCA scores also
      coeffPCA = coeff;
      scorePCA = score;
      if(params.training)
        ncbar.setCurrentBarName('Computing ICA');
      elseif(params.pbar > 0)
        ncbar.setBarTitle('Running denoiser. Computing ICA');
      end
      [icasig, A, W] = fastica(score*coeff', 'verbose', 'off');

      coeff = icasig';
      score = A;
      
      % Sort components based on spatial skewness
      skewS = zeros(Ncom, 1);
      for it = 1:Ncom
        selComponent = it;
        skewS(it) = skewness(mean(score(:, selComponent)*coeff(:, selComponent)'));
        %skewT(it) = skewness(mean(score(:, selComponent)*coeff(:, selComponent)', 2));
      end
      [~, idx] = sort(skewS, 'descend');
      score = score(:, idx);
      coeff = coeff(:, idx);

      if(params.training)
        ncbar.unsetAutomaticBar();
      end

      denoisedBlock = struct;
      % If training, return all components
      if(~params.training)
        denoisedBlock.Ncomponents = largestComponent;
      else
        denoisedBlock.Ncomponents = length(latent);
      end
      denoisedBlock.largestComponent = largestComponent;
      denoisedBlock.block = [BID1, BID2];
      denoisedBlock.blockCoordinates = [idx1, idx2];
      denoisedBlock.blockCoordinatesLast = [idx1Last, idx2Last];
      denoisedBlock.blockSize = denoisedBlock.blockCoordinatesLast-denoisedBlock.blockCoordinates+1;
      data = zeros(height, width);
      data(idx1:idx1Last, idx2:idx2Last) = 1;
      denoisedBlock.pixelList = find(data);
      denoisedBlock.latent = latent;
      denoisedBlock.fullLatent = fullLatent;
      denoisedBlock.score = score(:, 1:denoisedBlock.Ncomponents);
      denoisedBlock.coeff = coeff(:, 1:denoisedBlock.Ncomponents);
      denoisedBlock.means = mu*0; % Hack for ICA
      denoisedBlock.frames = [firstFrame, lastFrame];
      if(params.frameBlockAverageSize > 1)
        denoisedBlock.frameList = ceil((1:(lastFrame-firstFrame+1))/params.frameBlockAverageSize);
      end
      denoisedBlock.coeffPCA = coeffPCA;
      denoisedBlock.scorePCA = scorePCA;
      denoisedBlock.meansPCA = mu;
      denoisedBlock.mask = mask;
      % Looks like its always needed
      if(strcmp(experiment.extension, '.his'))
        denoisedBlock.needsTranspose = true;
      else
        denoisedBlock.needsTranspose = false;
      end

      denoisedData = [denoisedData, denoisedBlock];
      if(~params.training && params.pbar > 0)
        ncbar.update(currentBlock/Nblocks);
      end
    end
  end
end

if(~params.training)
  switch params.movie
    case 'glia'
      experiment.denoisedDataGlia = denoisedData;
    otherwise
      experiment.denoisedData = denoisedData;
  end
  experiment.saveBigFields = true; % So the traces are saved
else
  experiment.denoisedDataTraining = denoisedData;
end

%--------------------------------------------------------------------------
barCleanup(params);
%--------------------------------------------------------------------------
