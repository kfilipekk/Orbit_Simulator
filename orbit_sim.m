classdef orbit_sim < handle

    properties (Access = private)
        UIFigure, GridLayout, ControlPanel, PlotTabGroup
        Ax3D, AxGroundTrack, AxErrors, AxCd, AxSkyPlot, AxForceAnalysis
        
        RunPauseButton, ExportButton
        OrbitDropdown, J2Checkbox, J3J4Checkbox, DragCheckbox, ThirdBodyCheckbox, SRPCheckbox
        SpeedSlider, SpeedLabel, NoiseSlider, NoiseLabel, F107Slider, F107Label
        StatusLabel, TimeLabel, StationLabel
        h = struct() 
        SimTimer, IsRunning = false
        Constants, TimeState, Satellite, Stations, UKF, History, Perturbations
    end
    
    methods (Access = public)
        function app = orbit_sim()
            app.createComponents();
            app.resetSimulation();
            app.UIFigure.UserData = app;
        end
        
        function delete(app)
            if ~isempty(app.SimTimer) && isvalid(app.SimTimer)
                stop(app.SimTimer);
                delete(app.SimTimer);
            end
            
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end
    end
    
    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure('Name', 'Orbit simulator (UKF)', ...
                                  'Position', [50 50 1700 950], ...
                                  'CloseRequestFcn', @(src, event) delete(app));
                                  
            app.GridLayout = uigridlayout(app.UIFigure, [10, 8], 'RowHeight', {30, '1x', '1x', '1x', '1x', '1x', '1x', '1x', '1x', 30}, 'ColumnWidth', {280, '1x', '1x', '1x', '1x', '1x', '1x', '1x'});
            
            app.ControlPanel = uipanel(app.GridLayout, 'Title', 'Controls & Settings');
            app.ControlPanel.Layout.Row = [1 10]; app.ControlPanel.Layout.Column = 1;
            cpGrid = uigridlayout(app.ControlPanel, [5, 1], 'RowHeight', {'fit', 'fit', 'fit', 'fit', '1x'});

            %% Main Control Buttons
            mainGrid = uigridlayout(cpGrid, [1, 3]);
            app.RunPauseButton = uibutton(mainGrid, 'push', 'Text', 'Run', 'ButtonPushedFcn', @app.onRunPause);
            uibutton(mainGrid, 'push', 'Text', 'Reset', 'ButtonPushedFcn', @app.onReset);
            app.ExportButton = uibutton(mainGrid, 'push', 'Text', 'Export to MAT', 'ButtonPushedFcn', @app.onExport, 'Enable', 'off');
            settingsPanel = uipanel(cpGrid, 'Title', 'General Settings');
            settingsGrid = uigridlayout(settingsPanel, [4, 3], 'ColumnWidth', {'fit', '1x', 50});
            uilabel(settingsGrid, 'Text', 'Orbit Type:');
            app.OrbitDropdown = uidropdown(settingsGrid, 'Items', {'LEO (ISS-like)', 'MEO (GPS-like)', 'HEO (Tundra)', 'GEO'});
            app.OrbitDropdown.Layout.Column = [2 3];
            uilabel(settingsGrid, 'Text', 'Sim Speed:');
            app.SpeedSlider = uislider(settingsGrid, 'Limits', [1, 50], 'Value', 1, 'ValueChangingFcn', @app.onSpeedChange);
            app.SpeedLabel = uilabel(settingsGrid, 'Text', '1x');
            uilabel(settingsGrid, 'Text', 'Meas. Noise (m):');
            app.NoiseSlider = uislider(settingsGrid, 'Limits', [0, 100], 'Value', 10, 'ValueChangingFcn', @app.onNoiseChange);
            app.NoiseLabel = uilabel(settingsGrid, 'Text', '10 m');
            
            %% Perturbation Controls Panel
            pertPanel = uipanel(cpGrid, 'Title', 'Perturbation Selection');
            pertGrid = uigridlayout(pertPanel, [3, 2]);
            app.J2Checkbox = uicheckbox(pertGrid, 'Text', 'J2', 'Value', 1);
            app.J3J4Checkbox = uicheckbox(pertGrid, 'Text', 'J3 & J4', 'Value', 1);
            app.DragCheckbox = uicheckbox(pertGrid, 'Text', 'Atmospheric Drag', 'Value', 1);
            app.ThirdBodyCheckbox = uicheckbox(pertGrid, 'Text', 'Sun/Moon Gravity', 'Value', 1);
            app.SRPCheckbox = uicheckbox(pertGrid, 'Text', 'Solar Radiation', 'Value', 1);
            weatherPanel = uipanel(cpGrid, 'Title', 'Space Weather');
            weatherGrid = uigridlayout(weatherPanel, [1, 3], 'ColumnWidth', {'fit', '1x', 50});
            uilabel(weatherGrid, 'Text', 'F10.7 Solar Flux:');
            app.F107Slider = uislider(weatherGrid, 'Limits', [70, 250], 'Value', 150, 'ValueChangingFcn', @(s,e) set(app.F107Label, 'Text', sprintf('%.0f', e.Value)));
            app.F107Label = uilabel(weatherGrid, 'Text', '150');
            
            app.PlotTabGroup = uitabgroup(app.GridLayout);
            app.PlotTabGroup.Layout.Row = [1 9]; app.PlotTabGroup.Layout.Column = [2 8];
            orbitTab = uitab(app.PlotTabGroup, 'Title', 'Orbit Visualizations');
            orbitGrid = uigridlayout(orbitTab, [2, 2]);
            filterTab = uitab(app.PlotTabGroup, 'Title', 'Filter Performance');
            filterGrid = uigridlayout(filterTab, [2, 2]);
            forceTab = uitab(app.PlotTabGroup, 'Title', 'Force Analysis');
            
            app.Ax3D = uiaxes(orbitGrid); app.Ax3D.Layout.Row = [1 2]; title(app.Ax3D, '3D Orbit Trajectory (ECI)');
            app.AxGroundTrack = uiaxes(orbitGrid); title(app.AxGroundTrack, 'Ground Track');
            app.AxSkyPlot = uiaxes(orbitGrid); title(app.AxSkyPlot, 'Sky Plot');
            app.AxErrors = uiaxes(filterGrid); title(app.AxErrors, 'UKF Position Error');
            app.AxCd = uiaxes(filterGrid); title(app.AxCd, 'Drag Coefficient (Cd) Estimation');
            app.AxForceAnalysis = uiaxes(forceTab); title(app.AxForceAnalysis, 'Acceleration Magnitudes');
            
            statusGrid = uigridlayout(app.GridLayout, [1,3], 'ColumnWidth', {'1x', '2x', '1x'});
            statusGrid.Layout.Row = 9; statusGrid.Layout.Column = [2 8];
            app.StatusLabel = uilabel(statusGrid, 'Text', 'Status: Ready', 'FontWeight', 'bold');
            app.TimeLabel = uilabel(statusGrid, 'Text', 'T: +0.00 hours', 'HorizontalAlignment', 'center');
            app.StationLabel = uilabel(statusGrid, 'Text', 'Tracking: None', 'HorizontalAlignment', 'right');
        end
        function initializeSimulationState(app)
            %% Constants
            app.Constants.GM = 3.986004418e14; app.Constants.R_earth = 6378137.0;
            app.Constants.omega_earth = 7.2921150e-5; app.Constants.J2 = 1.08263e-3;
            app.Constants.J3 = -2.5327e-6; app.Constants.J4 = -1.6196e-6;
            app.Constants.GM_sun = 1.32712440018e20; app.Constants.GM_moon = 4.9048695e12;
            app.Constants.P_srp = 4.56e-6;

            app.TimeState.t = 0; app.TimeState.dt_major = 60;
            app.TimeState.t_end = 24 * 3600;
            app.TimeState.time_vector = app.TimeState.t:app.TimeState.dt_major:app.TimeState.t_end;
            app.TimeState.k = 1;
            
            %% Satellite
            orbitType = app.OrbitDropdown.Value;
            switch orbitType
                case 'LEO (ISS-like)', a = app.Constants.R_earth + 420e3; e = 0.0003; i = deg2rad(51.6);
                case 'MEO (GPS-like)', a = app.Constants.R_earth + 20200e3; e = 0.005; i = deg2rad(55);
                case 'HEO (Tundra)',   a = 42164e3; e = 0.28; i = deg2rad(63.4);
                case 'GEO',            a = 42164e3; e = 0.001; i = deg2rad(0.5);
            end
            [r0, v0] = orbit_sim.orb_elements_to_state(a, e, i, deg2rad(20), deg2rad(270), 0, app.Constants.GM);
            app.Satellite.true_Cd = 2.2; app.Satellite.area_srp = 1.5; app.Satellite.area_drag = 1.0;
            app.Satellite.mass = 500; app.Satellite.Cr = 1.2;
            
            %% UKF State
            app.UKF.x_true = [r0; v0; app.Satellite.true_Cd];
            error_pos = [1000; -1500; 800]; error_vel = [10; -5; 3]; error_Cd = 0.5;
            app.UKF.x_est = app.UKF.x_true + [error_pos; error_vel; error_Cd];
            app.UKF.P = diag([1e7, 1e7, 1e7, 1e4, 1e4, 1e4, 1.0]);
            app.UKF.Q = diag([1e-7, 1e-7, 1e-7, 1e-10]);
            app.UKF.R = diag([deg2rad(0.01)^2, deg2rad(0.01)^2, app.NoiseSlider.Value^2]);
            app.UKF.n = 7; app.UKF.alpha = 1e-3; app.UKF.beta = 2; app.UKF.kappa = 0;
            
            %% Stations
            stations(1) = struct('name', 'Cambridge (MRAO)', 'lat', deg2rad(52.167), 'lon', deg2rad(0.039), 'alt', 15);
            stations(2) = struct('name', 'Goldstone', 'lat', deg2rad(35.42), 'lon', deg2rad(-116.89), 'alt', 1034);
            stations(3) = struct('name', 'Canberra', 'lat', deg2rad(-35.40), 'lon', deg2rad(148.98), 'alt', 683);
            for idx=1:length(stations), stations(idx).r_ecef = orbit_sim.lla2ecef(stations(idx).lat, stations(idx).lon, stations(idx).alt, app.Constants.R_earth); end
            app.Stations = stations; app.Satellite.min_elevation = deg2rad(7);
            
            %% History
            num_steps = length(app.TimeState.time_vector);
            app.History.x_true = nan(7, num_steps); app.History.x_est = nan(7, num_steps);
            app.History.P_diag = nan(7, num_steps); app.History.force_mags = nan(6, num_steps);
            app.History.x_true(:,1) = app.UKF.x_true; app.History.x_est(:,1) = app.UKF.x_est;
            app.History.P_diag(:,1) = diag(app.UKF.P);
        end

        function initializePlots(app)
            allAxes = [app.Ax3D, app.AxGroundTrack, app.AxSkyPlot, app.AxErrors, app.AxCd, app.AxForceAnalysis];
            for ax = allAxes, cla(ax); hold(ax, 'on'); grid(ax, 'on'); end
            
            %% Draw Earth
            axis(app.Ax3D, 'equal'); view(app.Ax3D, 3);
            [xE,yE,zE] = sphere(50);
            app.h.earth = surf(app.Ax3D, xE*app.Constants.R_earth/1000, yE*app.Constants.R_earth/1000, zE*app.Constants.R_earth/1000, 'FaceColor', 'blue', 'EdgeColor', 'none', 'FaceAlpha', 0.7);

            %% Plot true + estimated orbits
            app.h.true_orbit = plot3(app.Ax3D, NaN, NaN, NaN, 'b-', 'LineWidth', 2);
            app.h.est_orbit = plot3(app.Ax3D, NaN, NaN, NaN, 'r--', 'LineWidth', 1.5);
            app.h.satellite = plot3(app.Ax3D, NaN, NaN, NaN, 'yo', 'MarkerFaceColor', 'y', 'MarkerSize', 10);
            for i=1:length(app.Stations), app.h.stations(i) = plot3(app.Ax3D, NaN, NaN, NaN, 'go', 'MarkerFaceColor', 'g', 'MarkerSize', 8); end
            xlabel(app.Ax3D, 'X (km)'); ylabel(app.Ax3D, 'Y (km)'); zlabel(app.Ax3D, 'Z (km)');
            
            %% Ground Track
            coast_data = load('coastlines.mat'); plot(app.AxGroundTrack, coast_data.coastlon, coast_data.coastlat, 'k');
            app.h.ground_track = plot(app.AxGroundTrack, NaN, NaN, 'm-', 'LineWidth', 2);
            axis(app.AxGroundTrack, [-180 180 -90 90]); xlabel(app.AxGroundTrack, 'Longitude (deg)'); ylabel(app.AxGroundTrack, 'Latitude (deg)');

            %% Force Analysis
            set(app.AxForceAnalysis, 'YScale', 'log');
            force_names = {'2-Body', 'J2-J4', 'Drag', 'Lunar', 'Solar', 'SRP'};
            colors = lines(6);
            for i=1:6, app.h.forces(i) = plot(app.AxForceAnalysis, NaN, NaN, 'LineWidth', 2, 'Color', colors(i,:), 'DisplayName', force_names{i}); end
            legend(app.AxForceAnalysis); xlabel(app.AxForceAnalysis, 'Time (hours)'); ylabel(app.AxForceAnalysis, 'Acceleration (m/s^2)');
            
            %% Other Plots
            app.h.pos_error = plot(app.AxErrors, NaN, NaN, 'k', 'LineWidth', 2); app.h.pos_sigma = plot(app.AxErrors, NaN, NaN, 'r--');
            legend(app.AxErrors, 'Position Error Norm', '3\sigma Bound'); xlabel(app.AxErrors, 'Time (hours)'); ylabel(app.AxErrors, 'Position Error (m)');
            app.h.cd_est = plot(app.AxCd, NaN, NaN, 'b', 'LineWidth', 2); app.h.cd_sigma = fill(app.AxCd, NaN, NaN, 'r', 'FaceAlpha', 0.2, 'EdgeColor', 'none');
            app.h.cd_true = yline(app.AxCd, app.Satellite.true_Cd, 'k--', 'True Cd');
            legend(app.AxCd, 'Estimated Cd', '3\sigma Bound'); xlabel(app.AxCd, 'Time (hours)'); ylabel(app.AxCd, 'Cd');
            
            orbit_sim.createManualSkyPlotBackground(app.AxSkyPlot);
        end
        
        %% Callback Functions
        function onRunPause(app, ~, ~)
            app.IsRunning = ~app.IsRunning;
            if app.IsRunning
                app.RunPauseButton.Text = 'Pause';
                start(app.SimTimer);
            else
                app.RunPauseButton.Text = 'Run';
                stop(app.SimTimer);
            end
        end
        
        function onReset(app, ~, ~)
            app.resetSimulation();
        end
        
        function onExport(app, ~, ~)
            [file, path] = uiputfile('*.mat', 'Save Simulation Data');
            if isequal(file,0), return; end
            data.History = app.History;
            data.TimeState = app.TimeState;
            data.Constants = app.Constants;
            save(fullfile(path, file), '-struct', 'data');
            app.StatusLabel.Text = ['Status: Data exported to ' file];
        end
        
        function onSpeedChange(app, ~, event)
            newSpeed = event.Value;
            app.SpeedLabel.Text = sprintf('%dx', round(newSpeed));
            if ~isempty(app.SimTimer)
                stop(app.SimTimer);
                app.SimTimer.Period = 1/newSpeed;
                if app.IsRunning
                    start(app.SimTimer);
                end
            end
        end
        
        function onNoiseChange(app, ~, event)
            newNoise = event.Value;
            app.NoiseLabel.Text = sprintf('%d m', round(newNoise));
            app.UKF.R(3,3) = newNoise^2;
        end
        
        function resetSimulation(app)
            if ~isempty(app.SimTimer), stop(app.SimTimer); delete(app.SimTimer); end
            app.IsRunning = false;
            app.initializeSimulationState();
            app.initializePlots();
            app.updatePlots(true, 0);
            app.RunPauseButton.Text = 'Run'; app.StatusLabel.Text = 'Status: Ready';
            app.ExportButton.Enable = 'off';
            period = 1 / app.SpeedSlider.Value;
            app.SimTimer = timer('ExecutionMode', 'fixedRate', 'Period', period, 'TimerFcn', @(~,~) app.simulationStep, 'StopFcn', @(~,~) app.onTimerStop);
        end
        
        function onTimerStop(app)
            if app.TimeState.t >= app.TimeState.t_end
                app.StatusLabel.Text = 'Status: Simulation Finished.';
                app.RunPauseButton.Text = 'Run';
                app.IsRunning = false;
                app.ExportButton.Enable = 'on';
            else
                app.StatusLabel.Text = 'Status: Paused.';
            end
        end

        %% Main Simulation Logic
        function simulationStep(app)
            if app.TimeState.t >= app.TimeState.t_end, stop(app.SimTimer); return; end
            
            app.TimeState.k = app.TimeState.k + 1;
            t_start = app.TimeState.t;
            t_end = app.TimeState.time_vector(app.TimeState.k);
            app.TimeState.t = t_end;
            
            app.Perturbations.J2 = app.J2Checkbox.Value; app.Perturbations.J3J4 = app.J3J4Checkbox.Value;
            app.Perturbations.Drag = app.DragCheckbox.Value; app.Perturbations.ThirdBody = app.ThirdBodyCheckbox.Value;
            app.Perturbations.SRP = app.SRPCheckbox.Value;
            app.Perturbations.F107 = app.F107Slider.Value;

            ode_opts = odeset('RelTol', 1e-9, 'AbsTol', 1e-10);
            
            dynamics_handle = @(t, x) orbit_sim.dynamics_wrapper(t, x, app.Constants, app.Satellite, app.Perturbations);
            
            [~, y_true] = ode45(dynamics_handle, [t_start, t_end], app.UKF.x_true, ode_opts);
            app.UKF.x_true = y_true(end, :)';
            
            [x_pred, P_pred] = app.ukf_predict(app.UKF.x_est, app.UKF.P, dynamics_handle, [t_start, t_end], app.UKF.Q, ode_opts);
            
            station_in_view_idx = 0;
            station_in_view_name = 'None';
            for i = 1:length(app.Stations)
                [az, el, rho] = orbit_sim.ecef2aer(app.UKF.x_true(1:3), t_end, app.Stations(i), app.Constants);
                if el > app.Satellite.min_elevation
                    station_in_view_idx = i;
                    station_in_view_name = app.Stations(i).name;
                    z_true = orbit_sim.measurement_model(app.UKF.x_true(1:3), t_end, app.Stations(i), app.Constants);
                    z_meas = z_true + sqrt(diag(app.UKF.R)) .* randn(3, 1);
                    [app.UKF.x_est, app.UKF.P] = app.ukf_update(x_pred, P_pred, z_meas, app.Stations(i), t_end, app.UKF.R);
                    break;
                end
            end
            if station_in_view_idx == 0, app.UKF.x_est = x_pred; app.UKF.P = P_pred; end
            
            app.History.x_true(:, app.TimeState.k) = app.UKF.x_true;
            app.History.x_est(:, app.TimeState.k) = app.UKF.x_est;
            app.History.P_diag(:, app.TimeState.k) = diag(app.UKF.P);
            [~, forces] = dynamics_handle(t_end, app.UKF.x_true);
            app.History.force_mags(:, app.TimeState.k) = forces;

            app.updatePlots(false, station_in_view_idx);
            app.StatusLabel.Text = 'Status: Running...';
            app.StationLabel.Text = ['Tracking: ' station_in_view_name];
        end
        
        function [x_pred, P_pred] = ukf_predict(app, x_est, P_est, dynamics, tspan, Q, ode_opts)
            [lambda, Wm, Wc] = orbit_sim.get_ukf_params(app.UKF.n, app.UKF.alpha, app.UKF.beta, app.UKF.kappa);
            Xi = orbit_sim.generate_sigma_points(x_est, P_est, lambda);
            
            Yi = zeros(size(Xi));
            for i = 1:size(Xi, 2)
                [~, y_i] = ode45(dynamics, tspan, Xi(:,i), ode_opts);
                Yi(:,i) = y_i(end,:)';
            end
            
            x_pred = Yi * Wm;
            P_pred = zeros(app.UKF.n);
            for i = 1:size(Yi, 2)
                P_pred = P_pred + Wc(i) * (Yi(:,i) - x_pred) * (Yi(:,i) - x_pred)';
            end
            
            Gamma = [zeros(3,4); eye(4)];
            P_pred = P_pred + Gamma*Q*Gamma' * (tspan(2)-tspan(1));
        end

        function [x_new, P_new] = ukf_update(app, x_pred, P_pred, z_meas, station, t, R)
            [lambda, Wm, Wc] = orbit_sim.get_ukf_params(app.UKF.n, app.UKF.alpha, app.UKF.beta, app.UKF.kappa);
            Xi = orbit_sim.generate_sigma_points(x_pred, P_pred, lambda);
            
            Zi = zeros(3, size(Xi, 2));
            for i = 1:size(Xi, 2)
                Zi(:,i) = orbit_sim.measurement_model(Xi(1:3,i), t, station, app.Constants);
            end
            
            z_pred = Zi * Wm;
            
            Pzz = zeros(3); Pxz = zeros(app.UKF.n, 3);
            for i = 1:size(Xi, 2)
                z_diff = Zi(:,i) - z_pred;
                if z_diff(1) > pi, z_diff(1) = z_diff(1) - 2*pi; elseif z_diff(1) < -pi, z_diff(1) = z_diff(1) + 2*pi; end
                Pzz = Pzz + Wc(i) * z_diff * z_diff';
                Pxz = Pxz + Wc(i) * (Xi(:,i) - x_pred) * z_diff';
            end
            Pzz = Pzz + R;
            
            K = Pxz / Pzz;
            y = z_meas - z_pred;
            if y(1) > pi, y(1) = y(1) - 2*pi; elseif y(1) < -pi, y(1) = y(1) + 2*pi; end
            x_new = x_pred + K * y;
            P_new = P_pred - K * Pzz * K';
        end

        %% Plotting and Updates
        function updatePlots(app, is_reset, tracking_station_idx)
            if nargin < 3
                tracking_station_idx = 0;
            end

            k = app.TimeState.k; if k < 2 && ~is_reset, return; end
            idx = 1:k;
            time_hrs = app.TimeState.time_vector(idx)/3600;
            
            set(app.h.true_orbit, 'XData', app.History.x_true(1,idx)/1000, 'YData', app.History.x_true(2,idx)/1000, 'ZData', app.History.x_true(3,idx)/1000);
            set(app.h.est_orbit, 'XData', app.History.x_est(1,idx)/1000, 'YData', app.History.x_est(2,idx)/1000, 'ZData', app.History.x_est(3,idx)/1000);
            set(app.h.satellite, 'XData', app.UKF.x_true(1)/1000, 'YData', app.UKF.x_true(2)/1000, 'ZData', app.UKF.x_true(3)/1000);
            
            if is_reset
                for i=1:length(app.Stations)
                    r_eci = orbit_sim.ecef2eci_matrix(app.Constants.omega_earth * app.TimeState.t) * app.Stations(i).r_ecef;
                    set(app.h.stations(i), 'XData', r_eci(1)/1000, 'YData', r_eci(2)/1000, 'ZData', r_eci(3)/1000);
                end
            end

            for i=1:length(app.Stations)
                if i == tracking_station_idx
                    set(app.h.stations(i), 'MarkerFaceColor', 'r');
                else
                    set(app.h.stations(i), 'MarkerFaceColor', 'g');
                end
            end

            [lats, lons] = orbit_sim.eci2lla_vectorized(app.History.x_true(1:3,idx), app.TimeState.time_vector(idx), app.Constants);
            set(app.h.ground_track, 'XData', rad2deg(unwrap(lons)), 'YData', rad2deg(lats));
            
            error_norm = vecnorm(app.History.x_true(1:3,idx) - app.History.x_est(1:3,idx));
            sigma_bound = 3*sqrt(sum(app.History.P_diag(1:3,idx),1));
            set(app.h.pos_error, 'XData', time_hrs, 'YData', error_norm); set(app.h.pos_sigma, 'XData', time_hrs, 'YData', sigma_bound);
            
            cd_est_hist = app.History.x_est(7,idx); cd_sigma_bound = 3*sqrt(app.History.P_diag(7,idx));
            set(app.h.cd_est, 'XData', time_hrs, 'YData', cd_est_hist);
            set(app.h.cd_sigma, 'XData', [time_hrs, fliplr(time_hrs)], 'YData', [cd_est_hist+cd_sigma_bound, fliplr(cd_est_hist-cd_sigma_bound)]);
            
            for i=1:6, set(app.h.forces(i), 'XData', time_hrs, 'YData', app.History.force_mags(i,idx)); end
            
            app.TimeLabel.Text = sprintf('T: +%.2f hours', app.TimeState.t/3600);
        end
    end
    
    %% Static Library for Physics and Math
    methods (Static)
        function [dxdt, forces] = dynamics_wrapper(t, x, C, S, P)
            r = x(1:3); v = x(4:6); Cd = x(7);
            
            [r_sun, r_moon] = orbit_sim.ephemeris(t);
            
            a_2body = -C.GM * r / (norm(r)^3);
            
            a_zonal = [0;0;0];
            if P.J2 || P.J3J4
                r_norm = norm(r);
                tz = r(3)/r_norm;
                
                if P.J2
                    J2_term = -1.5 * C.J2 * (C.GM * C.R_earth^2) / (r_norm^4);
                    a_zonal = a_zonal + J2_term * ...
                        [ r(1)/r_norm*(1-5*tz^2); 
                          r(2)/r_norm*(1-5*tz^2); 
                          r(3)/r_norm*(3-5*tz^2) ];
                end
                if P.J3J4
                    J3_term = -2.5 * C.J3 * (C.GM * C.R_earth^3) / (r_norm^5);
                    a_zonal = a_zonal + J3_term * ...
                        [ r(1)/r_norm*(3*tz - 7*tz^3); 
                          r(2)/r_norm*(3*tz - 7*tz^3); 
                          6*tz^2 - 7*tz^4 - 0.6 ];
                end
            end
            
            a_drag = [0;0;0];
            if P.Drag
                r_norm = norm(r);
                v_rel_vec = v - cross([0;0;C.omega_earth], r); v_rel = norm(v_rel_vec);
                alt = r_norm - C.R_earth;
                rho = orbit_sim.atmospheric_density_f107(alt, P.F107);
                B = Cd * S.area_drag / S.mass;
                a_drag = -0.5 * rho * B * v_rel * v_rel_vec;
            end
            
            a_moon = [0;0;0]; a_sun = [0;0;0];
            if P.ThirdBody
                r_sat_moon = r_moon - r; r_sat_sun = r_sun - r;
                a_moon = C.GM_moon * (r_sat_moon/norm(r_sat_moon)^3 - r_moon/norm(r_moon)^3);
                a_sun  = C.GM_sun * (r_sat_sun/norm(r_sat_sun)^3 - r_sun/norm(r_sun)^3);
            end
            
            a_srp = [0;0;0];
            if P.SRP
                r_sat_sun = r_sun - r;
                nu = orbit_sim.shadow_function(r, r_sun, C.R_earth);
                if nu > 0
                    a_srp = nu * C.P_srp * (S.Cr * S.area_srp / S.mass) * r_sat_sun / norm(r_sat_sun);
                end
            end
            
            a_total = a_2body + a_zonal + a_drag + a_moon + a_sun + a_srp;
            dxdt = [v; a_total; 0];
            
            forces = [norm(a_2body); norm(a_zonal); norm(a_drag); norm(a_moon); norm(a_sun); norm(a_srp)];
        end

        function [lambda, Wm, Wc] = get_ukf_params(n, alpha, beta, kappa)
            lambda = alpha^2 * (n + kappa) - n;
            Wm = [lambda/(n+lambda); ones(2*n, 1)*0.5/(n+lambda)];
            Wc_0 = lambda/(n+lambda) + (1 - alpha^2 + beta);
            Wc_i = ones(1, 2*n)*0.5/(n+lambda);
            Wc = [Wc_0, Wc_i];
        end

        function Xi = generate_sigma_points(x, P, lambda)
            n = length(x);
            Psqrtm = chol((n + lambda) * P, 'lower');
            Xi = [x, x + Psqrtm, x - Psqrtm];
        end

        %% Atmospheric Density Model
        function rho = atmospheric_density_f107(alt_m, F107)
            alt_km = alt_m / 1000;
            if alt_km < 90, rho = 0; return; end
            if alt_km > 1000, rho = 0; return; end
            
            T_inf = 379 + 3.24 * F107;
            T_120 = 188;
            Tz = T_inf - (T_inf - T_120) * exp(-0.012 * (alt_km - 120));
            
            M = 28.96; R_star = 8314.32; g0 = 9.80665;
            H = R_star * Tz / (M * g0) / 1000; % Scale Height in km
            
            rho0 = 3.614e-9; h0 = 120; % kg/m^3 at 120km
            rho = rho0 * exp(-(alt_km - h0) / H);
        end

        %% Satellite Shadow Function
        function nu = shadow_function(r_sat, r_sun, R_e)
            e_sun = r_sun / norm(r_sun);
            s = dot(r_sat, e_sun);
            if s > 0, nu = 1.0; return; end
            if norm(cross(r_sat, e_sun)) > R_e, nu = 1.0; return; end
            nu = 0.0;
        end

        function [r_sun, r_moon] = ephemeris(t)
            JD = 2451545.0 + t / 86400;
            T_utc = (JD - 2451545.0) / 36525;
            
            M_sun = deg2rad(357.529 + 35999.05 * T_utc);
            lambda_sun = deg2rad(280.460 + 36000.77 * T_utc + 1.915 * sin(M_sun) + 0.020 * sin(2 * M_sun));
            r_sun_norm = (1.00014 - 0.01671 * cos(M_sun) - 0.00014 * cos(2 * M_sun)) * 149597870700;
            r_sun = [r_sun_norm * cos(lambda_sun); r_sun_norm * sin(lambda_sun); 0];
            
            lambda_moon = deg2rad(218.32 + 481267.8813 * T_utc);
            r_moon_norm = 385000e3;
            r_moon = [r_moon_norm * cos(lambda_moon); r_moon_norm * sin(lambda_moon); 0];
        end

        function [r_eci, v_eci] = orb_elements_to_state(a, e, i, RAAN, arg_p, TA, GM)
            p = a * (1 - e^2);
            r_norm = p / (1 + e * cos(TA));
            r_pqw = [r_norm * cos(TA); r_norm * sin(TA); 0];
            v_pqw = sqrt(GM/p) * [-sin(TA); e + cos(TA); 0];
            R_pqw2eci = (orbit_sim.rotz(RAAN) * orbit_sim.rotx(i) * orbit_sim.rotz(arg_p))';
            r_eci = R_pqw2eci * r_pqw;
            v_eci = R_pqw2eci * v_pqw;
        end
        
        %% Convert LLA to ECEF
        function r_ecef = lla2ecef(lat, lon, alt, R_earth)
            r_ecef = [(R_earth + alt) * cos(lat) * cos(lon);
                      (R_earth + alt) * cos(lat) * sin(lon);
                      (R_earth + alt) * sin(lat)];
        end
        
        %% Convert ECEF to AER
        function [az, el, rho] = ecef2aer(r_sat_eci, t, station, C)
            r_sat_ecef = orbit_sim.ecef2eci_matrix(C.omega_earth * t)' * r_sat_eci;
            rho_vec_ecef = r_sat_ecef - station.r_ecef;
            R_ecef2enu = [-sin(station.lon), cos(station.lon), 0;
                          -sin(station.lat)*cos(station.lon), -sin(station.lat)*sin(station.lon), cos(station.lat);
                           cos(station.lat)*cos(station.lon), cos(station.lat)*sin(station.lon), sin(station.lat)];
            rho_vec_enu = R_ecef2enu * rho_vec_ecef;
            rho = norm(rho_vec_enu);
            el = asin(rho_vec_enu(3) / rho);
            az = atan2(rho_vec_enu(1), rho_vec_enu(2));
        end
        
        %% Convert ECI to LLA (Vectorised)
        function [lat_vec, lon_vec] = eci2lla_vectorized(r_eci_mat, t_vec, C)
            num_points = size(r_eci_mat, 2);
            lat_vec = zeros(1, num_points);
            lon_vec = zeros(1, num_points);
            for i=1:num_points
                r_ecef = orbit_sim.ecef2eci_matrix(C.omega_earth * t_vec(i))' * r_eci_mat(:,i);
                lon_vec(i) = atan2(r_ecef(2), r_ecef(1));
                lat_vec(i) = asin(r_ecef(3) / norm(r_ecef));
            end
        end
        
        %% Measurement Model
        function z = measurement_model(r_sat_eci, t, station, C)
            [az, el, rho] = orbit_sim.ecef2aer(r_sat_eci, t, station, C);
            z = [az; el; rho];
        end
        
        %% Create Sky Plot Background
        function createManualSkyPlotBackground(ax)
            cla(ax); hold(ax, 'on'); axis(ax, 'equal'); axis(ax, [-100 100 -100 100]); ax.Visible = 'off';
            th = linspace(0, 2*pi, 100); radii = [30, 60, 90];
            for r = radii
                plot(ax, r*cos(th), r*sin(th), 'Color', [0.8 0.8 0.8]);
            end
            for ang_deg = 0:45:315
                ang_rad = deg2rad(ang_deg);
                plot(ax, [0 90*sin(ang_rad)], [0 90*cos(ang_rad)], 'Color', [0.8 0.8 0.8]);
            end
            labels = {'N','NE','E','SE','S','SW','W','NW'};
            angles = 0:45:315;
            for i=1:length(labels)
                ang_rad = deg2rad(angles(i));
                text(ax, 95*sin(ang_rad), 95*cos(ang_rad), labels{i}, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
            end
            text(ax, 0, 0, '90', 'HorizontalAlignment', 'center');
            text(ax, 0, 30, '60', 'HorizontalAlignment', 'center');
            text(ax, 0, 60, '30', 'HorizontalAlignment', 'center');
        end
        
        %% Rotation matrix from ECEF to ECI
        function R = ecef2eci_matrix(theta)
            R = [cos(theta), -sin(theta), 0; sin(theta), cos(theta), 0; 0, 0, 1];
        end
        
        function R = rotx(a)
            R = [1 0 0; 0 cos(a) sin(a); 0 -sin(a) cos(a)];
        end
        
        function R = rotz(a)
            R = [cos(a) sin(a) 0; -sin(a) cos(a) 0; 0 0 1];
        end
    end
end