include("shared_packages.jl")

using XLSX  # to read Costanza et al. (2014) table S1
using HTTP  # to get CPI data
using JSON  # to get CPI data

include("../src/components/welfare.jl")


function set_up_marginal_model(
    η::Real,
    θ::Real,
    α::Real,
    γ::Real,
    pulse_year::Int,
    pulse_size::Real,
    additional_parameters::Dict=Dict()
)::MarginalModel
    main_parameters = Dict(:η => η, :θ => θ, :α => α, (:quantile_recycle, :γ) => γ)
    parameters = merge(main_parameters, additional_parameters)

    m = GreenNICE.create(parameters=parameters)
    mm = create_marginal_model(m, pulse_size)

    years = dim_keys(m, :time)
    n_years = length(years)
    pulse_year_index = findfirst(year -> year == pulse_year, years)
    pulse_series = zeros(n_years)
    pulse_series[pulse_year_index] = pulse_size
    update_param!(mm.modified, :emissions, :co2_pulse, pulse_series)

    return mm
end


function get_model_data(mm::MarginalModel, pulse_year::Int)::DataFrame
    base_df = getdataframe(mm.base, :welfare => (:qcpc_post_recycle, :E_flow_percapita))
    within_equal_consumption_df = getdataframe(mm.base, :quantile_recycle => :CPC_post)
    equal_consumption_df = getdataframe(mm.base, :quantile_recycle => :CPC_post_global)
    equal_E_df = getdataframe(mm.base, :environment => :E_flow_equal)
    population_df = getdataframe(mm.base, :welfare => :l)
    damages_df = @chain begin
        getdataframe(
            mm,
            :welfare => :E_flow_percapita,
            :quantile_recycle => :qcpc_damages,
        )
        # The marginal model gives changes per ton of CO2:
        # `(modified_model_value - base_model_value) / pulse_size`.
        # So marginal *damages* are the additive inverse of the changes in environment.
        @mutate(marginal_damage_to_E = -E_flow_percapita)
        @select(-(E_flow_percapita))
    end

    clean_df = @eval @chain $base_df begin
        @left_join($within_equal_consumption_df)
        @left_join($equal_consumption_df)
        @left_join($equal_E_df)
        @left_join($population_df)
        @left_join($damages_df)
        @rename(
            year = time,
            c = qcpc_post_recycle,
            c_within_equal = CPC_post,
            c_across_equal = CPC_post_global,
            E = E_flow_percapita,
            E_equal = E_flow_equal,
            marginal_damage_to_c = qcpc_damages,
        )
        @mutate(
            t = year - $pulse_year, # t = 0 at pulse year. Used later to discount.
            l = l / 10, # population in a decile is a tenth of the country's population
        )
        @relocate(year, t)
        @mutate(
            # convert from thousand dollars and thousand people to dollars and people
            marginal_damage_to_c = marginal_damage_to_c * 10^3,
            marginal_damage_to_E = marginal_damage_to_E * 10^3,
            c = c * 10^3,
            E = E * 10^3,
            c_within_equal = c_within_equal * 10^3,
            c_across_equal = c_across_equal * 10^3,
            E_equal = E_equal * 10^3,
            l = l * 10^3,
        )
    end

    return clean_df
end


@doc raw"""
    marginal_welfare_of_consumption(c, E, l, η, θ, α)

First derivative of welfare with respect to consumption.

```math
\partial_{c_i} W  =
    l_i
    \cdot (1 - \alpha) c_i^{\theta - 1}
    \cdot v(c_i, E_i)^{1 - \eta - \theta}
```
"""
function marginal_welfare_of_consumption(c, E, l, η, θ, α)
    return l * (1 - α) * c^(θ - 1) * v(c, E, θ, α)^(1 - η - θ)
end


@doc raw"""
    marginal_welfare_of_environment(c, E, l, η, θ, α)

First derivative of welfare with respect to environment.

```math
\partial_{E_i} W  =
    l_i
    \cdot \alpha E_i^{\theta - 1}
    \cdot v(c_i, E_i)^{1 - \eta - \theta}
```
"""
function marginal_welfare_of_environment(c, E, l, η, θ, α)
    return l * α * E^(θ - 1) * v(c, E, θ, α)^(1 - η - θ)
end


function get_marginal_utility_at_present_average(df::DataFrame, η::Real, θ::Real, α::Real)
        present_average_df = @chain df begin
        @filter(t == 0)
        @mutate(sum_c = c.* l, sum_E = E.*l)
        @summarize(
            c = sum(sum_c) / sum(l),
            E = sum(sum_E) / sum(l),
        )
    end
    present_average_c = present_average_df.c[1]
    present_average_E = present_average_df.E[1]
    marginal_utility_at_present_average = marginal_welfare_of_consumption(
        present_average_c, present_average_E, 1, η, θ, α
    )
    return marginal_utility_at_present_average
