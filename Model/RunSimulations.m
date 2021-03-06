%% RunSimulations
% This file will run all simulations in a given project folder

%% Change to this script's working directory
[filepath,~,~] = fileparts(mfilename('fullpath'));
cd(filepath)

%% List of Project Folders
i = 1;
% Project_Folder{i} = 'phiFsolve_Test';   i = i+1;
Project_Folder{i} = 'KBCP_Mode_Test';   i = i+1;
% Project_Folder{i} = 'Half_Cell_Test';   i = i+1;
% Project_Folder{i} = 'Final_Lui_Wiley_Model';   i = i+1;
% Project_Folder{i} = 'Change_Mode_Number_Test';   i = i+1;

%%
num_Proj = length(Project_Folder);

%% Make a list of all sim file names with full path name
for i = 1:num_Proj
    % Make a list of simulations in the project folder
    oldFolder = cd([pwd filesep 'Results' filesep Project_Folder{i}]);
    list = dir('*.mat*');
    num_files = length(list);
    for j = 1:num_files
        if ~exist('sim_filenames')
            sim_filenames{1} = [pwd filesep list(j).name];
        else
            sim_filenames{end+1,1} = [pwd filesep list(j).name];
        end
    end
    %Go back to oldFolder
    cd(oldFolder);
end
num_sim_files = length(sim_filenames);

