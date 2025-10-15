using Mimi
using TidierData
using TidierFiles

include("../src/GreenNICE.jl")
using .GreenNICE

include("../src/components/welfare.jl")


function set_up_marginal_model(
    η::Real, θ::Real, α::Real, γ::Real, pulse_year::Int, pulse_size::Real
)::MarginalModel

    m = GreenNICE.create()
    update_params!(m, Dict(:η => η, :θ => θ, :α => α))
    update_param!(m, :quantile_recycle, :γ, γ)

    years = dim_keys(m, :time)
    n_years = length(years)
    pulse_year_index = findfirst(t -> t == pulse_year, years)

    pulse_series = zeros(n_years)
    pulse_series[pulse_year_index] = pulse_size

    mm = create_marginal_model(m, pulse_size)
    update_param!(mm.modified, :emissions, :co2_pulse, pulse_series)

    return mm
end

function get_model_data(mm::MarginalModel, pulse_year::Int)::DataFrame
    base_df = getdataframe(mm.base, :welfare => (:qcpc_post_recycle, :Env_percapita))
    population_df = getdataframe(mm.base, :welfare => :l)
    damages_df = @chain begin
        getdataframe(
            mm,
            :welfare => :Env_percapita,
            :quantile_recycle => :qcpc_damages,
        )
        # The marginal model gives changes per ton of CO2:
        # `(modified_model_value - base_model_value) / pulse_size`.
        # So marginal *damages* are the additive inverse of the changes in environment.
        @mutate(marginal_damage_to_E = -Env_percapita)
        @select(-(Env_percapita))
    end

    clean_df = @eval @chain $base_df begin
        @left_join($population_df)
        @left_join($damages_df)
        @rename(
            year = time,
            c = qcpc_post_recycle,
            E = Env_percapita,
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


function prepare_df_for_SCC(df::DataFrame, η::Real, θ::Real, α::Real)::DataFrame
    prepared_df = @eval @chain $df begin
        @mutate(
            ∂_cW = marginal_welfare_of_consumption(c, E, l, $η, $θ, $α),
            ∂_cE = marginal_welfare_of_environment(c, E, l, $η, $θ, $α),
        )
        @mutate(p = ∂_cW / ∂_cE)  # relative price of E
        @group_by(year)
        @mutate(∂_cW_global_average = sum(∂_cW) / sum(l))
        @ungroup()
        @mutate(a = ∂_cW / ∂_cW_global_average)  # equity weights
    end
    return prepared_df
end


@doc raw"""
        apply_SCC_decomposition_formula(prepared_df::DataFrame, ρ::Real)::DataFrame

    Get present value of equity-weighted, money-metric damages to `c` and `E`.

    The social cost of carbon (SCC) is equal to the sum of the present cost of marginal
    damages to consumption `c`, and to environment `E`:
    ```math
    \sum_t B_t \sum_{i} a_{i, t} \frac{dc_i}{de}
    + \sum_t B_t \sum_{i} a_{i, t} p_{i, t} \frac{dE_i}{de}.
    ```

    **Discount factor** ``B_t`` (column `B` in the dataframe) is calculated as:
    ```math
    B(t) = \beta^t
        \frac{
            \frac{1}{n} \sum_{i} \partial_{c_{i, t}}{W_t}
        }{
            \frac{1}{n} \sum_{i} \partial_{c_{i, 0}}{W_0}
    },
    ```

    where index ``i`` represents a group (a certain decile in a certain country), and
    ``W_t`` is global welfare at time ``t``.

    **Equity weight** ``a_{i, t}`` (column `a`) is defined as:
    ```math
    a_{i, t} = \frac{
        \partial_{c_{i, t}} W_t
    }{
        \frac{1}{n} \sum_{i}\partial_{c_{i, t}} W_t
    }
    ```

    **Relative price** ``p_{i, t}`` (column `p`) is defined as:
    ```math
    p_{i, t} = \frac{\partial_{E_i}{W_t}}{\partial_{c_i}{W_t}}.
    ```

    Marginal damages to consumption ``\frac{dc_i}{de}`` are called `marginal_damage_to_c` in
    the dataframe, and marginal damages to the environment, ``\frac{dE_i}{de}``, are coded
    as `marginal_damage_to_E`.
"""
function apply_SCC_decomposition_formula(prepared_df::DataFrame, ρ::Real)::DataFrame
    SCC_df = @eval @chain $prepared_df begin
        @group_by(year)
        @summarize(
            t = unique(t),
            ∂_cW_global_average = unique(∂_cW_global_average),
            cost_of_damages_to_c = sum(a .* marginal_damage_to_c),
            cost_of_damages_to_E = sum(a .* p.* marginal_damage_to_E),
        )
        @mutate(B = (1 / (1 + $ρ))^t * ∂_cW_global_average / ∂_cW_global_average[t == 0])
        @filter(t >= 0)
        @summarize(
            present_cost_of_damages_to_c = sum(B .* cost_of_damages_to_c),
            present_cost_of_damages_to_E = sum(B .* cost_of_damages_to_E),
        )
    end
    return SCC_df
end


"""
        get_SCC_decomposition(
            η::Real, θ::Real, α::Real, γ::Real, ρ::Real;
            pulse_year::Int=2025, pulse_size::Real=1.
        )::DataFrame

    Get social cost of carbon as damages to consumption and damages to the environment.

    Run a version of GreenNICE with the parameters supplied to the function, as well as an
    identical model with an additional `pulse_size` tons of CO2 in year `pulse_year`.
    Compare consumption and environment between the two models, and compute the present
    value of damages analytically.

    Return a one-line `Dataframe` with two `Float64` columns:
    - `present_cost_of_damages_to_c`,
    - `present_cost_of_damages_to_E`.

    The sum of these two numbers is the social cost of carbon (SCC). See function
    `apply_SCC_decomposition_formula` for mathematical details.

    # Arguments
    - `η::Real`: inequality aversion (coefficient of relative risk aversion).
    - `θ::Real`: substitutability parameter. Accepts value between -∞ and 1.
    - `α::Real`: share of `environment` the utility function. Must be in ``[0, 1]``.
    - `γ::Real`: within-country inequality parameter. 0 means no within-country inequality.
        1 is the standard calibration.
    - `ρ::Real`: rate of pure time preference (utility discount rate).
    - `pulse_year::Int`: year where the CO2 marginal pulse is emmitted, and year of
        reference for the SCC.
    - `pulse_size::Real`: size of the CO2 pulse, in tons.
"""
function get_SCC_decomposition(
    η::Real, θ::Real, α::Real, γ::Real, ρ::Real; pulse_year::Int=2025, pulse_size::Real=1.
)::DataFrame

    mm = set_up_marginal_model(η, θ, α, γ, pulse_year, pulse_size)
    run(mm)

    SCC_decomposition_df = @chain begin
        get_model_data(mm, pulse_year)
        prepare_df_for_SCC(_, η, θ, α)
        apply_SCC_decomposition_formula(_, ρ)
    end

    return SCC_decomposition_df
end


"""
        get_SCC_decomposition(
        η::Real, θ::Real, α::Real, γ_list::Vector, ρ::Real; kwargs...
    )::DataFrame

    Get SCC decomposition for a vector of γ values.

    Apply `get_SCC_decomposition` for each value of γ provided in `γ_list`.
    Return a Dataframe with as many rows as values in `γ_list`, with three columns:
    - `γ`, equal to `γ_list`,
    - `present_cost_of_damages_to_c`,
    - `present_cost_of_damages_to_E`.
"""
function get_SCC_decomposition(
    η::Real, θ::Real, α::Real, γ_list::Vector, ρ::Real; kwargs...
)::DataFrame
    df_list = map(γ -> get_SCC_decomposition(η, θ, α, γ, ρ; kwargs...), γ_list)
    concatenated_df = reduce(vcat, df_list)
    SCC_decomposition_df = @eval @chain $concatenated_df begin
        @mutate(γ = $γ_list)
        @relocate(γ)
    end
    return SCC_decomposition_df
end


# Testing...
η = 2
θ = 0.5
α = 0.1
ρ = 0.001
γ = 0
get_SCC_decomposition(η, θ, α, γ, ρ)


γ_list = [0., 1.]
get_SCC_decomposition(η, θ, α, γ_list, ρ)