end


function prepare_df_for_SCC(df::DataFrame, η::Real, θ::Real, α::Real)::DataFrame
    prepared_df = @eval @chain $df begin
        @mutate(
            ∂_cW = marginal_welfare_of_consumption(c, E, l, $η, $θ, $α),
            ∂_EW = marginal_welfare_of_environment(c, E, l, $η, $θ, $α),
            ∂_cW_within_equal = marginal_welfare_of_consumption(c_within_equal,
                                                                E,
                                                                l,
                                                                $η,
                                                                $θ,
                                                                $α),
            ∂_EW_within_equal = marginal_welfare_of_environment(c_within_equal,
                                                                E,
                                                                l,
                                                                $η,
                                                                $θ,
                                                                $α),
            ∂_cW_across_equal = marginal_welfare_of_consumption(c_across_equal,
                                                                E,
                                                                l,
                                                                $η,
                                                                $θ,
                                                                $α),
            ∂_EW_across_equal = marginal_welfare_of_environment(c_across_equal,
                                                                E,
                                                                l,
                                                                $η,
                                                                $θ,
                                                                $α),
            ∂_cW_E_equal = marginal_welfare_of_consumption(c_across_equal,
                                                            E_equal,
                                                            l,
                                                            $η,
                                                            $θ,
                                                            $α),
            ∂_EW_E_equal = marginal_welfare_of_environment(c_across_equal,
                                                            E_equal,
                                                            l,
                                                            $η,
                                                            $θ,
                                                            $α),
        )
    end
    return prepared_df
end


@doc raw"""
    apply_SCC_decomposition_formula(
        prepared_df::DataFrame, reference_marginal_utility::Real, ρ::Real;
        analysis_level::String="global"
    )::DataFrame

Get present value of equity-weighted, money-metric damages to `c` and `E`.

The social cost of carbon (SCC) is equal to the sum of the present cost of marginal
damages to consumption `c`, and to environment `E`:
```math
    \sum_t \beta^t \sum_{i,j} \partial_{c_{i,j,t}}{W_t} \cdot (-\partial_{e_0} c_{i,j,t})
+ \sum_t \beta^t \sum_{i,j} \partial_{E_{i,j,t}}{W_t} \cdot (-\partial_{e_0} E_{i,j,t}).
```

Marginal damages to consumption ``\frac{dc_i}{de}`` are called `marginal_damage_to_c` in
the dataframe, and marginal damages to the environment, ``\frac{dE_i}{de}``, are coded
as `marginal_damage_to_E`.

analysis_level == "global" computes the SCC decomposition at the global level, while
analysis_level == "country" computes the SCC decomposition at the country level.

Alternative scenarios are i) No within country inequality ("within_equal"),
ii) No across country inequality ("across_equal") and iii) No natural capital inequality
("E_equal"). These three scenarios build on top of each other.
"""
function apply_SCC_decomposition_formula(
    prepared_df::DataFrame, reference_marginal_utility::Real, ρ::Real;
    analysis_level::String="global"
)::DataFrame

    β = 1 / (1 + ρ)

    if analysis_level == "country"
        group_columns = [:country, :year]
    else
        group_columns = [:year]
    end

    SCC_df = @eval @chain $prepared_df begin
        @group_by($(group_columns...))
        # Exclude 4 small countries with E = 0 because they have infinite ∂_EW
        @filter(E > 0)
        @summarize(
            t = unique(t),
            welfare_loss_c = sum(∂_cW * marginal_damage_to_c),
            welfare_loss_E = sum(∂_EW * marginal_damage_to_E),
            welfare_loss_c_within_equal = sum(∂_cW_within_equal * marginal_damage_to_c),
            welfare_loss_E_within_equal = sum(∂_EW_within_equal * marginal_damage_to_E),
            welfare_loss_c_across_equal = sum(∂_cW_across_equal * marginal_damage_to_c),
            welfare_loss_E_across_equal = sum(∂_EW_across_equal * marginal_damage_to_E),
            welfare_loss_c_E_equal = sum(∂_cW_E_equal * marginal_damage_to_c),
            welfare_loss_E_E_equal = sum(∂_EW_E_equal * marginal_damage_to_E)
        )
        @filter(t >= 0)
        @summarize(
            present_cost_of_damages_to_c = 1 / $reference_marginal_utility
                                           * sum($β^t * welfare_loss_c),
            present_cost_of_damages_to_E = 1 / $reference_marginal_utility
                                           * sum($β^t * welfare_loss_E),
            present_cost_of_damages_to_c_within_equal = 1 / $reference_marginal_utility
                                            * sum($β^t * welfare_loss_c_within_equal),
            present_cost_of_damages_to_E_within_equal = 1 / $reference_marginal_utility
                                            * sum($β^t * welfare_loss_E_within_equal),
            present_cost_of_damages_to_c_across_equal = 1 / $reference_marginal_utility
                                            * sum($β^t * welfare_loss_c_across_equal),
            present_cost_of_damages_to_E_across_equal = 1 / $reference_marginal_utility
                                            * sum($β^t * welfare_loss_E_across_equal),
            present_cost_of_damages_to_c_E_equal = 1 / $reference_marginal_utility
                                            * sum($β^t * welfare_loss_c_E_equal),
            present_cost_of_damages_to_E_E_equal = 1 / $reference_marginal_utility
                                            * sum($β^t * welfare_loss_E_E_equal),
        )
    end
    return SCC_df
