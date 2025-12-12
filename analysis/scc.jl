using Mimi
using TidierData
using TidierFiles
using VegaLite, VegaDatasets
using Countries

include("../src/GreenNICE.jl")
using .GreenNICE

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
        @left_join($population_df)
        @left_join($damages_df)
        @rename(
            year = time,
            c = qcpc_post_recycle,
            E = E_flow_percapita,
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
        @summarize(
            c = mean(c),
            E = mean(E),
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
            ∂_cE = marginal_welfare_of_environment(c, E, l, $η, $θ, $α),
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
        # Exclude 4 small countries with E = 0 because they have infinite ∂_cE
        @filter(E > 0)
        @summarize(
            t = unique(t),
            welfare_loss_c = sum(∂_cW * marginal_damage_to_c),
            welfare_loss_E = sum(∂_cE * marginal_damage_to_E),
        )
        @filter(t >= 0)
        @summarize(
            present_cost_of_damages_to_c = 1 / $reference_marginal_utility
                                           * sum($β^t * welfare_loss_c),
            present_cost_of_damages_to_E = 1 / $reference_marginal_utility
                                           * sum($β^t * welfare_loss_E),
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
            η::Real, θ::Real, α::Real, γ_list::Vector, ρ::Real; kwargs...
        )::DataFrame

    Get SCC decomposition for a vector of γ values.

    Apply `get_SCC_decomposition` for each value of γ provided in `γ_list`.
    Return a Dataframe with as many rows as values in `γ_list`.
"""
function get_SCC_decomposition(
    η::Real, θ::Real, α::Real, γ_list::Vector, ρ::Real; kwargs...
)::DataFrame
    df_list = [get_SCC_decomposition(η, θ, α, γ, ρ; kwargs...) for γ in γ_list]
    concatenated_df = reduce(vcat, df_list)
    return concatenated_df
end


"""
        get_SCC_decomposition(
            η_list::Vector, θ_list::Vector, α::Real, γ_list::Vector, ρ::Real; kwargs...
        )::DataFrame

    Get SCC decomposition for an η × θ grid.
"""
function get_SCC_decomposition(
    η_list::Vector, θ_list::Vector, α::Real, γ_list::Vector, ρ::Real; kwargs...
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
        y="present_cost_of_damages_to_c:q",
    )
    environment_plot = SCC_decomposition_df |> @vlplot(
        :line,
        x="γ:q",
        y="present_cost_of_damages_to_c:q",
    )
    combined_plot = hcat(consumption_plot, environment_plot)
    return combined_plot
end


"""
        facet_SCC(SCC_decomposition_df::DataFrame; cost_to::String)::VegaLite.VLSpec

    Plot the social cost of carbon to environment or consumption for different η's and θ's.

    # Keyword arguments
    - `cost_to::String`: either "E" to plot the present social value of damages to the
        environment, or "c" for damages to consumption.
"""
function facet_SCC(SCC_decomposition_df::DataFrame; cost_to::String)::VegaLite.VLSpec
    y_name = "present_cost_of_damages_to_" * cost_to
    SCC_facet_plot = SCC_decomposition_df |> @vlplot(
        :line,
        x="γ:q",
        y="$y_name:q",
        column=:θ,
        row={field=:η, sort={field=:η, order="descending"}},
        resolve={scale={y="independent"}},
    )
    return SCC_facet_plot
end

"""
        function get_SCC_interaction(
            η::Real, θ::Real, α::Real, γ_list::Vector, ρ::Real
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
function get_SCC_interaction(η::Real, θ::Real, α::Real, γ_list::Vector, ρ::Real)::DataFrame
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
                title = "Interaction cost",
                scale = {
                    scheme = "blueorange",
                    domainMid = 0,
                    domain = [-0.1, 0.1]
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
