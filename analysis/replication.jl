# %% Activate environment, install packages and precompile project
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
Pkg.instantiate()

# %% Include
include("scc.jl")
include("descriptives.jl")

# %% Get descriptive figures
descriptives_df = get_descriptives_df()

initial_E_flow_map = map_E_percapita_country(descriptives_df)
Gini_E_flow0_scatterplot = plot_gini_E_stock0(descriptives_df)
ξ_map = map_damage_coefficient_country(descriptives_df)

# %% Save figures
save("outputs/maps/initial_E_flow_percapita.svg", initial_E_flow_map)
save("outputs/figures/gini_E_flow0.svg", Gini_E_flow0_scatterplot)
save("outputs/maps/initial_damage_coefficient_map.svg", ξ_map)

# %% Get descriptive values
top3_E_flow_percapita = first(sort(descriptives_df, :E_flow0_percapita, rev=true), 3)
bottom4_E_flow_percapita = first(sort(descriptives_df, :E_flow0_percapita,
                                        rev=false), 4)
top3_ξ = first(sort(descriptives_df, :ξ, rev=true), 3)
bottom3_ξ = first(sort(descriptives_df, :ξ, rev=false), 3)

# %% Set default parameters
η = 1.5
θ = 0.5
α = 0.1
ρ = 0.001
γ_list = [0., 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.75, 0.80, 0.85, 0.90, 0.95, 0.975, 1.]

# %% Get SCC decomposition and save results
SCC_decomposition_df = get_SCC_decomposition(η, θ, α, γ_list, ρ)
write_csv(SCC_decomposition_df, "outputs/SCC_decomposition.csv")

# %% Plot SCC decomposition
SCC_decomposition_df = read_csv("outputs/SCC_decomposition.csv")
decomposition_plot = plot_SCC_decomposition(SCC_decomposition_df)
decomposition_plot |> save("outputs/figures/SCC_decomposition.svg")

# ==== Calculate interaction effect ====
# %% Get data
country_interaction_df = get_SCC_interaction(η, θ, α, [0.0, 1.0], ρ)
decomposition_BAU = @filter(SCC_decomposition_df, γ == 1.)

# %% Calculate SCC
SCC_c = decomposition_BAU.present_cost_of_damages_to_c
SCC_E = decomposition_BAU.present_cost_of_damages_to_E
SCC = SCC_c + SCC_E

# %% Calculate interaction effect (absolute and relative)
I_abs_interaction = sum(country_interaction_df.interaction)
I_rel_interaction = I_abs_interaction ./ SCC_E * 100

# ==== Map interaction effect at country levels ====
# %% Absolute interaction map
absolute_interaction_map = map_SCC_decomposition_level(country_interaction_df)
save("outputs/maps/map_interaction_effect_abs.svg", absolute_interaction_map)

# %%% Identify countries with highest and lowest interaction effects
top3_abs_interaction = first(sort(country_interaction_df, :interaction, rev=true), 3)
bottom3_abs_interaction = first(sort(country_interaction_df, :interaction, rev=false), 3)

# %% Relative interaction map
relative_interaction_map = map_SCC_decomposition_pct(country_interaction_df)
save("outputs/maps/map_interaction_effect_pct.svg", relative_interaction_map)

# %%% Identify countries with highest and lowest relative interaction effects
top3_rel_interaction = first(sort(country_interaction_df, :interaction_pct, rev=true), 3)
bottom3_rel_interaction = first(sort(country_interaction_df, :interaction_pct, rev=false),
                                3)
# ==== Descriptive information on the default run ====
# %% Default run
m = GreenNICE.create()
run(m)

# %% Plot temperature trajectory in a default run
temperature_plot = plot_temperature_trajectory(m)
temperature_plot |> save("outputs/figures/temperature.svg")

# %% Plot global flow of ecosystem services in default run
E_flow_df = @chain begin
    getdataframe(m, :environment => :E_flow_global)
    @mutate(E_flow_global = E_flow_global * 10^6)  # convert million USD to USD