%% Run all the simulations
for i = 1:num_sim_files
    disp(' ')
    disp(['Performing Simulation ' num2str(i) '/' num2str(num_sim_files)])
    disp(datestr(datetime));
    load(sim_filenames{i})
    
    %% Check if it has already ran
    if ~exist('postProcessComplete')
        %% Run simulation
        tSimStart = tic;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% ---- Polarization ---- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        if SIM.SimMode == 1 
            % Simulation Parameters
            Tol.Abs = 1E-7;
            Tol.Rel = 1E-7;

            events = @(t,SV) batt_events(t,SV,SIM,P,N,FLAG);

            options = odeset('RelTol' ,Tol.Rel,      ...
                             'AbsTol' ,Tol.Abs,      ...
                             'Mass'   ,SIM.M,        ...
                             'Events' ,events);%,       ...
                            %'MaxStep',1e2);
            
            i_user = 0;
            for k = 1:length(SIM.tspan)-1
                if k == 1
                    tspan = [SIM.tspan(k), SIM.tspan(k+1)-1e-8];
                    SV_IC = SIM.SV_IC;
                    [t_soln_int,SV_soln_int,te,ye,ie] = ode15s(@(t,SV)batt_GovEqn(t,SV,AN,CA,SEP,EL,SIM,CONS,P,N,FLAG,PROPS,i_user),tspan,SV_IC,options);
                    t_soln = t_soln_int;
                    SV_soln = SV_soln_int;
                else
                    %New IC
                    SV_IC = SV_soln_int(end,:);
                    tspan = [SIM.tspan(k), SIM.tspan(k+1)-1e-8];
                    [t_soln_int,SV_soln_int,te,ye,ie] = ode15s(@(t,SV)batt_GovEqn(t,SV,AN,CA,SEP,EL,SIM,CONS,P,N,FLAG,PROPS,i_user),tspan,SV_IC,options);
                    t_soln = [t_soln; t_soln_int];
                    SV_soln = [SV_soln; SV_soln_int];
                end
            end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% ---- Harmonic Perturbation ---- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        elseif SIM.SimMode == 2 
            % Simulation Parameters
            Tol.Abs = 1E-7;
            Tol.Rel = 1E-7;

            events = @(t,SV) batt_events(t,SV,SIM,P,N,FLAG);

            options = odeset('RelTol' ,Tol.Rel,      ...
                             'AbsTol' ,Tol.Abs,      ...
                             'Mass'   ,SIM.M,        ...
                             'Events' ,events);%,       ...
                            %'MaxStep',1e2);
            
            i_user = 0;
            tspan = SIM.tspan;
            SV_IC = SIM.SV_IC;
            [t_soln_int,SV_soln_int,te,ye,ie] = ode15s(@(t,SV)batt_GovEqn(t,SV,AN,CA,SEP,EL,SIM,CONS,P,N,FLAG,PROPS,i_user),tspan,SV_IC,options);
            t_soln = t_soln_int;
            SV_soln = SV_soln_int;
            
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% ---- State Space EIS ---- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        elseif SIM.SimMode == 3 
            [A,B,C,D,Z_results] = getSSImpedance(AN,CA,SEP,EL,SIM,CONS,P,N,FLAG,PROPS);
            
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% ---- Known BC Profile Controller ---- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        elseif SIM.SimMode == 4 
            % Initialize Save Variables
                t_soln      = [];
                SV_soln     = [];
                i_user_soln = [];
                mode_soln   = [];
                step_soln   = [];
                
            % Loop through all of the steps
            for k = 1:length(SIM.Controller_MO_File)
                SIM.current_MO_step = k;
                MO = SIM.Controller_MO_File(SIM.current_MO_step).MO;
                
                % Set SV
                    if k == 1
                        SV_IC = SIM.SV_IC;
                    else
                        SV_IC = SV_soln(end,:);
                    end
                
                % Determine i_user and tspan
                    if MO == 1 %CC
                        if SIM.Controller_MO_File(SIM.current_MO_step).CorD == 'C'
                            i_user = -SIM.Controller_MO_File(SIM.current_MO_step).C_rate*SIM.Cell_Cap/SIM.A_c;
                        else
                            i_user =  SIM.Controller_MO_File(SIM.current_MO_step).C_rate*SIM.Cell_Cap/SIM.A_c;
                        end
                        tfinal = SIM.Controller_MO_File(SIM.current_MO_step).Time_lim;
                        tspan = [0,tfinal];
                    elseif MO == 2 % CV
                        % i_user will be solved for in the next section
                        tspan_vec = 0:SIM.DiscreteTimeStep:SIM.Controller_MO_File(SIM.current_MO_step).Time_lim;
                    elseif MO == 3 % Relaxation
                        i_user = 0;
                        tfinal = SIM.Controller_MO_File(SIM.current_MO_step).Time_lim;
                        tspan = [0,tfinal];
                    end
                
                % call ODE
                % Simulation Parameters
                Tol.Abs = 1E-7;
                Tol.Rel = 1E-7;

                events = @(t,SV) batt_events(t,SV,SIM,P,N,FLAG);

                options_CC = odeset('RelTol' ,Tol.Rel,      ...
                                    'AbsTol' ,Tol.Abs,      ...
                                    'Mass'   ,SIM.M,        ...
                                    'Events' ,events);%,       ...
                                   %'MaxStep',1e2);

                options_CV = odeset('RelTol' ,Tol.Rel,      ...
                                    'AbsTol' ,Tol.Abs,      ...
                                    'Mass'   ,SIM.M);
                    if MO == 1 %CC
                        SOLN = ode15s(@(t,SV)batt_GovEqn(t,SV,AN,CA,SEP,EL,SIM,CONS,P,N,FLAG,PROPS,i_user),tspan,SV_IC,options_CC);
                    elseif MO == 2 % CV
                        % First iteration is not using ODExtend
                        % Setup variables to track i_user history
                        N_history = ceil(SIM.ZeroTime / SIM.DiscreteTimeStep);
