using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
#Pkg.resolve() # To resolve inconsistencies between Manifest.toml and Project.toml
Pkg.instantiate()

# Load required Julia packages.
using Mimi, MimiFAIRv2, DataFrames, CSVFiles, Plots, VegaLite

include("../src/GreenNICE.jl")
include("scc.jl")

η = 1.5
θ = 0.5
α = 0.1
γ = 1.0
ρ = 0.01
γ_list = [0.0, 1.0]
pulse_year = 2025
pulse_size = 1.0 # GtCO2


## Make figures showing interaction effect at country and region levels

interaction_country = get_SCC_interaction(η, θ, α, γ_list, ρ; level_analysis="country")
interaction_rwpp = get_SCC_interaction(η, θ, α, γ_list, ρ; level_analysis="region")

map_level_country = map_SCC_decomposition_level(interaction_country)
map_pct_country = map_SCC_decomposition_pct(interaction_country)

map_level_rwpp = map_SCC_decomposition_level(interaction_rwpp)
map_pct_rwpp = map_SCC_decomposition_pct(interaction_rwpp)
