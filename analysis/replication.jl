using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
#Pkg.resolve() # To resolve inconsistencies between Manifest.toml and Project.toml
Pkg.instantiate()

include("../src/GreenNICE.jl")
include("scc.jl")

η = 1.5
θ = 0.5
α = 0.1
γ = 1.0
ρ = 0.01
γ_list = [0.0, 1.0]
pulse_year = 2025
pulse_size = 1.0 # ton CO2


## Make figures showing interaction effect at country and region levels

country_interaction_df = get_SCC_interaction(η, θ, α, γ_list, ρ)

absolute_interaction_map = map_SCC_decomposition_level(country_interaction_df)
relative_interaction_map = map_SCC_decomposition_pct(country_interaction_df)