%                         SIM.i_user_history = ones(N_history,1);
                        SIM.i_user_history = zeros(N_history,1);
                        % Calc i_user from controller
                            SV = SV_IC;
                            SV = SV1Dto2D(SV , N , P , FLAG);
                            i_user = SIM.ControllerHandle(SV, P , SIM);
                            % Update history
                            SIM.i_user_history = [SIM.i_user_history(2:end); i_user];
                            
                        % Call ode solver
                            SOLN = ode15s(@(t,SV)batt_GovEqn(t,SV,AN,CA,SEP,EL,SIM,CONS,P,N,FLAG,PROPS,i_user),tspan_vec(1:2),SV_IC,options_CV);
                            i_user_soln_int = i_user*ones(length(SOLN.x),1);
                        for j = 3:length(tspan_vec)
                            % Calc i_user
                                SV_temp = SOLN.y';
                                SV = SV_temp(end,:);
                                SV = SV1Dto2D(SV , N , P , FLAG);
                                i_user = SIM.ControllerHandle(SV, P , SIM);
                                % Update history
                                SIM.i_user_history = [SIM.i_user_history(2:end); i_user];
                            % Call ODE solver %%%%% Will this change i_user for the GovEqn or do I need to add the fnc handle for GovEqn
                                SOLN = odextend(SOLN,@(t,SV)batt_GovEqn(t,SV,AN,CA,SEP,EL,SIM,CONS,P,N,FLAG,PROPS,i_user),tspan_vec(j));
                            % add something to account for C/20 and Delta SV
                                
                            % Update i_user variables
                                old_size = length(i_user_soln_int);
                                new_size = length(SOLN.x);
                                
                                i_user_int_int  = i_user*ones((new_size - old_size),1);
                                i_user_soln_int = [i_user_soln_int ; i_user_int_int];
                                
                            % Break out of the for loop if time_zero has been reached
                                if sum(SIM.i_user_history) == 0
                                    break
                                end
                        end
                        t_soln_int  = SOLN.x';
                        SV_soln_int = SOLN.y';

                    elseif MO == 3 % Relaxation
                        SOLN = ode15s(@(t,SV)batt_GovEqn(t,SV,AN,CA,SEP,EL,SIM,CONS,P,N,FLAG,PROPS,i_user),tspan,SV_IC,options_CC);
                    end
                
                % Save solution
                    if MO ~= 2 % CC, Relax
                        if FLAG.SaveSolnDiscreteTime
                            new_tfinal = SOLN.x(end);
                            save_time = (0:SIM.SaveTStep:new_tfinal)';
                            t_soln_int  = save_time;
                            if ~isempty(t_soln)
                                t_soln_int = t_soln_int + t_soln(end);
                            end
                            
                            SV_soln_int = (deval(SOLN,save_time))';
                        else
                            t_soln_int = SOLN.x';
                            if ~isempty(t_soln)
                                t_soln_int = t_soln_int + t_soln(end);
                            end

                            SV_soln_int = SOLN.y';
                        end
                        i_user_soln_int = i_user*ones(length(t_soln_int),1);