end
E_flow_df |> @vlplot(:line, :time, {:E_flow_global, scale={zero=false}})

# ==== Facet plot ====
# %% Set η × θ grid
η_list = [1, 1.5, 2]
θ_list = [-1, -0.25, 0.5]

# %% Run model on parameter grid (this can take a long time) and save results
facet_df = get_SCC_decomposition(η_list, θ_list, α, γ_list, ρ)
write_csv(facet_df, "outputs/facet_df.csv")

# %% Read
facet_df = read_csv("outputs/facet_df.csv")

# %% Facet plot
facet_plot = facet_SCC(facet_df; cost_to="E")
facet_plot |> save("outputs/figures/facetted_SCC_decomposition.svg")

# ====  Sensitivity to E =====
# %% Get the annual flow of material forest ecosystem services from Costanza et al. (2014)
costanza_forest_values = get_costanza_forest_values()

# %% Convert total value of ecosystem services to 2017 USD
total_costanza_estimate_2007 = 124.8 * 10^12
total_costanza_estimate = adjust_for_inflation(total_costanza_estimate_2007, 2007, 2017)

# %% Compare CWON calibration of E to Costanza values
baseline_E = (@chain E_flow_df @filter(time == 2020) @pull(E_flow_global)) |> only
costanza_E_water_food_recreation = costanza_forest_values[1, :water_food_recreation]

costanza_forests_multiplier = costanza_E_water_food_recreation / baseline_E
costanza_total_multiplier = total_costanza_estimate / baseline_E

# %% Set list of E multipliers (x-axis in SCC_E vs E plots)
E_multiplier_list = [0.5 (1:25)...] |> vec

# %% Get SCC for different E multipliers to check sensitivity, and save results
SCC_vs_E_df = get_SCC_vs_E(E_multiplier_list, η, θ, α, ρ)
write_csv(SCC_vs_E_df, "outputs/SCC_vs_E.csv")

# %% Read and plot
SCC_vs_E_df = read_csv("outputs/SCC_vs_E.csv")

SCC_E_vs_E_plot = plot_SCC_vs_E(SCC_vs_E_df; cost_to="E")
SCC_E_vs_E_plot |> save("outputs/figures/SCC_E_vs_E.svg")

SCC_c_vs_E_plot = plot_SCC_vs_E(SCC_vs_E_df; cost_to="c")
SCC_c_vs_E_plot |> save("outputs/figures/SCC_c_vs_E.svg")

# %% Plot E trajectory in a high-E run
high_E_m = GreenNICE.create(; parameters=Dict(:E_multiplier => 5))
run(high_E_m)
high_E_flow_df = getdataframe(high_E_m, :environment => :E_flow_global)
high_E_flow_df |>
    @vlplot(:line, :time, {:E_flow_global, scale={zero=false}}) |>
    save("outputs/figures/high_E_flow.svg")

# ==== SCC vs θ, facetted by E and η ====
# %%  Set values for x-axis and E facets
θ_axis = [θ for θ in -1:0.025:1]
E_facet_list = [1, costanza_forests_multiplier, costanza_total_multiplier]

# %% Run and save
SCC_vs_E_θ_and_η_df = get_SCC_vs_E_θ_and_η(E_facet_list, η_list, θ_axis, α, ρ)
write_csv(SCC_vs_E_θ_and_η_df, "outputs/SCC_vs_E_θ_and_η.csv")

# %% Read
SCC_vs_E_θ_and_η_df = read_csv("outputs/SCC_vs_E_θ_and_η.csv")

# %% Plot
SCC_vs_θ_facetted_by_E_and_η = plot_SCC_vs_θ_facetted_by_E_and_η(SCC_vs_E_θ_and_η_df)
SCC_vs_θ_facetted_by_E_and_η |> save("outputs/figures/SCC_vs_θ_facetted_by_E_and_η.svg")
