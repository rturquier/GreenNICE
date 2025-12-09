# Development file

# %% Include
include("scc.jl")

# %% Set parameters
α = 0.1
θ = 0.5
η = 1.5
γ_list = [0., 1.]
ρ = 0.001

# %% Run
SCC_decomposition_df = get_SCC_decomposition(η, θ, α, γ_list, ρ)

# %% Plot
decomposition_plot = plot_SCC_decomposition(SCC_decomposition_df)