end

"""
    get_SCC_decomposition(
        η::Real, θ::Real, α::Real, γ::Real, ρ::Real;
        analysis_level::String="global",
        pulse_year::Int=2025,
        pulse_size::Real=1.,
        additional_parameters::Dict=Dict()
    )::DataFrame

Get social cost of carbon as damages to consumption and damages to the environment.

Run a version of GreenNICE with the parameters supplied to the function, as well as an
identical model with an additional `pulse_size` tons of CO2 in year `pulse_year`.
Compare consumption and environment between the two models, and compute the present
value of damages analytically.

Return a one-line `Dataframe` with the social cost of carbon (SCC) decomposed in two
columns:
- `present_cost_of_damages_to_c`,
- `present_cost_of_damages_to_E`.

The sum of these two numbers is the SCC. See function `apply_SCC_decomposition_formula`
for mathematical details.

# Arguments
- `η::Real`: inequality aversion (coefficient of relative risk aversion).
- `θ::Real`: substitutability parameter. Accepts value between -∞ and 1.
- `α::Real`: share of `environment` the utility function. Must be in ``[0, 1]``.
- `γ::Real`: within-country inequality parameter. 0 means no within-country inequality.
    1 is the standard calibration.
- `ρ::Real`: rate of pure time preference (utility discount rate).

# Keyword arguments
- `analysis_level::String`: if "global", computes SCC decomposition at the global level,
    if "country", computes SCC decomposition at the country level.
- `pulse_year::Int`: year where the CO2 marginal pulse is emmitted, and year of
    reference for the SCC.
- `pulse_size::Real`: size of the CO2 pulse, in tons.
- `additional_parameters::Dict`: additional parameters to be passed to the model.
"""
function get_SCC_decomposition(
    η::Real, θ::Real, α::Real, γ::Real, ρ::Real;
    analysis_level::String="global",
    pulse_year::Int=2025,
    pulse_size::Real=1.,
    additional_parameters::Dict=Dict()
)::DataFrame
    mm = set_up_marginal_model(η, θ, α, γ, pulse_year, pulse_size, additional_parameters)
    run(mm)
    model_df = get_model_data(mm, pulse_year)

    reference_marginal_utility = get_marginal_utility_at_present_average(model_df, η, θ, α)

    SCC_decomposition_df = @eval @chain begin
        prepare_df_for_SCC($model_df, $η, $θ, $α)
        apply_SCC_decomposition_formula(
            _, $reference_marginal_utility, $ρ;
            analysis_level = $analysis_level
        )
        @mutate(
            η = $η,
            θ = $θ,
            γ = $γ,
        )
        @relocate(η, θ, γ)
    end

    return SCC_decomposition_df
end

"""
    get_SCC_decomposition(
        η::Real, θ::Real, α::Real, γ_list::AbstractVector, ρ::Real; kwargs...
    )::DataFrame

Get SCC decomposition for a vector of γ values.

Apply `get_SCC_decomposition` for each value of γ provided in `γ_list`.
Return a Dataframe with as many rows as values in `γ_list`.
"""
function get_SCC_decomposition(
    η::Real, θ::Real, α::Real, γ_list::AbstractVector, ρ::Real; kwargs...
)::DataFrame
    df_list = [get_SCC_decomposition(η, θ, α, γ, ρ; kwargs...) for γ in γ_list]
    concatenated_df = reduce(vcat, df_list)
    return concatenated_df
end


"""
    get_SCC_decomposition(
        η_list::AbstractVector,
        θ_list::AbstractVector,
        α::Real,
        γ_list::AbstractVector,
        ρ::Real;
        kwargs...
    )::DataFrame

Get SCC decomposition for an η × θ grid.
"""
function get_SCC_decomposition(
    η_list::AbstractVector,
    θ_list::AbstractVector,
    α::Real,
    γ_list::AbstractVector,
    ρ::Real;
    kwargs...
)::DataFrame
    η_θ_grid = Base.product(η_list, θ_list) |> collect |> vec
    df_list = [get_SCC_decomposition(η, θ, α, γ_list, ρ; kwargs...) for (η, θ) in η_θ_grid]
    concatenated_df = reduce(vcat, df_list)
    return concatenated_df
