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
pulse_year = 2021
pulse_size = 1.

mm_0 = set_up_marginal_model(η, θ, α, γ_0, pulse_year, pulse_size)
mm_1 = set_up_marginal_model(η, θ, α, γ_1, pulse_year, pulse_size)

run(mm_0)
run(mm_1)

γ_0_test_df = @chain begin
    get_model_data(mm_0, pulse_year)
    prepare_df_for_SCC(_, η, θ, α, ρ)
end
γ_1_test_df = @chain begin
    get_model_data(mm_1, pulse_year)
    prepare_df_for_SCC(_, η, θ, α, ρ)
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

# %% Check that the average equity weight is 1
function average_equity_weight_is_1(df)
    average_weight_is_1 = @chain df begin
        @group_by(year)
        @summarize(average_weight_is_1 = sum(a) / sum(l) ≈ 1.)
        @pull(average_weight_is_1)
    end

    average_weight_is_always_1 = (&)(average_weight_is_1...)
    return average_weight_is_always_1
end

average_equity_weight_is_1(γ_0_test_df) & average_equity_weight_is_1(γ_1_test_df)

# %% Check that equity weights shift towards poorer deciles
average_equity_weight_2030_γ_0 = @chain begin
    γ_0_test_df
    @group_by(year, quantile)
    @summarize(a = sum(a) / sum(l))
    @ungroup
    @filter(year == 2030)
end

average_equity_weight_2030_γ_1 = @chain begin
    γ_1_test_df
    @group_by(year, quantile)
    @summarize(a = sum(a) / sum(l))
    @ungroup
    @filter(year == 2030)
end

# --> equity weights shift towards poorer deciles when γ goes from 0 to 1

# %% Check that average marginal damages don't change at the country level
average_damages_γ_0_df = @chain γ_0_test_df begin
    @group_by(year, country)
    @summarize(
        l_γ_0 = sum(l),
        average_damages_to_c_γ_0 = mean(marginal_damage_to_c),
    )
    @ungroup()
end
average_damages_γ_1_df = @chain γ_1_test_df begin
    @group_by(year, country)
    @summarize(
        l_γ_1 = sum(l),
        average_damages_to_c_γ_1 = mean(marginal_damage_to_c),
    )
    @ungroup()
end

average_damages_df = @left_join(average_damages_γ_0_df, average_damages_γ_1_df)

@chain average_damages_df begin
    @filter(year == 2030)
    @mutate(relative_difference = average_damages_to_c_γ_0 / average_damages_to_c_γ_1 - 1)
end

# --> relative difference is around 0.01%. Seems small enough.

# %% Look at SCC, equity weights and unweighted damages by decile
function apply_SCC_formula_by_quantile(df::DataFrame)::DataFrame
    SCC_by_quantile_df = @chain df begin
        @group_by(quantile, year)
        @summarize(
            t = unique(t),
            B = unique(B),
            ∂_cW_global_average = unique(∂_cW_global_average),
            cost_of_damages_to_c = sum(a * marginal_damage_to_c),
            cost_of_damages_to_E = sum(a * p * marginal_damage_to_E),
            a = sum(a),
            c = mean(c),
            damages_to_c = sum(marginal_damage_to_c),
        )
        @filter(t >= 0)
        @summarize(
            present_cost_of_damages_to_c = sum(B * cost_of_damages_to_c),
            present_cost_of_damages_to_E = sum(B * cost_of_damages_to_E),
            mean_a = mean(a),
            mean_c = mean(c),
            present_damages_to_c = sum(B * damages_to_c),
        )
    end
    return SCC_by_quantile_df
end

γ_0_quantile_df = apply_SCC_formula_by_quantile(γ_0_test_df)
γ_1_quantile_df = apply_SCC_formula_by_quantile(γ_1_test_df)

@select(γ_1_quantile_df, 2:6) .- @select(γ_0_quantile_df, 2:6)

sum(γ_0_quantile_df.present_cost_of_damages_to_c)
sum(γ_1_quantile_df.present_cost_of_damages_to_c)

# --> the equity weights increase a lot for the three bottom deciles,
# and become smaller for the top 70%. This dominates the slight increase
# in damages to the top deciles (elasticity of 0.6).

# %% Apply initial SCC formula and check that results are the same
function apply_two_SCC_formulas_by_quantile(df)
    @eval @chain $df begin
        @group_by(quantile, year)
            @summarize(
                t = unique(t),
                B = unique(B),
                ∂_cW_global_average = unique(∂_cW_global_average),
                welfare_cost_to_c = sum(∂_cW * marginal_damage_to_c),
                welfare_cost_to_E = sum(∂_cE * marginal_damage_to_E),
                weighted_cost_to_c = sum(a * marginal_damage_to_c),
                weighted_cost_to_E = sum(a * p * marginal_damage_to_E),
                ∂_cW = mean(∂_cW),
                a = sum(a) / sum(l),
                c = sum(c),
                damages_to_c = sum(marginal_damage_to_c),
            )
            @filter(t >= 0)
            @mutate(β = 1 / (1 + $ρ))
            @summarize(
                present_welfare_cost_to_c = sum(β^t * welfare_cost_to_c),
                present_welfare_cost_to_E = sum(β^t * welfare_cost_to_E),
                present_weighted_cost_to_c = sum(B * weighted_cost_to_c),
                present_weighted_cost_to_E = sum(B * weighted_cost_to_E),
                mean_a = mean(a),
                mean_∂_cW = mean(∂_cW),
                c = sum(c),
                discounted_damages_to_c = sum(β^t * damages_to_c),
            )
    end
end

γ_0_quantile_df = apply_two_SCC_formulas_by_quantile(γ_0_test_df)
γ_1_quantile_df = apply_two_SCC_formulas_by_quantile(γ_1_test_df)

∂_cW_global_average_present_γ_0 = @filter(γ_0_test_df, t==0).∂_cW_global_average[1]
∂_cW_global_average_present_γ_1 = @filter(γ_1_test_df, t==0).∂_cW_global_average[1]

@eval @mutate(
    γ_0_quantile_df,
    present_welfare_cost_to_c = present_welfare_cost_to_c / $∂_cW_global_average_present_γ_0
)
@eval @mutate(
    γ_1_quantile_df,
    present_welfare_cost_to_c = present_welfare_cost_to_c / $∂_cW_global_average_present_γ_1
)

# --> The difference comes from the `∂_cW_global_average_present` factor. Because it
# changes with gamma, it breaks comparability between the two scenarios.
# --> We have to normalized by something that doesn't change with gamma, like the marginal
# welfare of average consumption.
