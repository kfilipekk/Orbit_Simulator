classdef orbit_sim < handle
    % --- Private Properties ---
    properties (Access = private)
        % --- GUI Handles ---
        UIFigure, GridLayout, ControlPanel, PlotTabGroup
        Ax3D, AxGroundTrack, AxErrors, AxCd, AxSkyPlot, AxForceAnalysis
        
        % Controls
        RunPauseButton, ExportButton
        OrbitDropdown, J2Checkbox, J3J4Checkbox, DragCheckbox, ThirdBodyCheckbox, SRPCheckbox
        SpeedSlider, SpeedLabel, NoiseSlider, NoiseLabel, F107Slider, F107Label
        
        % Status Labels
        StatusLabel, TimeLabel, StationLabel
        
        % Graphics Handles
        h = struct() 
        
        % --- Simulation Core ---
        SimTimer, IsRunning = false
        
        % --- State & Models ---
        Constants, TimeState, Satellite, Stations, UKF, History, Perturbations
    end
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
            app.UIFigure = uifigure('Name', 'Advanced Navigation Simulator (UKF)', ...
                              'Position', [50 50 1700 950], ...
                              'CloseRequestFcn', @(src, event) delete(app));

            app.GridLayout = uigridlayout(app.UIFigure, [10, 8], 'RowHeight', {30, '1x', '1x', '1x', '1x', '1x', '1x', '1x', '1x', 30}, 'ColumnWidth', {280, '1x', '1x', '1x', '1x', '1x', '1x', '1x'});

            app.ControlPanel = uipanel(app.GridLayout, 'Title', 'Controls & Settings');
            app.ControlPanel.Layout.Row = [1 10]; app.ControlPanel.Layout.Column = 1;
            cpGrid = uigridlayout(app.ControlPanel, [5, 1], 'RowHeight', {'fit', 'fit', 'fit', 'fit', '1x'});

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

        end

        function resetSimulation(app)
            %% Placeholder
            fprintf('Simulation Reset!\n');
        end

        function onRunPause(app, ~, ~)
            %% Placeholder
            fprintf('Run/Pause Toggled!\n');
        end

        function onReset(app, ~, ~)
            app.resetSimulation();
        end

        function onRunPause(app, ~, ~)
            app.IsRunning = ~app.IsRunning;
            if app.IsRunning
                start(app.SimTimer);
            else
                stop(app.SimTimer);
            end
        end

        function initializeSimulationState(app)
            %% Constants
            app.Constants.GM = 3.986004418e14;
            app.Constants.R_earth = 6378137.0;
            app.Constants.J2 = 1.08263e-3;

            app.TimeState.t = 0; app.TimeState.dt_major = 60; app.TimeState.t_end = 24 * 3600; app.TimeState.k = 1;
            %% Satellite True State
            a = app.Constants.R_earth + 420e3; e = 0.0003; i = deg2rad(51.6);
            [r0, v0] = orbit_sim.orb_elements_to_state(a, e, i, 0, 0, 0, app.Constants.GM);
            app.Satellite.true_state = [r0; v0];
            %% UKF State
            app.UKF.x_est = app.Satellite.true_state + [1000; -1500; 800; 10; -5; 3];
            app.UKF.P = diag([1e7, 1e7, 1e7, 1e4, 1e4, 1e4]);
            app.UKF.Q = diag([1e-8, 1e-8, 1e-8, 1e-12, 1e-12, 1e-12]);
            app.UKF.n = 6; app.UKF.alpha = 1e-3; app.UKF.beta = 2; app.UKF.kappa = 0;

            num_steps = ceil(app.TimeState.t_end / app.TimeState.dt_major) + 1;
            app.History.x_true = nan(6, num_steps);
            app.History.x_est = nan(6, num_steps);
            app.History.x_true(:, 1) = app.Satellite.true_state;
            app.History.x_est(:, 1) = app.UKF.x_est;
        end

        function initializePlots(app)
            cla(app.Ax3D);
            %% Draw Earth
            hold(app.Ax3D, 'on'); grid(app.Ax3D, 'on'); axis(app.Ax3D, 'equal'); view(app.Ax3D, 3);
            [xE,yE,zE] = sphere(50);
            surf(app.Ax3D, xE*app.Constants.R_earth/1000, yE*app.Constants.R_earth/1000, zE*app.Constants.R_earth/1000, ...
                 'FaceColor', 'blue', 'EdgeColor', 'none', 'FaceAlpha', 0.7);
            %% Plot true + estimated orbits
            app.h.true_orbit = plot3(app.Ax3D, NaN, NaN, NaN, 'b-', 'LineWidth', 2, 'DisplayName', 'True Orbit');
            app.h.est_orbit = plot3(app.Ax3D, NaN, NaN, NaN, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Estimated Orbit');
            app.h.satellite = plot3(app.Ax3D, NaN, NaN, NaN, 'yo', 'MarkerFaceColor', 'y', 'MarkerSize', 10);
            legend(app.Ax3D, 'AutoUpdate', 'off');
            xlabel(app.Ax3D, 'X (km)'); ylabel(app.Ax3D, 'Y (km)'); zlabel(app.Ax3D, 'Z (km)');
            app.updatePlots();
        end

        function simulationStep(app)
            if app.TimeState.t >= app.TimeState.t_end, stop(app.SimTimer); app.IsRunning = false; return; end

            t_start = app.TimeState.t;
            t_end = t_start + app.TimeState.dt_major;
            app.TimeState.t = t_end;
            app.TimeState.k = app.TimeState.k + 1;

            %% Read perturbation settings from UI
            app.Perturbations.J2 = app.J2Checkbox.Value;

            %% Create handle to new wrapper
            dynamics_handle = @(t, y) orbit_sim.dynamics_wrapper(t, y, app.Constants, app.Perturbations);
            ode_opts = odeset('RelTol', 1e-9, 'AbsTol', 1e-10);

            [~, y_out] = ode45(dynamics_handle, [t_start, t_end], app.Satellite.true_state, ode_opts);
            app.Satellite.true_state = y_out(end, :)';

            [x_pred, P_pred] = app.ukf_predict(app.UKF.x_est, app.UKF.P, dynamics_handle, [t_start, t_end], app.UKF.Q, ode_opts);

            %% With no measurements, the prediction becomes the new estimate
            app.UKF.x_est = x_pred;
            app.UKF.P = P_pred;
            app.History.x_true(:, app.TimeState.k) = app.Satellite.true_state;
            app.History.x_est(:, app.TimeState.k) = app.UKF.x_est;
            app.updatePlots();
        end
        function simulationStep(app)
            if app.TimeState.t >= app.TimeState.t_end, stop(app.SimTimer); app.IsRunning = false; return; end

            t_start = app.TimeState.t;
            t_end = t_start + app.TimeState.dt_major;
            app.TimeState.t = t_end;
            app.TimeState.k = app.TimeState.k + 1;

            %% Dynamics
            dynamics_handle = @(t, y) orbit_sim.dynamics_wrapper(t, y, app.Constants, app.Satellite, app.Perturbations);
            ode_opts = odeset('RelTol', 1e-9, 'AbsTol', 1e-10);

            [~, y_out] = ode45(dynamics_handle, [t_start, t_end], app.Satellite.true_state, ode_opts);
            app.Satellite.true_state = y_out(end, :)';

            %% UKF Prediction
            [x_pred, P_pred] = app.ukf_predict(app.UKF.x_est, app.UKF.P, dynamics_handle, [t_start, t_end], app.UKF.Q, ode_opts);

            %% Measurements
            measurements = {};
            for i = 1:length(app.Stations)
                z = orbit_sim.measurement_model(app.Satellite.true_state(1:3), t_end, app.Stations(i), app.Constants);
                if z(2) > app.Constants.min_elevation
                    z = z + sqrt(diag(app.UKF.R)) .* randn(3,1);
                    measurements{end+1} = struct('z', z, 'station', app.Stations(i));
                end
            end

            app.UKF.x_est = x_pred;
            app.UKF.P = P_pred;
            
            for i = 1:length(measurements)
                [app.UKF.x_est, app.UKF.P] = app.ukf_update(app.UKF.x_est, app.UKF.P, ...
                                                          measurements{i}.z, measurements{i}.station, ...
                                                          t_end, app.UKF.R);
            end

            app.History.x_true(:, app.TimeState.k) = app.Satellite.true_state;
            app.History.x_est(:, app.TimeState.k) = app.UKF.x_est;
            app.updatePlots();
        end

        function updatePlots(app)
            k = app.TimeState.k;
            idx = 1:k;
            
            %% Orbits
            set(app.h.true_orbit, 'XData', app.History.x_true(1,idx)/1000, ...
                                 'YData', app.History.x_true(2,idx)/1000, ...
                                 'ZData', app.History.x_true(3,idx)/1000);
                                 
            if isfield(app.h, 'est_orbit') && isfield(app.History, 'x_est')
                set(app.h.est_orbit, 'XData', app.History.x_est(1,idx)/1000, ...
                                    'YData', app.History.x_est(2,idx)/1000, ...
                                    'ZData', app.History.x_est(3,idx)/1000);
            end
            
            %% Satellite
            set(app.h.satellite, 'XData', app.Satellite.true_state(1)/1000, ...
                                'YData', app.Satellite.true_state(2)/1000, ...
                                'ZData', app.Satellite.true_state(3)/1000);

            %% Errors
            if isfield(app.h, 'error_plot') && k > 1
                pos_error = sqrt(sum((app.History.x_true(1:3,idx) - app.History.x_est(1:3,idx)).^2, 1));
                set(app.h.error_plot, 'XData', app.TimeState.dt_major*idx/3600, 'YData', pos_error/1000);
            end

            %% Forces
            if app.Perturbations.show_forces && k > 1
                [~, forces] = orbit_sim.dynamics_wrapper(app.TimeState.t, app.Satellite.true_state, ...
                                                      app.Constants, app.Satellite, app.Perturbations);
                force_norms = struct2array(structfun(@norm, forces, 'UniformOutput', false));
                if isfield(app.h, 'force_plot')
                    set(app.h.force_plot, 'YData', log10(force_norms));
                end
            end

            drawnow;
        end

        function [x_pred, P_pred] = ukf_predict(app, x_est, P_est, dynamics, tspan, Q, ode_opts)
            %% Generate sigma points
            n = app.UKF.n;
            [lambda, Wm, Wc] = orbit_sim.get_ukf_params(n, app.UKF.alpha, app.UKF.beta, app.UKF.kappa);
            Xi = orbit_sim.generate_sigma_points(x_est, P_est, lambda);

            %% Propagate each sigma point through
            Yi = zeros(size(Xi));
            for i = 1:size(Xi, 2)
                [~, y_i] = ode45(dynamics, tspan, Xi(:,i), ode_opts);
                Yi(:,i) = y_i(end,:)';
            end

            %% Recombine to get predicted state and covariance
            x_pred = Yi * Wm;
            P_pred = zeros(n);
            for i = 1:size(Yi, 2)
                P_pred = P_pred + Wc(i) * (Yi(:,i) - x_pred) * (Yi(:,i) - x_pred)';
            end

            %% noise
            dt = tspan(2) - tspan(1);
            P_pred = P_pred + Q * dt;
        end

        function [x_new, P_new] = ukf_update(app, x_pred, P_pred, z_meas, station, t, R)
            %% Sigma points
            n = app.UKF.n;
            [lambda, Wm, Wc] = orbit_sim.get_ukf_params(n, app.UKF.alpha, app.UKF.beta, app.UKF.kappa);
            Xi = orbit_sim.generate_sigma_points(x_pred, P_pred, lambda);

            %% Measurement transform
            Zi = zeros(3, size(Xi, 2));
            for i = 1:size(Xi, 2)
                Zi(:,i) = orbit_sim.measurement_model(Xi(1:3,i), t, station, app.Constants);
            end

            %% Statistics
            z_pred = Zi * Wm;
            Pzz = R;
            Pxz = zeros(n, 3);
            
            for i = 1:size(Xi, 2)
                dZ = Zi(:,i) - z_pred;
                dX = Xi(:,i) - x_pred;
                dZ(1) = mod(dZ(1) + pi, 2*pi) - pi;
                
                Pzz = Pzz + Wc(i) * (dZ * dZ');
                Pxz = Pxz + Wc(i) * (dX * dZ');
            end

            %% Update
            K = Pxz / Pzz;
            dz = z_meas - z_pred;
            dz(1) = mod(dz(1) + pi, 2*pi) - pi;
            
            x_new = x_pred + K * dz;
            P_new = P_pred - K * Pzz * K';
            P_new = (P_new + P_new')/2;
        end
    end
    
    methods (Static)
        function [dxdt, forces] = dynamics_wrapper(t, x, C, S, P)
            r_vec = x(1:3);
            v_vec = x(4:6);
            r_norm = norm(r_vec);

            %% Initialize forces
            forces = struct('a_2body', zeros(3,1), 'a_j2', zeros(3,1), ...
                          'a_drag', zeros(3,1), 'a_srp', zeros(3,1), ...
                          'a_3body', zeros(3,1));

            %% Two-body
            forces.a_2body = -C.GM * r_vec / (r_norm^3);
            a_total = forces.a_2body;

            %% Zonal harmonics
            if P.zonals
                z2 = r_vec(3)^2;
                r2 = r_norm^2;
                r5 = r_norm^5;
                
                J2_term = -1.5 * C.J2 * (C.GM * C.R_earth^2) / r5;
                forces.a_j2(1) = J2_term * r_vec(1) * (1 - 5*z2/r2);
                forces.a_j2(2) = J2_term * r_vec(2) * (1 - 5*z2/r2);
                forces.a_j2(3) = J2_term * r_vec(3) * (3 - 5*z2/r2);
                
                a_total = a_total + forces.a_j2;
            end

            %% Drag
            if P.drag
                [r_sun, ~] = orbit_sim.ephemeris(t);
                rho = orbit_sim.atmospheric_density_f107(r_norm - C.R_earth, S.F107);
                v_rel = v_vec;
                v_rel_norm = norm(v_rel);
                forces.a_drag = -0.5 * rho * S.Cd * S.area_m2 / S.mass_kg * v_rel_norm * v_rel;
                a_total = a_total + forces.a_drag;
            end

            %% SRP
            if P.srp
                [r_sun, ~] = orbit_sim.ephemeris(t);
                r_sat2sun = r_sun - r_vec;
                r_sat2sun_norm = norm(r_sat2sun);
                nu = orbit_sim.shadow_function(r_vec, r_sun, C.R_earth);
                P_srp = C.P_srp * (C.AU/r_sat2sun_norm)^2;
                forces.a_srp = nu * P_srp * C.Cr * S.area_m2 / S.mass_kg * (r_sat2sun/r_sat2sun_norm);
                a_total = a_total + forces.a_srp;
            end

            %% Third body
            if P.thirdbody
                [r_sun, r_moon] = orbit_sim.ephemeris(t);
                r_sat2sun = r_sun - r_vec;
                r_sat2moon = r_moon - r_vec;
                
                forces.a_3body = C.GM_sun * (r_sat2sun/norm(r_sat2sun)^3 - r_sun/norm(r_sun)^3);
                forces.a_3body = forces.a_3body + ...
                               C.GM_moon * (r_sat2moon/norm(r_sat2moon)^3 - r_moon/norm(r_moon)^3);
                               
                a_total = a_total + forces.a_3body;
            end

            dxdt = [v_vec; a_total];
        end

        function rho = atmospheric_density_f107(alt_m, F107)
            h0 = 400e3;
            rho0 = 2.7e-12;
            H = 53.8e3;
            
            f107_nominal = 150;
            density_multiplier = (F107/f107_nominal)^0.25;
            
            rho = rho0 * exp(-(alt_m - h0)/H) * density_multiplier;
        end

        function nu = shadow_function(r_sat, r_sun, R_e)
            r_sat2sun = r_sun - r_sat;
            r_sat2sun_norm = norm(r_sat2sun);

            cos_theta = dot(r_sat, r_sat2sun)/(norm(r_sat)*r_sat2sun_norm);
            
            if cos_theta < 0
                d = norm(cross(r_sat, r_sat2sun))/r_sat2sun_norm;
                if d < R_e
                    nu = 0;
                    return;
                end
            end
            nu = 1;
        end

        function [r_sun, r_moon] = ephemeris(t)
            
            omega_sun = 2*pi/(365.25*24*3600);
            r_sun = 149597870e3 * [cos(omega_sun*t); sin(omega_sun*t); 0];
            
            omega_moon = 2*pi/(27.32*24*3600);
            r_moon = 384400e3 * [cos(omega_moon*t); sin(omega_moon*t); 0];
        end

        function [r_eci, v_eci] = orb_elements_to_state(a, e, i, RAAN, arg_p, TA, GM)
            p = a * (1 - e^2);
            r_norm = p / (1 + e * cos(TA));
            r_pqw = [r_norm * cos(TA); r_norm * sin(TA); 0];
            v_pqw = sqrt(GM/p) * [-sin(TA); e + cos(TA); 0];
            
            Rz_RAAN = orbit_sim.rotz(-RAAN);
            Rx_i = orbit_sim.rotx(-i);
            Rz_argp = orbit_sim.rotz(-arg_p);
            
            R_pqw2eci = (Rz_RAAN * Rx_i * Rz_argp)';
            r_eci = R_pqw2eci * r_pqw;
            v_eci = R_pqw2eci * v_pqw;
        end

        function R = rotx(angle)
            % Rotation matrix about x-axis (IA notes if you forget)
            R = [1 0 0; 
                 0 cos(angle) sin(angle); 
                 0 -sin(angle) cos(angle)];
        end

        function R = rotz(angle)
            % Rotation matrix about z-axis
            R = [cos(angle) sin(angle) 0;
                 -sin(angle) cos(angle) 0;
                 0 0 1];
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

        function z = measurement_model(r_sat_eci, t, station, C)
            %% Convert satellite ECI position to ECEF
            theta_GMST = orbit_sim.greenwich_sidereal_time(t);
            T_eci2ecef = orbit_sim.ecef2eci_matrix(theta_GMST)';
            r_sat_ecef = T_eci2ecef * r_sat_eci;
            
            %% Get station ECEF position
            r_station_ecef = orbit_sim.lla2ecef(station.lat, station.lon, station.alt);
            
            rho_ecef = r_sat_ecef - r_station_ecef;
            [az, el, rng] = orbit_sim.ecef2aer(rho_ecef, station.lat, station.lon, station.alt);
            
            %% Return measurement vector [az; el; range]
            z = [az; el; rng];
        end
        
        function R = ecef2eci_matrix(theta_GMST)
            %% Rotation matrix from ECEF to ECI
            R = orbit_sim.rotz(theta_GMST);
        end

        function theta_GMST = greenwich_sidereal_time(t)
            omega_earth = 7.2921150e-5;
            theta_GMST = omega_earth * t;
        end

        function r_ecef = lla2ecef(lat, lon, alt)
            %% Convert geodetic coordinates to ECEF
            a = 6378137.0;
            e = 0.081819190842622;
            
            N = a / sqrt(1 - e^2 * sin(lat)^2);
            
            r_ecef = [(N + alt)*cos(lat)*cos(lon);
                      (N + alt)*cos(lat)*sin(lon);
                      (N*(1-e^2) + alt)*sin(lat)];
        end

        function [az, el, rng] = ecef2aer(rho_ecef, lat, lon, alt)
            %% Convert ECEF relative position vector to azimuth, elevation, range
            sl = sin(lon); cl = cos(lon);
            sphi = sin(lat); cphi = cos(lat);
            
            R1 = [-sl -cl*sphi cl*cphi;
                   cl -sl*sphi sl*cphi;
                   0   cphi     sphi];
            
            rho_sez = R1 * rho_ecef;
            
            rng = norm(rho_sez);
            az = atan2(rho_sez(2), -rho_sez(1));
            el = asin(rho_sez(3)/rng);
        end
    end
end