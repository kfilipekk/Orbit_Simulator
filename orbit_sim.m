classdef orbit_sim < handle
    properties (Access = private)
        UIFigure
    end

    methods (Access = public)
        function app = orbit_sim()
            app.UIFigure = uifigure('Name', 'Orbit Simulator (UKF)', ...
                                  'Position', [100 100 1200 800]);
        end
    end
end