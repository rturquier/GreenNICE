# %% Activate environment, install packages and precompile project
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
Pkg.instantiate()

# %% Include
include("scc.jl")
include("descriptives.jl")

# %% Get descriptive figures
descriptives_df = get_descriptives_df()

initial_E_stock_map = map_E_percapita_country(descriptives_df)
ξ_map = map_damage_coefficient_country(descriptives_df)
Gini_E_stock0_scatterplot = plot_gini_E_stock0(descriptives_df)

# %% Save figures
save("outputs/figures/maps/initial_E_stock_percapita.svg", initial_E_stock_map)
save("outputs/figures/maps/initial_damage_coefficient_map.svg", ξ_map)
save("outputs/figures/gini_E_stock0.svg", Gini_E_stock0_scatterplot)


# %% Set default parameters
η = 1.5
θ = 0.5
α = 0.1
ρ = 0.001
γ_list = [0.0, 0.25, 0.5, 0.75, 1.0]

# %% Plot SCC decomposition
SCC_decomposition_df = get_SCC_decomposition(η, θ, α, γ_list, ρ)
decomposition_plot = plot_SCC_decomposition(SCC_decomposition_df)

decomposition_plot |> save("outputs/figures/SCC_decomposition.svg")

# ==== Map interaction effect at country and region levels ====
# %% Get data
γ_list = [0.0, 1.0]
country_interaction_df = get_SCC_interaction(η, θ, α, γ_list, ρ)

# %% Absolute interaction map
absolute_interaction_map = map_SCC_decomposition_level(country_interaction_df)
save("outputs/maps/map_interaction_effect_pct.svg", absolute_interaction_map)

# %% Relative interaction map
relative_interaction_map = map_SCC_decomposition_pct(country_interaction_df)
save("outputs/maps/map_interaction_effect_pct.svg", relative_interaction_map)

# ==== Descriptive information on the default run ====
# %% Default run
m = GreenNICE.create()
run(m)

# %% Plot temperature trajectory in a default run
warming_df = getdataframe(m, :damages => :temp_anomaly)
warming_df |> @vlplot(:line, :time, :temp_anomaly)

# %% Plot global flow of ecosystem services in default run
E_flow_df = getdataframe(m, :environment => :E_flow_global)
E_flow_df |> @vlplot(:line, :time, :E_flow_global)

# ==== Facet plot ====
# %% Set default η × θ grid
η_list = [0.1, 1.05, 2.]
θ_list = [-1.5, -0.5, 0.5]
γ_list = [0., 0.5, 1.]

# %% Run model on parameter grid (this can take a long time) and save results
facet_df = get_SCC_decomposition(η_list, θ_list, α, γ_list, ρ)
write_csv(facet_df, "outputs/facet_df.csv")

# %% Read
facet_df = read_csv("outputs/facet_df.csv")

# %% Facet plot
facet_plot = facet_SCC(facet_df; cost_to="E")
facet_plot |> save("outputs/figures/facetted_SCC_decomposition.svg")

# ====  Sensitivity to E
# %% Get the annual flow of material forest ecosystem services from Costanza et al. (2014)
costanza_forest_values = get_costanza_forest_values()

# %% Convert total value of ecosystem services to 2017 USD
total_costanza_estimate = 124.8 * 10^12
adjust_for_inflation(total_costanza_estimate, 2007, 2017)

# %% Run model with different E multipliers to check sensitivity, and save results
E_multiplier_list = [0.5, 1, 2, 3, 4, 5]

sensitivity_to_E_df = check_sensitivity_to_E(E_multiplier_list, η, θ, α, ρ)
write_csv(sensitivity_to_E_df, "outputs/sensitivity_to_E.csv")

# %% Read and plot
sensitivity_to_E_df = read_csv("outputs/sensitivity_to_E.csv")
sensitivity_to_E_plot = plot_sensitivity_to_E(sensitivity_to_E_df)
sensitivity_to_E_plot |> save("outputs/figures/sensitivity_to_E.svg")
