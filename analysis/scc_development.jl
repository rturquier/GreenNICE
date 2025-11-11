# This is a test ground for developing the functions in `scc.jl`.

# %%
include("scc.jl")


# %% Set parameters
η = 1.5
θ = 0.5
α = 0.1
ρ = 0.001
γ_list = [0., 1.]

# %%
test_df = get_SCC_decomposition(η, θ, α, γ_list, ρ)

# %% Plot SCC decomposition
damages_to_E_with_equal_deciles = test_df[
    test_df.γ .== 0, :present_cost_of_damages_to_E
][1]
test_df = @eval @chain $test_df begin
    @mutate(
        interaction = present_cost_of_damages_to_E
                        - $damages_to_E_with_equal_deciles,
        non_interaction = present_cost_of_damages_to_c
                            + $damages_to_E_with_equal_deciles,
    )
end


using VegaLite
plot_df = @pivot_longer(
    test_df, (interaction, non_interaction), names_to="interaction", values_to="SCC_part"
)

plot_df |> @vlplot(:area, x="γ:q", y="SCC_part:q", color="interaction:N")

# %% Compare analytical SCC with EDE decrease in the marginal model
γ = 1.
pulse_year = 2021
pulse_size = 1.
mm = set_up_marginal_model(η, θ, α, γ, pulse_year, pulse_size)
run(mm)

EDE_df = @eval @chain begin
    getdataframe($mm.base, :welfare => :l)
    @mutate(l = l * 10^3)
    @group_by(time)
    @summarise(l = sum(l))
    @right_join(getdataframe($mm, :welfare, :cons_EDE_global))
    @mutate(EDE_difference = -cons_EDE_global * 10^3)
    @mutate(SCC_from_EDE = EDE_difference * l)
    @rename(year = time)
    @filter(year >= $pulse_year)
end