end

function plot_SCC_decomposition(SCC_decomposition_df::DataFrame)::VegaLite.VLSpec
    consumption_plot = SCC_decomposition_df |> @vlplot(
        :line,
        x="γ:q",
        y= {
            "present_cost_of_damages_to_c:q",
            axis = { title = "SCC_c" }
            },
    )
    environment_plot = SCC_decomposition_df |> @vlplot(
        :line,
        x="γ:q",
        y={
            "present_cost_of_damages_to_E:q",
            axis = { title = "SCC_E" }
        },
    )
    combined_plot = hcat(consumption_plot, environment_plot)
    return combined_plot
end

function plot_SCC_E_waterfall(df::DataFrame)::VegaLite.VLSpec

    E_equal = df.present_cost_of_damages_to_E_E_equal[1]
    E_across_equal = df.present_cost_of_damages_to_E_across_equal[1]
    E_within_equal = df.present_cost_of_damages_to_E_within_equal[1]
    E_total = df.present_cost_of_damages_to_E[1]

    label_order = [
        "No Inequality",
        "A",
        "B",
        "C",
        "Total"
    ]

    bar_df = DataFrame(
        label = label_order,
        order = 1:5,
        bar_start = [0.0, E_equal, E_across_equal, E_within_equal, 0.0],
        bar_end = [E_equal, E_across_equal, E_within_equal, E_total, E_total],
        bar_type  = ["base", "increment", "increment", "increment", "total"],
        bar_value = [
            E_equal,
            E_across_equal - E_equal,
            E_within_equal - E_across_equal,
            E_total - E_within_equal,
            E_total
        ]
    )
    bar_df.label_y = (bar_df.bar_start .+ bar_df.bar_end) ./ 2
    bar_df.value_str = string.(round.(bar_df.bar_value, digits=2))
    bar_df.description = ["No Inequality",
                          "A = Unequal E Endowment",
                          "B = Unequal Inter-Regional Consumption",
                          "C = Unequal Intra-Regional Consumption",
                          "Total"]

    base_total_df = bar_df[bar_df.bar_type .!= "increment", :]
    increment_df = bar_df[bar_df.bar_type .== "increment", :]

    connector_df = DataFrame(
        from_label = label_order[1:4],
        from_order = [1, 2, 3, 4],
        to_label = label_order[2:5],
        to_order = [2, 3, 4, 5],
        y_val = [E_equal, E_across_equal, E_within_equal, E_total]
    )

    plot = @vlplot(
        width  = 620,
        height = 320,
        config = {
            view = {stroke = "transparent"},
            background = "white",
            font = "sans-serif",
            axis = {
                gridColor = "#e8e8e8",
                gridWidth = 0.8,
                domainColor = "#cccccc",
                tickColor = "#cccccc",
                labelColor = "#444444",
                titleColor = "#444444",
                labelFontSize = 14,
                titleFontSize = 14
            },
            legend = {
                labelFontSize = 12,
                labelColor = "#444444",
                titleFontSize = 13,
                titleColor = "#444444",
                orient = "bottom",
                direction = "vertical",
                labelLimit = 500,
                symbolSize = 0
            }
        }
    ) +
    @vlplot(
        data = base_total_df,
        mark = {type = :bar, cornerRadiusEnd = 3},
        x = {
            field = :label,
            type  = "nominal",
            scale = {domain = ["No Inequality", "A", "B", "C", "Total"]},
            axis  = {title = "", labelAngle = 0, labelLimit = 220,
                     domain = false, ticks = false, labelPadding = 8}
        },
        y = {
            field = :bar_start,
            type = "quantitative",
            title = "Environmental SCC (\$ per ton CO₂)",
            scale = {zero = true},
            axis = {domain = false, tickCount = 5, grid = true}
        },
        y2 = {field = :bar_end},
        color = {value = "#8B4A6E"}
    ) +
    @vlplot(
        data = increment_df,
        mark = {type = :bar, cornerRadiusEnd = 3},
        x = {
            field = :label,
            type = "nominal",
            scale = {domain = ["No Inequality", "A", "B", "C", "Total"]},
            axis = {title = "", labelAngle = 0, labelLimit = 220,
                     domain = false, ticks = false, labelPadding = 8}
        },
        y = {
            field = :bar_start,
            type = "quantitative",
            title = "Environmental SCC (\$ per ton CO₂)",
            scale = {zero = true},
            axis = {domain = false, tickCount = 5, grid = true}
        },
        y2 = {field = :bar_end},
        color = {
            field = :description,
            type = "nominal",
            scale = {
                domain = ["A = Unequal E Endowment",
                          "B = Unequal Inter-Regional Consumption",
                          "C = Unequal Intra-Regional Consumption"],
                range  = ["#4A7C59", "#4A7C59", "#4A7C59"]
            },
            legend = {title = ""}
        }
    ) +
    @vlplot(
        data = bar_df,
        mark = {type = :text, color = :white, fontWeight = :bold, fontSize = 13, dy = 0},
        x = {field = :label,   type = "nominal"},
        y = {field = :label_y, type = "quantitative"},
        text = {field = :value_str, type = "nominal"}
    ) +
    @vlplot(
        data = connector_df,
        mark = {type = :rule, strokeDash = [4, 4], color = "#333333", strokeWidth = 1.2},
        x = {field = :from_label, type = "nominal", bandPosition = 1},
        x2 = {field = :to_label,   type = "nominal", bandPosition = 0},
        y = {field = :y_val, type = "quantitative"}
    )

    return plot
