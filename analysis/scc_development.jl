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

# %% Get SCC decomposition for an η × θ grid
η_list = [0.1, 1.05, 2.]
θ_list = [-1.5, -0.5, 0.5]
γ_list = [0., 0.5, 1.]

scc_df = get_SCC_decomposition(η_list, θ_list, α, γ_list, ρ)

# %% Save
write_csv(scc_df, "outputs/scc_df.csv")

# %% Read
scc_df = read_csv("outputs/scc_df.csv")

# %% Plot
scc_df |> @vlplot(
    :line,
    x="γ:q",
    y="present_cost_of_damages_to_E:q",
    column=:θ,
    row={field=:η, sort={field=:η, order="descending"}},
    resolve={scale={y="independent"}},
)

# %% Plot for consumption
scc_df |> @vlplot(
    :line,
    x="γ:q",
    y="present_cost_of_damages_to_c:q",
    column=:θ,
    row={field=:η, sort={field=:η, order="descending"}},
    resolve={scale={y="independent"}},
)


# ---- Make facet plot with a mitigation coefficient compatible with +2°C objective ---- #
# %% Get temperature in a default run
m = GreenNICE.create()
run(m)

warming_df = getdataframe(m, :damages => :temp_anomaly)
warming_in_2100 = @filter(warming_df, time == 2100).temp_anomaly[1]

warming_df |> @vlplot(:line, :time, :temp_anomaly)


# %% Change abatement rate to stay under +2°C
paris_target_abatement_rate = 0.8
default_μ_input_matrix = (GreenNICE.create() |> Mimi.build)[:abatement, :μ_input]
new_μ_input_matrix = default_μ_input_matrix .+ paris_target_abatement_rate

η_list = [2.]
θ_list = [0.5]
γ_list = [0., 1.]

scc_df = get_SCC_decomposition(
    η_list, θ_list, α, γ_list, ρ;
    additional_parameters=Dict((:abatement, :μ_input) => new_μ_input_matrix)
)

plot_environment_SCC(scc_df)
# update_param!(m, :abatement, :μ_input, new_μ_input_matrix)

# %% Re-run model and get new warming value
m = GreenNICE.create(parameters=Dict((:abatement, :μ_input) => new_μ_input_matrix))
run(m)
warming_df = getdataframe(m, :damages => :temp_anomaly)
warming_in_2100 = @filter(warming_df, time == 2100).temp_anomaly[1]
