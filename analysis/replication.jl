# %% Activate environment, install packages and precompile project
using Pkg
using DataFrames

Pkg.activate(joinpath(@__DIR__, ".."))
Pkg.instantiate()

# %% Include
include("scc.jl")
include("descriptives.jl")

# %% Get descriptive figures
descriptives_df = get_descriptives_df()

initial_E_stock_map = map_E_percapita_country(descriptives_df)
Gini_E_stock0_scatterplot = plot_gini_E_stock0(descriptives_df)
ξ_map = map_damage_coefficient_country(descriptives_df)

# %% Save figures
save("outputs/maps/initial_E_stock_percapita.svg", initial_E_stock_map)
save("outputs/figures/gini_E_stock0.svg", Gini_E_stock0_scatterplot)
save("outputs/figures/initial_damage_coefficient_map.svg", ξ_map)


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

# ==== Map interaction effect at country levels ====
# %% Get data
γ_list = [0.0, 1.0]
country_interaction_df = get_SCC_interaction(η, θ, α, γ_list, ρ)

# %% Absolute interaction map
absolute_interaction_map = map_SCC_decomposition_level(country_interaction_df)
save("outputs/maps/map_interaction_effect_pct.svg", absolute_interaction_map)

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

# ==== Facet plot ====
# %% Set default η × θ grid
η_list = [0.1, 1.05, 2.]
θ_list = [-1.5, -0.5, 0.5]
γ_list = [0., 0.5, 1.]

# %% Plot temperature trajectory in a default run
m = GreenNICE.create()
run(m)
warming_df = getdataframe(m, :damages => :temp_anomaly)
warming_df |> @vlplot(:line, :time, :temp_anomaly)

# %% Run model on parameter grid (this can take a long time) and save results
facet_df = get_SCC_decomposition(η_list, θ_list, α, γ_list, ρ)
write_csv(facet_df, "outputs/facet_df.csv")

# %% Read
facet_df = read_csv("outputs/facet_df.csv")

# %% Facet plot
facet_SCC(facet_df; cost_to="E")