end

function prepare_heatmap_df(heatmap_simulations_df)
    heatmap_df_γ0 = @chain heatmap_simulations_df begin
        @filter(γ == 0)
        @select(
            η,
            θ,
            SCC_E_0 = present_cost_of_damages_to_E,
            SCC_c_0 = present_cost_of_damages_to_c
        )
    end

    heatmap_df_γ1 = @chain heatmap_simulations_df begin
        @filter(γ == 1)
        @select(
            η,
            θ,
            SCC_E_1 = present_cost_of_damages_to_E,
            SCC_c_1 = present_cost_of_damages_to_c
        )
    end

    heatmap_df = @chain begin
        @left_join(heatmap_df_γ0, heatmap_df_γ1)
        @mutate(
            Δ_SCC_E = SCC_E_1 - SCC_E_0,
            Δ_SCC_c = SCC_c_1 - SCC_c_0,
        )
        @mutate(
            Δ_SCC_E_over_SCC_E = Δ_SCC_E / SCC_E_1,
            Δ_SCC_E_over_SCC = Δ_SCC_E / (SCC_E_1 + SCC_c_1),
        )
    end
    return heatmap_df
end

function plot_SCC_heatmap(
    heatmap_df::DataFrame; cost_to="E", relative_to=nothing
)::VegaLite.VLSpec

    if relative_to |> isnothing
        variable_to_plot = "Δ_SCC_$cost_to"
        legend_format = " \$d"
        legend_title = ["Change in the social",
                        "cost of damages to $cost_to",
                        "due to national inequality"]
    else
        variable_to_plot = "Δ_SCC_$(cost_to)_over_$relative_to"
        legend_format = ".0%"
        legend_title = ["Share of $relative_to due", "to national inequality"]
    end

    max_absolute_value = heatmap_df[!, variable_to_plot] .|> abs |> maximum

    diagonal_dashed_line = @vlplot(
        mark={:rule, strokeWidth=1, strokeDash=(8, 8)},
        x={datum=-1},
        y={datum=2},
        x2={datum=1},
        y2={datum=0},
        color={value="#888"}
    )
    star_mark = @vlplot(
        mark={:text, text="★", fontSize=15, xOffset=-14, color="#5B5B5B"},
        x={datum=0.5},
        y={datum=1.5}
    )
    heatmap_base = heatmap_df |> @vlplot(
        x={"θ:o", axis={title="Substitutability θ"}},
        y={"η:o", axis={title="Inequality aversion η"}, scale={reverse=true}},
    ) + @vlplot(
        :rect,
        color={
            variable_to_plot,
            scale={
                scheme="blueorange",
                domainMid=0,
                domainMin=-max_absolute_value,
                domainMax=max_absolute_value
            },
            legend={
                title=legend_title,
                format=legend_format,
                gradientLength=300,
                gradientThickness=20
            }
        },
    )
    if cost_to == "E"
        heatmap = heatmap_base + star_mark + diagonal_dashed_line
    else
        heatmap = heatmap_base + star_mark
    end
    return heatmap
end

