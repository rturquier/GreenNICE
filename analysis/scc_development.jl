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


# %% --- Invetigating the role of γ
# %% Get SCC prepared_df for two values of γ
γ_0 = 0.
γ_1 = 1.

mm_0 = set_up_marginal_model(η, θ, α, γ_0, pulse_year, pulse_size)
run(mm_0)

γ_0_test_df = @chain begin
    get_model_data(mm_0, pulse_year)
    prepare_df_for_SCC(_, η, θ, α)
end

mm_1 = set_up_marginal_model(η, θ, α, γ_1, pulse_year, pulse_size)
run(mm_1)

γ_1_test_df = @chain begin
    get_model_data(mm_1, pulse_year)
    prepare_df_for_SCC(_, η, θ, α)
end

# %% Compare discount factors
B_0 = @chain γ_0_test_df begin
    @group_by(year)
    @summarize(B_0 = unique(B))
end
B_1 = @chain γ_1_test_df begin
    @group_by(year)
    @summarize(B_1 = unique(B))
end

B_comparison_df = @chain begin
    @left_join(B_0, B_1)
    @mutate(B_relative_difference = B_1 / B_0 - 1)
end

# %% Compare undiscounted SCC
total_cost_of_consumption_damages_0 = @eval @chain $γ_0_test_df begin
    @group_by(year)
    @summarize(
        t = unique(t),
        ∂_cW_global_average = unique(∂_cW_global_average),
        cost_of_damages_to_c = sum(a .* marginal_damage_to_c),
    )
    @filter(t >= 0)
    @summarize(
        total_cost_of_damages_to_c = sum(cost_of_damages_to_c),
    )
    @pull(total_cost_of_damages_to_c)
end
total_cost_of_consumption_damages_1 = @eval @chain $γ_1_test_df begin
    @group_by(year)
    @summarize(
        t = unique(t),
        ∂_cW_global_average = unique(∂_cW_global_average),
        cost_of_damages_to_c = sum(a .* marginal_damage_to_c),
    )
    @filter(t >= 0)
    @summarize(
        total_cost_of_damages_to_c = sum(cost_of_damages_to_c),
    )
    @pull(total_cost_of_damages_to_c)
end

total_cost_of_consumption_damages_1 - total_cost_of_consumption_damages_0

# %% Let's compare the two dataframes directly
@select(γ_1_test_df, c:B) .- @select(γ_0_test_df, c:B)
