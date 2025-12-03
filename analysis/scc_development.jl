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

# %% Plot consumption SCC
function plot_consumption_SCC(df::DataFrame)::VegaLite.VLSpec
    plot = df |> @vlplot(
        :line,
        x="γ:q",
        y="present_cost_of_damages_to_c:q",
    )
    return plot
end

plot_consumption_SCC(SCC_decomposition_df)

# %% Plot environment SCC
function plot_environment_SCC(df::DataFrame)::VegaLite.VLSpec
    plot = df |> @vlplot(
        :line,
        x="γ:q",
        y="present_cost_of_damages_to_E:q",
    )
    return plot
end

plot_environment_SCC(SCC_decomposition_df)

# %% get SCC decomposition for a θ × η grid
function get_SCC_decomposition(
    η_list::Vector, θ_list::Vector, α::Real, γ_list::Vector, ρ::Real; kwargs...
)::DataFrame
    η_θ_grid = Base.product(η_list, θ_list) |> collect |> vec
    df_list = [get_SCC_decomposition(η, θ, α, γ_list, ρ) for (η, θ) in η_θ_grid]
    concatenated_df = reduce(vcat, df_list)
    return concatenated_df
end

# %% Run
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

# %% Change abatement rate to stay under +2°C
paris_target_abatement_rate = 0.8
new_μ_input_matrix = m[:abatement, :μ_input] .+ paris_target_abatement_rate
update_param!(m, :abatement, :μ_input, new_μ_input_matrix)

# %% Re-run model and get new warming value
run(m)

warming_df = getdataframe(m, :damages => :temp_anomaly)
warming_in_2100 = @filter(warming_df, time == 2100).temp_anomaly[1]