"""
    function get_SCC_interaction(
        η::Real, θ::Real, α::Real, γ_list::AbstractVector, ρ::Real
    )::DataFrame

Calculate interaction effect in absolute and relative terms at the country level.

Use `get_SCC_decomposition` to compute the SCC decomposition at the country level
for γ = 0 and γ = 1. Then, calculate the interaction effect as the difference in
`present_cost_of_damages_to_E` between the two levels of γ. Finally, calculate the
percentage interaction effect relative to the damage when γ = 1.

Return a DataFrame with the following columns:
- `country`: Country code (ISO3).
- `inequality_damage_E`: Present cost of damages to environment when γ = 1.
- `no_inequality_damage_E`: Present cost of damages to environment when γ = 0.
- `interaction`: Absolute interaction effect (difference between the two columns).
- `interaction_pct`: Percentage interaction effect relative to `inequality_damage_E`.
- `country_id`: Numeric country code for mapping purposes.
"""
function get_SCC_interaction(
    η::Real, θ::Real, α::Real, γ_list::AbstractVector, ρ::Real
)::DataFrame
    SCC_decomposition_df = get_SCC_decomposition(η, θ, α, γ_list, ρ;
                                                 analysis_level="country")

    no_inequality_df = @chain SCC_decomposition_df begin
        @filter(γ == 0)
        @select(country, no_inequality_damage_E = present_cost_of_damages_to_E)
    end

    inequality_df = @chain SCC_decomposition_df begin
        @filter(γ == 1)
        @select(country, inequality_damage_E = present_cost_of_damages_to_E)
    end

    countries_df = @chain begin
        DataFrame(all_countries())
        @select(country = alpha3, country_id = numeric)
    end

    interaction_df = @chain inequality_df begin
        @inner_join(no_inequality_df)
        @mutate(interaction = inequality_damage_E - no_inequality_damage_E)
        @mutate(interaction_pct = 100 * interaction / abs(inequality_damage_E))
        @mutate(country = string.(country))
        @left_join(countries_df)
    end

    return interaction_df
end

function map_SCC_decomposition_level(interaction_df::DataFrame)

    world110m = dataset("world-110m")

    interaction_map = @vlplot(
        width = 640,
        height = 360,
        title = "",
        projection = {type = :equirectangular}
    ) +
    @vlplot(
        data = {
            values = world110m,
            format = {
                type = :topojson,
                feature = :countries
            }
        },
        transform = [{
            lookup = "id",
            from = {
                data = interaction_df,
                key = :country_id,
                fields = ["interaction"]
            }
        }],
        mark = :geoshape,
        encoding = {
            color = {
                field = "interaction",
                type = "quantitative",
                title = "Interaction",
                scale = {
                    scheme = "goldred"
                }
            }
        }
    )

    return interaction_map
end

function map_SCC_decomposition_pct(interaction_df::DataFrame)

    world110m = dataset("world-110m")

    percentage_interaction_map = @vlplot(
        width = 640,
        height = 360,
        title = "",
        projection = {type = :equirectangular}
    ) +
    @vlplot(
        data = {
            values = world110m,
            format = {
                type = :topojson,
                feature = :countries
            }
        },
        transform = [{
            lookup = "id",
            from = {
                data = interaction_df,
                key = :country_id,
                fields = ["interaction_pct"]
            }
        }],
        mark = :geoshape,
        encoding = {
            color = {
                field = "interaction_pct",
                type = "quantitative",
                title = "Interaction (%)",
                scale = {
                    scheme = "purpleorange",
                    domainMid = 0
                }
            }
        }
    )

    return percentage_interaction_map
end

function get_SCC_vs_E(
    E_multiplier_list::AbstractVector, η::Real, θ::Real, α::Real, ρ::Real; kwargs...
)::DataFrame
    kwargs::Dict{Any, Any} = Dict(kwargs)  # avoids type errors when manipulating kwargs
    γ_list = [0., 1.]

    df_list = []
    for E_multiplier in E_multiplier_list
        if haskey(kwargs, :additional_parameters)
            kwargs[:additional_parameters][:E_multiplier] = E_multiplier
        else
            kwargs[:additional_parameters] = Dict(:E_multiplier => E_multiplier)
        end
        df = get_SCC_decomposition(η, θ, α, γ_list, ρ; kwargs...)
        df.E_multiplier .= E_multiplier
        push!(df_list, df)
    end

    concatenated_df = reduce(vcat, df_list)
    return concatenated_df
end

function vertical_rule(
    x::Number,
    y::Number,
    y2::Number,
    label::Union{String, Array{String}}="",
    label_dx::Number=0,
    label_dy::Number=0
)::VegaLite.VLSpec
    rule = @vlplot(
        mark={:rule, strokeWidth=1},
        x={datum=x},
        y={datum=y},
        y2={datum=y2},
        color={value="#888"})
    text = @vlplot(
        mark={:text, align="center", dx=label_dx, dy=label_dy},
        data={values=[{x=x, label=label}]},
        x="x:q",
        text="label:n"
    )
    return @vlplot() + rule + text  # `@vlplot()` avoids a VegaLite.jl bug when layering
end

