include("scc.jl")

# %% Set default parameters
α = 0.1
ρ = 0.001

# %% Set η × θ grid
η_list = 0:0.1:2
θ_list = -1:0.1:1

# %% Run model on parameter grid and save results
heatmap_df = get_SCC_decomposition(η_list, θ_list, α, [0, 1], ρ)
write_csv(heatmap_df, "outputs/heatmap_df.csv")
