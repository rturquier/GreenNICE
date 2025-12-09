# %% Activate environment, install packages and precompile project
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
Pkg.instantiate()

# %% Include
include("scc.jl")

# %% Set default parameters
η = 1.5
θ = 0.5
α = 0.1
ρ = 0.001
γ_list = [0.0, 0.25, 0.5, 0.75, 1.0]

# %% Plot SCC decomposition
SCC_decomposition_df = get_SCC_decomposition(η, θ, α, γ_list, ρ)
decomposition_plot = plot_SCC_decomposition(SCC_decomposition_df)

decomposition_plot |> save("outputs/SCC_decomposition.svg")

# ==== Map interaction effect at country and region levels ====
# %% Get data
γ_list = [0.0, 1.0]
country_interaction_df = get_SCC_interaction(η, θ, α, γ_list, ρ)

# %% Absolute interaction map
absolute_interaction_map = map_SCC_decomposition_level(country_interaction_df)

# %% Relative interaction map
relative_interaction_map = map_SCC_decomposition_pct(country_interaction_df)

# ==== Facet plots ====
# %% Set default η × θ grid
η_list = [0.1, 1.05, 2.]
θ_list = [-1.5, -0.5, 0.5]
γ_list = [0., 0.5, 1.]

# %% Run Business-As-Usual (BAU) model and save outputs
# Takes 30 to 60 minutes
BAU_facet_df = get_SCC_decomposition(η_list, θ_list, α, γ_list, ρ)
write_csv(BAU_facet_df, "outputs/BAU_facet_df.csv")

# %% Get temperature in a default run
m = GreenNICE.create()
run(m)
warming_df = getdataframe(m, :damages => :temp_anomaly)
warming_df |> @vlplot(:line, :time, :temp_anomaly)

# %% Change abatement rate to stay under +2°C (Paris agreement target)
paris_target_abatement_rate = 0.8
default_μ_input_matrix = (GreenNICE.create() |> Mimi.build)[:abatement, :μ_input]
paris_μ_input_matrix = default_μ_input_matrix .+ paris_target_abatement_rate

m = GreenNICE.create(parameters=Dict((:abatement, :μ_input) => paris_μ_input_matrix))
run(m)
paris_warming_df = getdataframe(m, :damages => :temp_anomaly)
paris_warming_df |> @vlplot(:line, :time, :temp_anomaly)

# %% Run model on a Paris agreement warming trajectory and save outputs
# Takes 30 to 60 minutes
paris_facet_df = get_SCC_decomposition(
    η_list, θ_list, α, γ_list, ρ;
    additional_parameters=Dict((:abatement, :μ_input) => paris_μ_input_matrix)
)
write_csv(paris_facet_df, "outputs/paris_facet_df.csv")

# %% Read
BAU_facet_df = read_csv("outputs/BAU_facet_df.csv")
paris_facet_df = read_csv("outputs/paris_facet_df.csv")

# %% BAU facet plot
facet_SCC(BAU_facet_df; cost_to="E")

# %% Facet plot for the 2°C scenario
facet_SCC(paris_facet_df; cost_to="E")