"""
    plot_SCC_vs_E(SCC_vs_E_df::DataFrame; cost_to::String)

Plot evolution of SCC with respect to the flow

# Keyword arguments
- `cost_to::String` (required): either "E" to plot the present social value of damages to
    the environment, or "c" for damages to consumption.
- `intermediate_layer::VegaLite.VLSpec` (optional): one or several plot components to be
    included between the chart background and the curves (e.g. vertical rules from the
    `vertical_rule` function).
"""
function plot_SCC_vs_E(
    SCC_vs_E_df::DataFrame;
    cost_to::String,
    intermediate_layer::Union{VegaLite.VLSpec, Nothing}=nothing
)
    y_name = "present_cost_of_damages_to_" * cost_to
    y_title = "SCC_" * cost_to * " (\$ / tCO₂ )"

    base = SCC_vs_E_df |> @vlplot(
        width=650,
        height=300,
        x={
            scale={domain=(-10, 600)},
            axis={
                values=[1, (50:50:550)...],
                labelExpr="[
                    datum.value == 1 ? 1 :
                        datum.value == 50 ? 50 :
                        datum.value % 100 ? '' :
                        datum.value,
                    datum.value == 1 ? '(CWON data)' : ''
                ]",
                title="E multiplier",
                grid=true,
        }},
        y={axis={
            title=y_title,
            grid=true,
        }},
        config={
            legend={
                titleFont="Serif",
                titleFontSize=14,
                titleFontWeight="normal",
            }
        }
    )

    dot_pair_connections = @vlplot(
        mark={:rect, width=1.2},
        x={"E_multiplier:q"},
        y={"min($y_name):q"},
        y2={"max($y_name):q"},
        color={
            value={
                y2=1, x2=0,
                y1=0, x1=0,
                gradient="linear",
                stops=[
                    {offset=0, color="#850085"},
                    {offset=1, color="#C98ACF"}
                ]
            }
        },
    )

    curves = @vlplot(
        mark={:line, strokeWidth=1.4, interpolate="monotone"},
        x="E_multiplier:q",
        y="$y_name:q",
        color={
            "γ:o",
            scale={
                domain=[0, 1],
                range=["#C98ACF", "#850085"]
            },
            legend=nothing,
        },
        shape={
            "γ:o",
            scale={
                domain=[1, 0],
                range=["diamond", "circle"]
            },
            legend={
                labelExpr="'γ = ' + datum.value",
                labelFont="Serif",
                labelFontSize=12,
                symbolStrokeColor="transparent",
                symbolFillColor={expr="scale('color', datum.value)"}
            },
        }
    )

    if intermediate_layer ≠ nothing
        base += intermediate_layer
    end
    SCC_vs_E_plot = base + dot_pair_connections + curves
    return SCC_vs_E_plot
end

function get_SCC_vs_E_θ_and_η(
    E_multiplier_list::AbstractVector,
    η_list::AbstractVector,
    θ_list::AbstractVector,
    α::Real,
    ρ::Real;
    kwargs...
)::DataFrame
    η_θ_grid = Base.product(η_list, θ_list) |> collect |> vec
    df_list = [
        get_SCC_vs_E(E_multiplier_list, η, θ, α, ρ; kwargs...) for (η, θ) in η_θ_grid
    ]
    concatenated_df = reduce(vcat, df_list)
    return concatenated_df
end

"""
    get_CPI_data()

Get consumer price index (CPI) data from the US Bureau of Labor Statistics
"""
function get_CPI_data()
    # The free public API is limited to 10 years per request
    all_data = []
    for start_year in [2000, 2010, 2020]
        end_year = min(start_year + 9, 2024)
        payload = Dict(
            "seriesid" => ["CUUR0000SA0"],
            "startyear" => string(start_year),
            "endyear" => string(end_year)
        )
        response = HTTP.post(
            "https://api.bls.gov/publicAPI/v1/timeseries/data/",
            ["Content-Type" => "application/json"],
            JSON.json(payload)
        )
        data = JSON.parse(String(response.body))
        append!(all_data, data["Results"]["series"][1]["data"])
    end

    CPI_df = @chain all_data begin
        DataFrame()
        @group_by(year)
        @summarize(CPI = mean(as_float(value)))
        @arrange(year)
    end
    return CPI_df
end

function adjust_for_inflation(amount, amount_year, target_year=2017)
    if !isfile("data/CPI.csv")
        write_csv(get_CPI_data(), "data/CPI.csv")
    end

    CPI_df = read_csv("data/CPI.csv")
    amount_year_CPI = @eval@chain $CPI_df @filter(year == $amount_year) @pull(CPI) only
    target_year_CPI = @eval@chain $CPI_df @filter(year == $target_year) @pull(CPI) only

    adjusted_amount = amount * (target_year_CPI / amount_year_CPI)
    return adjusted_amount
end

