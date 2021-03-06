classdef plotSpikesBurstStatisticsOptions < plotStatisticsOptions & baseOptions
% plotSpikesBurstStatisticsOptions # Plot fluorescence burst statistics
% Plots statistics associated to fluorescence (global) bursts: amplitude, duration, IBI
%   It can show a single box for each experimetn and group, or merge them together into a joint statistic. Change the groupingOrder for that.
%
%   Copyright (C) 2016-2018, Javier G. Orlandi <javiergorlandi@gmail.com>
%
%   See also plotSpikesBurstStatisticsOptions, plotStatisticsOptions, baseOptions, optionsWindow

  methods 
    function obj = setExperimentDefaults(obj, experiment)
      obj.statistic = {'IBI', 'IBI CV', 'bursting rate', 'bursting rate high', 'bursting rate low', 'duration', 'num spikes', 'num spikes per group member', 'ratio participating cells', 'num participating cells', 'burstiness', 'ask', ''};
      obj = setExperimentDefaults@plotStatisticsOptions(obj, experiment);
    end
  end
end