%                         t_soln_int = SOLN.x';
%                         if ~isempty(t_soln)
%                             t_soln_int = t_soln_int + t_soln(end);
%                         end
%                         
%                         SV_soln_int = SOLN.y';
%                         i_user_soln_int = i_user*ones(length(SOLN.x),1);
                    else % CV
                        if ~isempty(t_soln)
                            t_soln_int = t_soln_int + t_soln(end);
                        end
                    end
                    
                    mode_soln_int = MO * ones(length(t_soln_int),1);
                    step_soln_int = k  * ones(length(t_soln_int),1);
                    
                    t_soln      = [t_soln      ; t_soln_int     ];
                    SV_soln     = [SV_soln     ; SV_soln_int    ];
                    i_user_soln = [i_user_soln ; i_user_soln_int];
                    mode_soln   = [mode_soln   ; mode_soln_int  ];
                    step_soln   = [step_soln   ; step_soln_int  ];
            end
            
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% ---- MOO Controller ---- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        elseif SIM.SimMode == 5
            
           
            
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% ---- Manual Current Profile ---- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        elseif SIM.SimMode == 7 
            % Simulation Parameters
            Tol.Abs = 1E-7;
            Tol.Rel = 1E-7;

            events = @(t,SV) batt_events(t,SV,SIM,P,N,FLAG);

            options = odeset('RelTol' ,Tol.Rel,      ...
                             'AbsTol' ,Tol.Abs,      ...
                             'Mass'   ,SIM.M,        ...
                             'Events' ,events);%,       ...
                            %'MaxStep',1e2);
            
            counter = 0;
            continue_Refinement = 1;
            while continue_Refinement
                counter = counter + 1;
                if counter == 1
                    disp(['Iteration ' num2str(counter)])
                else
                    disp(['Iteration ' num2str(counter) ,' sum_of_refinement_vec = ' num2str(SIM.sum_of_refinement_vec(counter - 1))])
                end
                %% Run a simulation
                i_user = 0;
                tspan = SIM.tspan;
                SV_IC = SIM.SV_IC;
                [t_soln,SV_soln,~,~,~] = ode15s(@(t,SV)batt_GovEqn(t,SV,AN,CA,SEP,EL,SIM,CONS,P,N,FLAG,PROPS,i_user),tspan,SV_IC,options);

                %% Analyze the results
                r = max( N.N_SV_AN , N.N_SV_CA );
                N_t_steps = length(t_soln);
                SV      = zeros(r , N.N_CV_tot, N_t_steps );
                del_phi = zeros( N_t_steps , N.N_CV_tot );

                for j = 1:length(t_soln)
                    SV( : , : , j )  = SV1Dto2D( SV_soln( j , : ) , N , P , FLAG );
                    del_phi( j , : ) = SV( P.phi_ed , : , j) - SV( P.phi_el , : , j);
                end

                %% Modify the charge profile
                if FLAG.Optimize_Profile
                    [continue_Refinement, SIM.profile_current , SIM.region_current_vec , sum_of_refinement] = plating_Refinement(del_phi, t_soln, SIM, N);
                    SIM.sum_of_refinement_vec(counter) = sum_of_refinement;
                else
                    continue_Refinement = 0;
                end

                %% Max number of iterations
                if counter == SIM.max_iterations
                    continue_Refinement = 0;
                end
                
            end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% ---- Data Files ---- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        elseif SIM.SimMode == 0 
            disp('This file is not a simulation file')
        else 
            % Maybe don't need else
            disp('Not a recognized simulation mode')
        end
        SIM.tSimEnd = toc(tSimStart);
        
        
        %% Save results
        SIZE_SV_soln = whos('SV_soln');
        if SIM.SimMode == 0
            % Just a data file, don't save
        elseif SIM.SimMode == 3  % ---- State Space EIS ----
            postProcessComplete = 1;
            save(sim_filenames{i},'AN','CA','SEP','EL','SIM','CONS','P','N','FLAG','PROPS','A','B','C','D','Z_results','postProcessComplete')
            if FLAG.SaveSystemForEst % Save System to be used in Estimator
                multiple = -SIM.A_c^-1;
                sys = multiple*ss(A,B,C,D,'E',SIM.M);
                OutputAtEquil = SIM.OutputAtEquil;
                filename = [num2str(SIM.SOC_start) 'SOC'];
                save(filename,'sys','OutputAtEquil')
            end
        elseif SIM.SimMode == 4
            save(sim_filenames{i},'t_soln','SV_soln','i_user_soln','mode_soln','step_soln','AN','CA','SEP','EL','SIM','CONS','P','N','FLAG','PROPS')
        elseif SIM.SimMode == 5
            save(sim_filenames{i},'t_soln','SV_soln','i_user_soln','AN','CA','SEP','EL','SIM','CONS','P','N','FLAG','PROPS')
        else
            if SIZE_SV_soln.bytes > 1e9 % 1 GB = 1e9 bytes
                save(sim_filenames{i},'t_soln','SV_soln','AN','CA','SEP','EL','SIM','CONS','P','N','FLAG','PROPS','-v7.3')
            else
                save(sim_filenames{i},'t_soln','SV_soln','AN','CA','SEP','EL','SIM','CONS','P','N','FLAG','PROPS')
            end
        end
        
        %% Perform post-processing (Also re-saves data)
        if SIM.SimMode == 0
            %Don't do anything to the data file
        else
            if SIM.SimMode ~= 3 % ---- State Space EIS ----
                if FLAG.doPostProcessing
                    disp('Performing Post-Processing')
                    postProcessing(sim_filenames{i});
                end
            end
        end
        
        %% Plot
        if exist('FLAG','var') && isfield(FLAG,'Plot')
            if FLAG.Plot
                plotfcn(sim_filenames{i});
            end
        end
    else
        disp('Simulation has already been analyzed')
    end
    clearvars -except sim_filenames i k num_sim_files
end
disp('Finished all simulations')
