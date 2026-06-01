# %% Activate environment, install packages and precompile project
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
Pkg.instantiate()

# %% Include
include("scc.jl")
include("descriptives.jl")

# ==== Descriptive information on the default run ====
# %% Set default parameters
η = 1.5
θ = 0.43
α = 0.1
ρ = 0.001

# %% Default run
m = GreenNICE.create(; parameters = Dict(:η => η, :θ => θ, :α => α))
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

# %% Get initial value of global E
intial_global_E = E_flow_df.E_flow_global |> first

# %% Get descriptive figures
descriptives_df = get_descriptives_df(m)

initial_E_flow_map = map_E_percapita_country(descriptives_df)
Gini_E_flow0_scatterplot = plot_gini_vs_E_flow_0(descriptives_df)
ξ_map = map_damage_coefficient_country(descriptives_df)

# %% Save figures
save("outputs/maps/initial_E_flow_percapita.svg", initial_E_flow_map)
save("outputs/figures/gini_E_flow0.svg", Gini_E_flow0_scatterplot)
save("outputs/maps/initial_damage_coefficient_map.svg", ξ_map)

# %% Get descriptive values
top3_E_flow_percapita = @chain descriptives_df @arrange(desc(E_flow0_percapita)) first(3)
bottom4_E_flow_percapita = @chain descriptives_df @arrange(desc(E_flow0_percapita)) last(4)

top3_ξ = @chain descriptives_df @arrange(desc(ξ)) first(3)
bottom3_ξ = @chain descriptives_df @arrange(desc(ξ)) last(3)

# ==== Simulations ====
# %% Get SCC decomposition and save results
γ_list = [0., 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.75, 0.80, 0.85, 0.90, 0.95, 0.975, 1.]
SCC_decomposition_df = get_SCC_decomposition(η, θ, α, γ_list, ρ)
write_csv(SCC_decomposition_df, "outputs/SCC_decomposition.csv")

# %% Plot SCC decomposition
SCC_decomposition_df = read_csv("outputs/SCC_decomposition.csv")
decomposition_plot = plot_SCC_decomposition(SCC_decomposition_df)
decomposition_plot |> save("outputs/figures/SCC_decomposition.svg")

# %% Plot waterfall decomposition
SCC_E_waterfall_df = @filter(SCC_decomposition_df, γ == 1.)
waterfall_plot = plot_SCC_E_waterfall(SCC_E_waterfall_df)
waterfall_plot |> save("outputs/figures/SCC_E_waterfall.svg")

# ----- Calculate interaction effect -----
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

# ----- Map interaction effect at country level -----
# %% Absolute interaction map
absolute_interaction_map = map_SCC_decomposition_level(country_interaction_df)
save("outputs/maps/map_interaction_effect_abs.svg", absolute_interaction_map)

# %%% Identify countries with highest and lowest interaction effects
top3_abs_interaction = @chain country_interaction_df @arrange(desc(interaction)) first(3)
bottom3_abs_interaction = @chain country_interaction_df @arrange(desc(interaction)) last(3)

# %% Relative interaction map
relative_interaction_map = map_SCC_decomposition_pct(country_interaction_df)
save("outputs/maps/map_interaction_effect_pct.svg", relative_interaction_map)

# %%% Identify countries with highest and lowest relative interaction effects
rel_interaction_sorted_df = @arrange(country_interaction_df, desc(interaction_pct))
top3_rel_interaction = @chain rel_interaction_sorted_df first(3)
bottom3_rel_interaction = @chain rel_interaction_sorted_df last(3)

# ----- Heatmap -----
# %% Set η × θ grid
η_list = 0:0.1:2
θ_list = -1:0.1:1

# %% Run model on parameter grid (this can take a long time) and save results
heatmap_df = get_SCC_decomposition(η_list, θ_list, α, [0, 1], ρ)
write_csv(heatmap_df, "outputs/heatmap_df.csv")

# %% Read
heatmap_simulations_df = read_csv("outputs/heatmap_df.csv")

# %% Prepare
heatmap_df = prepare_heatmap_df(heatmap_simulations_df)

# %% Plot main heatmap
Δ_SCC_E_vs_SCC_E_heatmap = plot_SCC_heatmap(heatmap_df; cost_to="E", relative_to="SCC_E")
Δ_SCC_E_vs_SCC_E_heatmap |> save("outputs/figures/Delta_SCC_E_vs_SCC_E_heatmap.svg")
add_svg_rectangle!("Delta_SCC_E_vs_SCC_E_heatmap.svg")

# %% Plot additional heatmaps for the appendix
Δ_SCC_E_heatmap = plot_SCC_heatmap(heatmap_df; cost_to="E", relative_to=nothing)
Δ_SCC_E_heatmap |> save("outputs/figures/Delta_SCC_E_heatmap.svg")
add_svg_rectangle!("Delta_SCC_E_heatmap.svg")

SCC_E_heatmap = plot_SCC_heatmap(heatmap_df; variable_to_plot="SCC_E_1")
SCC_E_heatmap |> save("outputs/figures/SCC_E_heatmap.svg")

# -----  Sensitivity to E -----
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
E_multiplier_list = [
    1
    costanza_forests_multiplier
    50
    (100:50:550)...
    costanza_total_multiplier
]

# %% Get SCC for different E multipliers to check sensitivity, and save results
SCC_vs_E_df = get_SCC_vs_E(E_multiplier_list, η, θ, α, ρ)
write_csv(SCC_vs_E_df, "outputs/SCC_vs_E.csv")

# %% Read
SCC_vs_E_df = read_csv("outputs/SCC_vs_E.csv")

# %% Plot SCC_E vs E
vertical_rules = (
    vertical_rule(
        costanza_forests_multiplier, 0, 8.8, ["Costanza et al.", "(restricted)"], 2, 10
    )
    +
    vertical_rule(
        costanza_total_multiplier, 6.8, 10.5, ["Costanza et al." ,"(total)"], 0, 65
    )
    +
    vertical_rule(costanza_total_multiplier, 0, 4.8)
)
SCC_E_vs_E_plot = plot_SCC_vs_E(SCC_vs_E_df; cost_to="E", intermediate_layer=vertical_rules)
SCC_E_vs_E_plot |> save("outputs/figures/SCC_E_vs_E.svg")

# %% Plot SCC_c vs E
SCC_c_vs_E_plot = plot_SCC_vs_E(SCC_vs_E_df; cost_to="c")
SCC_c_vs_E_plot |> save("outputs/figures/SCC_c_vs_E.svg")

# %% Plot relative I vs E
SCC_rel_I_vs_E_plot = plot_relative_I_vs_E(SCC_vs_E_df)
SCC_rel_I_vs_E_plot |> save("outputs/figures/relative_I_vs_E.svg")

# %% Plot shares of SCC_E components vs E
SCC_E_shares_sensitivity_plot = plot_SCC_E_shares_sensitivity(SCC_vs_E_df)
SCC_E_shares_sensitivity_plot |> save("outputs/figures/SCC_E_shares_sensitivity.svg")
