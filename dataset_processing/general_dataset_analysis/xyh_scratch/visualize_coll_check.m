clc;
clear;
close all;

rng(3);
%% Load data
dataset = strcat(getenv('collision_checking_dataset_folder'), '/dataset_xyh_1/');
set_dataset = strcat(dataset,'set_1/');

G = load_graph( strcat(set_dataset,'graph.txt') );
load(strcat(set_dataset, 'world_library_assignment.mat'), 'world_library_assignment');
load(strcat(set_dataset, 'path_library.mat'), 'path_library');
path_library = path_library(1:20);
load( strcat(set_dataset, 'coll_check_results.mat'), 'coll_check_results' );

% Only for 2d viz
env_dataset = strcat(dataset,'environments/');
load(strcat(set_dataset, 'edge_traj_list.mat'), 'edge_traj_list');
id_list = sub2ind(size(G), [edge_traj_list.id1]', [edge_traj_list.id2]');

%% Extract relevant info
world_library_assignment = logical(world_library_assignment);
coll_check_results = logical(coll_check_results);
edge_check_cost = ones(1, size(coll_check_results,2)); %transpose(full(G(find(G)))); %
path_edgeid_map = get_path_edgeid_map( path_library, G );

%% Do a dimensionality reduction
if(isequal(tril(G), triu(G)))
    % Then its undirected and we assume the path forward is the path back
    % and can just check lower triangle of G leading to huge savings
    [ G, coll_check_results, edge_check_cost, path_edgeid_map ] = remove_redundant_edges( G,coll_check_results, edge_check_cost, path_edgeid_map  );
end

%% Load train test id
load(strcat(set_dataset, 'train_id.mat'), 'train_id');
load(strcat(set_dataset, 'test_id.mat'), 'test_id');

train_world_library_assignment = world_library_assignment(train_id, :);
train_coll_check_results = coll_check_results(train_id, :);

%% Select a policy
option_policy = 10;

switch(option_policy)
    case 1
        policy = policyRandomEdge(path_edgeid_map, size(train_coll_check_results, 2));
    case 2
        policy = policyMaxTallyEdge(path_edgeid_map, size(train_coll_check_results, 2));
    case 3
        policy = policyWeightedProbMaxTallyEdge(path_edgeid_map, train_world_library_assignment, train_coll_check_results, 0.2, true);
    case 4
        policy = policyRandomPathRandomEdge(path_edgeid_map, size(train_coll_check_results, 2));
    case 5
        policy = policyRandomPathMaxTallyEdge(path_edgeid_map, size(train_coll_check_results, 2));
    case 6
        policy = policyMaxProbPathRandomEdge(path_edgeid_map, train_world_library_assignment, train_coll_check_results, 0.01, false);
    case 7
        policy = policyMaxProbPathMaxTallyEdge(path_edgeid_map, train_world_library_assignment, train_coll_check_results, 0.01, true);
    case 8 %not realizable
        policy = policyDRDonevall(train_world_library_assignment, train_coll_check_results, edge_check_cost, path_edgeid_map);
    case 9 % not realizable
        policy = policyIncDRD(train_world_library_assignment, train_coll_check_results, edge_check_cost, path_edgeid_map, 5);
    case 10
        policy = policyDRDBernoulli(path_edgeid_map, edge_check_cost, train_world_library_assignment, train_coll_check_results, 0.01, false, 1);
    case 11
        policy = policyDRDandBern(train_world_library_assignment, train_coll_check_results, edge_check_cost, path_edgeid_map, 0.2, true, 0.25);
    case 12
        policy = policyIncDRDandBern(train_world_library_assignment, train_coll_check_results, edge_check_cost, 5, path_edgeid_map, 0.01, false, 0.2);
    case 13
        load(strcat(set_dataset, 'saved_decision_trees/drd_decision_tree_data.mat'), 'decision_tree_data');
        policy = policyDecisionTreeandBern(decision_tree_data, path_edgeid_map, edge_check_cost, 0.01, false, 0.2);
end

%% Perform stuff
test_world = test_id(17); %just a random world picked from test set with a guarantee that it has a path feasible

% 2d visualization
load(strcat(env_dataset, 'world_',num2str(test_world),'.mat'), 'map');
figure(1);
hold on;
visualize_map(map);

plot_edge_traj_list( edge_traj_list, [0.6 0.6 0.8] );
coord_set = [];
for i = 1:size(edge_traj_list,1)
    coord_set = [coord_set;
        edge_traj_list(i).traj(1,1) edge_traj_list(i).traj(1,2);
        edge_traj_list(i).traj(end,1) edge_traj_list(i).traj(end,2)];
end
scatter(coord_set(:,1), coord_set(:,2),30,'k', 'filled');
axis off;

selected_edge_outcome_matrix = [];
path_id = [];
while (1)
    selected_edge = policy.getEdgeToCheck(); % Call policy to select edge
    if (isempty(selected_edge))
        error('No valid selection made'); % Invalid selection made
    end
    
    outcome = coll_check_results(test_world, selected_edge); %Observe outcome
    fprintf('Selected edge : %d Outcome : %d \n', selected_edge, outcome);
    
    selected_edge_outcome_matrix = [selected_edge_outcome_matrix; selected_edge outcome]; %Update event matrixx
    policy.setOutcome(selected_edge, outcome); %Set outcome to policy
    
    [done, path_id] = any_path_feasible( path_edgeid_map, selected_edge_outcome_matrix );
    
    figure(1);
    sel_edges = get_edge_from_edgeid( selected_edge_outcome_matrix(:,1), G );
    [~, sel_edges_idx] = ismember(sel_edges, id_list);
    for j = 1:length(sel_edges_idx)
        idx = sel_edges_idx(j);
        if (selected_edge_outcome_matrix(j,2))
            col = 'g';
        else
            col = 'r';
        end
        plot(edge_traj_list(idx).traj(:,1), edge_traj_list(idx).traj(:,2), 'Color', col, 'LineWidth', 3);
    end
    pause;
    
    if (done)
        break;
    end
end

% figure(1); cla; plot_map_graph_edge_outcome(map, G, coord_set, selected_edge_outcome_matrix);
% plot_path( path_library{path_id}, coord_set, 'm', 4 );


fprintf('Num edges checked: %d Cost of check: %f \n', size(selected_edge_outcome_matrix, 1), sum(edge_check_cost(selected_edge_outcome_matrix(:,1))));
