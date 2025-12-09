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
γ = 1.0
ρ = 0.01
γ_list = [0.0, 1.0]

# ==== Map interaction effect at country and region levels ====
# %% Get data
country_interaction_df = get_SCC_interaction(η, θ, α, γ_list, ρ)

# %% Absolute interaction map
absolute_interaction_map = map_SCC_decomposition_level(country_interaction_df)

# %% Relative interaction map
relative_interaction_map = map_SCC_decomposition_pct(country_interaction_df)