"""
    get_costanza_total_forest_material_value()

Get the annual flow of material forest ecosystem services from Costanza et al. (2014).

Note: the original .xls file (`1-s2.0-S0959378014000685-mmc2.xls`) was converted to .xlsx
manually using LibreOffice, as reading an xls file in 2026 with Julia was just too messy.
"""
function get_costanza_forest_values()
    costanza_forest_df = @chain begin
        XLSX.readdata("analysis/costanza-2014-table-S1.xlsx", "Sheet2", "A4:AT32")
        DataFrame(_, :auto)
        @mutate(biome = coalesce(x1, x2, x3))
        @filter(biome != "Biome")
        @drop_missing(biome)
        @select(
            biome,
            area = x5 * 10^6,
            gas_regulation = x7,
            climate_regulation = x9,
            disturbance_regulation = x11,
            water_regulation = x13,
            water_supply = x15,
            erosion_control = x17,
            soil_formation = x19,
            nutrient_cycling = x21,
            waste_treatment = x23,
            pollination = x25,
            biological_control = x27,
            habitat = x29,
            food = x31,
            raw_materials = x33,
            genetic_resources = x35,
            recreation = x37,
            cultural = x39
        )
        coalesce.(_, 0)
    end

    total_value_per_hectare = @chain costanza_forest_df begin
        @select(gas_regulation:cultural)
        sum(eachcol(_))
    end

    forest_values_df = @eval @chain $costanza_forest_df begin
        @transmute(
            biome,
            total_value = area * $total_value_per_hectare,
            water_food_recreation =  area * (
                water_regulation
                + water_supply
                + food
                + recreation
            ),
        )
        @filter(biome == "Forest")
        @transmute(across(where(is_float), x -> adjust_for_inflation(x, 2007, 2017)))
        @rename_with(x -> replace(x, "_function" => ""))
    end
    return forest_values_df
end

function plot_relative_I_vs_E(SCC_vs_E_df::DataFrame)::VegaLite.VLSpec

    no_inequality_df = @chain SCC_vs_E_df begin
        @filter(γ == 0)
        @select(E_multiplier, SCC_E_0 = present_cost_of_damages_to_E)
    end

    inequality_df = @chain SCC_vs_E_df begin
        @filter(γ == 1)
        @select(E_multiplier, SCC_E_1 = present_cost_of_damages_to_E)
    end

    relative_I_vs_E = @chain inequality_df begin
        @inner_join(no_inequality_df)
        @mutate(
            relative_I = (SCC_E_1 - SCC_E_0) / abs(SCC_E_1) * 100
        )
    end

    relative_I_vs_E_plot = relative_I_vs_E |> @vlplot(
        width = 650,
        height = 300,
        mark = {:line, color = "firebrick", strokeWidth = 2.5},
        x = {
            "E_multiplier:q",
            axis = {
                values = [1, (50:50:550)...],
                title = "E multiplier",
                grid = true
            }
        },
        y = {
            "relative_I:q",
            scale = {domain = [0, 100]},
            axis = {
                title = "Relative Interaction Effect (I%)",
                grid = true
            }
        }
    )
    return relative_I_vs_E_plot
end

function plot_SCC_E_shares_sensitivity(SCC_vs_E_df::DataFrame)::VegaLite.VLSpec

    SCC_E_shares_sensitivity = @chain(SCC_vs_E_df,
        @filter(γ .== 1.0),
        @mutate(
            intra_regional_inequality =
                present_cost_of_damages_to_E_within_equal / present_cost_of_damages_to_E,
            inter_regional_inequality =
                present_cost_of_damages_to_E_across_equal / present_cost_of_damages_to_E,
            E_inequality =
                present_cost_of_damages_to_E_E_equal / present_cost_of_damages_to_E
        ),
        stack(
            [:intra_regional_inequality, :inter_regional_inequality, :E_inequality],
            variable_name = :inequality_type,
        value_name = :share
        ),
        @mutate(inequality_type = replace(inequality_type,
            "E_inequality"              => "A",
            "inter_regional_inequality" => "B",
            "intra_regional_inequality" => "C"
            )
        ),
        select(:E_multiplier, :inequality_type, :share)
    )

    SCC_E_shares_sensitivity_plot = SCC_E_shares_sensitivity |> @vlplot(
        mark = {:line, strokeWidth = 2},
        x = {
            field = :E_multiplier,
            title = "E multiplier",
            type = :quantitative,
            axis = {labelFontSize = 11, titleFontSize = 13, grid = false}
        },
        y = {
            field = :share,
            title = "Share of SCC_E",
            type = :quantitative,
            scale = {domainMin = 0.25},
            axis = {labelFontSize = 11, titleFontSize = 13, grid = true, gridDash = [4, 4]}
        },
        color = {
            field = :inequality_type,
            title = "Inequality type",
            scale = {scheme = "tableau10"},
            legend = {
                orient = "bottom",
                direction = "horizontal",
                labelFontSize = 11,
                titleFontSize = 12,
                titleOrient = "left"
            }
        },
        width = 500,
        height = 300,
        config = {
            background = "white",
            view = {stroke = "transparent"}
        }
    )

    return SCC_E_shares_sensitivity_plot

end
