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
        getdataframe(mm, :welfare => (:qcpc_post_recycle, :Env_percapita))
        # The marginal model gives changes per ton of CO2:
        # `(modified_model_value - base_model_value) / pulse_size`.
        # So marginal *damages* are the additive inverse of the changes in consumption and
        # environment.
        @mutate(
            marginal_damage_to_c = -qcpc_post_recycle,
            marginal_damage_to_E = -Env_percapita,
        )
        @select(-(qcpc_post_recycle, Env_percapita))
    end

    clean_df = @eval @chain $base_df begin
        @left_join($population_df)
        @left_join($damages_df)
        @rename(
            year = time,
            c = qcpc_post_recycle,
            E = Env_percapita,
        )
        @mutate(t = year - $pulse_year)  # t = 0 at pulse year. Used later to discount.
        @relocate(year, t)
    end

    return clean_df
end


function marginal_welfare_of_consumption(c, E, l, η, θ, α)
    return l * (1 - α) * c^(θ - 1) * v(c, E, θ, α)^(1 - η - θ)
end


function marginal_welfare_of_environment(c, E, l, η, θ, α)
    return l * α * E^(θ - 1) * v(c, E, θ, α)^(1 - η - θ)
end


function prepare_df_for_SCC(df::DataFrame, η::Real, θ::Real, α::Real)::DataFrame
    prepared_df = @eval @chain $df begin
        @mutate(
            l = l / 10,  # population in a decile is a tenth of the country's population
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
        @summarize(
            present_cost_of_damages_to_c = sum(B .* cost_of_damages_to_c),
            present_cost_of_damages_to_E = sum(B .* cost_of_damages_to_E),
        )
    end
    return SCC_df
end


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


# Testing...
η = 2
θ = 0.5
α = 0.1
ρ = 0.001
γ = 0
get_SCC_decomposition(η, θ, α, γ, ρ)
