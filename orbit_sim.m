classdef orbit_sim < handle
    properties (Access = private)
        %% GUI Handles
        UIFigure, GridLayout, ControlPanel, PlotTabGroup
        Ax3D
        
        h = struct()
        SimTimer, IsRunning = false
        Constants = struct('GM', 3.986004418e14, 'R_earth', 6378137.0);
        History, TimeState
    end

    methods (Access = public)
        function app = orbit_sim()
            app.UIFigure = uifigure('Name', 'Orbit Simulator (UKF)', 'Position', [50 50 1700 950]);
            app.GridLayout = uigridlayout(app.UIFigure, [1, 2], 'ColumnWidth', {280, '1x'});
            app.ControlPanel = uipanel(app.GridLayout, 'Title', 'Controls & Settings');
            app.PlotTabGroup = uitabgroup(app.GridLayout);
            
            orbitTab = uitab(app.PlotTabGroup, 'Title', 'Orbit Visualizations');
            app.Ax3D = uiaxes(orbitTab);
            title(app.Ax3D, '3D Orbit Trajectory (ECI)');
            
            uibutton(app.ControlPanel, 'push', 'Text', 'Reset', 'Position', [20 880 100 22], 'ButtonPushedFcn', @app.onReset);
            uibutton(app.ControlPanel, 'push', 'Text', 'Run/Pause', 'Position', [20 850 100 22], 'ButtonPushedFcn', @app.onRunPause);

            app.SimTimer = timer('ExecutionMode', 'fixedRate', 'Period', 0.1, 'TimerFcn', @(~,~) app.updateAnimation);
            
            app.onReset();
        end
    end

    methods (Access = private)
        function onReset(app, ~, ~)
            if ~isempty(app.SimTimer) && app.IsRunning
                stop(app.SimTimer);
                app.IsRunning = false;
            end
            app.initializeAndDrawOrbit();
        end
        
        function onRunPause(app, ~, ~)
            app.IsRunning = ~app.IsRunning;
            if app.IsRunning
                start(app.SimTimer);
            else
                stop(app.SimTimer);
            end
        end

        function initializeAndDrawOrbit(app)
            cla(app.Ax3D);
            
            %% 1. Draw the Earth
            [xE,yE,zE] = sphere(50);
            surf(app.Ax3D, xE*app.Constants.R_earth/1000, yE*app.Constants.R_earth/1000, zE*app.Constants.R_earth/1000, ...
                 'FaceColor', 'blue', 'EdgeColor', 'none', 'FaceAlpha', 0.7);
            hold(app.Ax3D, 'on'); grid(app.Ax3D, 'on'); axis(app.Ax3D, 'equal'); view(app.Ax3D, 3);

            %% 2. Define and calculate a simple LEO orbit
            a = app.Constants.R_earth + 420e3; e = 0.0003; i = deg2rad(51.6);
            [r0, v0] = orbit_sim.orb_elements_to_state(a, e, i, 0, 0, 0, app.Constants.GM);
            
            tspan = 0:10:95*60;
            ode_opts = odeset('RelTol', 1e-8, 'AbsTol', 1e-9);
            dynamics = @(t, y) [y(4:6); -app.Constants.GM * y(1:3) / (norm(y(1:3))^3)];
            [~, y_hist] = ode45(dynamics, tspan, [r0; v0], ode_opts);
            
            %% 3. Plot the trajectory
            plot3(app.Ax3D, y_hist(:,1)/1000, y_hist(:,2)/1000, y_hist(:,3)/1000, 'b-', 'LineWidth', 2);
            app.h.satellite = plot3(app.Ax3D, NaN, NaN, NaN, 'yo', 'MarkerFaceColor', 'y', 'MarkerSize', 10);
            xlabel(app.Ax3D, 'X (km)'); ylabel(app.Ax3D, 'Y (km)'); zlabel(app.Ax3D, 'Z (km)');
            
            app.History.y = y_hist'; 
            app.TimeState.k = 1;
            pos = app.History.y(1:3, 1);
            set(app.h.satellite, 'XData', pos(1)/1000, 'YData', pos(2)/1000, 'ZData', pos(3)/1000);
        end
        
        function updateAnimation(app)
            k = app.TimeState.k + 1;
            if k > size(app.History.y, 2), k = 1; end
            
            pos = app.History.y(1:3, k);
            set(app.h.satellite, 'XData', pos(1)/1000, 'YData', pos(2)/1000, 'ZData', pos(3)/1000);
            app.TimeState.k = k;
            drawnow;
        end
    end
    
    methods (Static)
        function [r_eci, v_eci] = orb_elements_to_state(a, e, i, RAAN, arg_p, TA, GM)
            p = a * (1 - e^2);
            r_norm = p / (1 + e * cos(TA));
            r_pqw = [r_norm * cos(TA); r_norm * sin(TA); 0];
            v_pqw = sqrt(GM/p) * [-sin(TA); e + cos(TA); 0];
            Rz_RAAN = [cos(RAAN) sin(RAAN) 0; -sin(RAAN) cos(RAAN) 0; 0 0 1];
            Rx_i = [1 0 0; 0 cos(i) sin(i); 0 -sin(i) cos(i)];
            Rz_argp = [cos(arg_p) sin(arg_p) 0; -sin(arg_p) cos(arg_p) 0; 0 0 1];
            R_pqw2eci = (Rz_RAAN * Rx_i * Rz_argp)';
            r_eci = R_pqw2eci * r_pqw;
            v_eci = R_pqw2eci * v_pqw;
        end
    end
end