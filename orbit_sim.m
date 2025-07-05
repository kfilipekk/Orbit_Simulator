classdef orbit_sim < handle
    properties (Access = private)
        %% GUI Handles
        UIFigure, Ax3D, J2Checkbox

        h = struct()
        SimTimer, IsRunning = false

        %% State & Models
        Constants, TimeState, Satellite, History, Perturbations, UKF
    end

    methods (Access = public)
        function app = orbit_sim()
            app.UIFigure = uifigure('Name', 'Orbit Simulator (UKF)', 'Position', [50 50, 1200, 800]);
            %% Controls %%
            cp = uipanel(app.UIFigure, 'Title', 'Controls', 'Position', [10, 590, 140, 200]);
            uibutton(cp, 'push', 'Text', 'Reset', 'Position', [20 140 100 22], 'ButtonPushedFcn', @app.onReset);
            uibutton(cp, 'push', 'Text', 'Run/Pause', 'Position', [20 110 100 22], 'ButtonPushedFcn', @app.onRunPause);
            pp = uipanel(cp, 'Title', 'Perturbations', 'Position', [10 10 120 80]);
            app.J2Checkbox = uicheckbox(pp, 'Text', 'J2 Effect', 'Value', 1, 'Position', [10 30 100 22]);
            %% Axes %%
            app.Ax3D = uiaxes(app.UIFigure, 'Position', [160, 50, 1000, 700]);
            title(app.Ax3D, '3D Orbit Trajectory (ECI)');
            %% Timer %%
            app.SimTimer = timer('ExecutionMode', 'fixedRate', 'Period', 0.1, 'TimerFcn', @(~,~) app.simulationStep);
            app.onReset();
        end
    end

    methods (Access = private)
        function onReset(app, ~, ~)
            if ~isempty(app.SimTimer) && app.IsRunning
                stop(app.SimTimer);
                app.IsRunning = false;
            end
            app.initializeSimulationState();
            app.initializePlots();
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
        function dxdt = dynamics_wrapper(t, x, C, P)
            r_vec = x(1:3);
            v_vec = x(4:6);

            r_norm = norm(r_vec);
            a_2body = -C.GM * r_vec / (r_norm^3);

            %% J2 Perturbation %%
            a_j2 = [0; 0; 0];
            if P.J2
                z2 = r_vec(3)^2;
                J2_term = -1.5 * C.J2 * (C.GM * C.R_earth^2) / (r_norm^5);

                a_j2(1) = J2_term * r_vec(1) * (1 - 5 * z2 / r_norm^2);
                a_j2(2) = J2_term * r_vec(2) * (1 - 5 * z2 / r_norm^2);
                a_j2(3) = J2_term * r_vec(3) * (3 - 5 * z2 / r_norm^2);
            end

            a_total = a_2body + a_j2;
            dxdt = [v_vec; a_total];
        end

        function updatePlots(app)
            k = app.TimeState.k;
            idx = 1:k;
            %% Update the full trajectory line and satellite marker
            set(app.h.true_orbit, 'XData', app.History.x_true(1,idx)/1000, 'YData', app.History.x_true(2,idx)/1000, 'ZData', app.History.x_true(3,idx)/1000);
            if isfield(app.h, 'est_orbit') && isfield(app.History, 'x_est')
                set(app.h.est_orbit, 'XData', app.History.x_est(1,idx)/1000, 'YData', app.History.x_est(2,idx)/1000, 'ZData', app.History.x_est(3,idx)/1000);
            end
            set(app.h.satellite, 'XData', app.Satellite.true_state(1)/1000, 'YData', app.Satellite.true_state(2)/1000, 'ZData', app.Satellite.true_state(3)/1000);
            drawnow;
        end
        function [x_pred, P_pred] = ukf_predict(app, x_est, P_est, dynamics, tspan, Q, ode_opts)
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