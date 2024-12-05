@defcomp welfare begin

    country         = Index()
    regionwpp       = Index()
	quantile        = Index()

    qcpc_post_recycle       = Parameter(index=[time, country, quantile])    # Quantile per capita consumption after recycling tax back to quantiles (thousand USD2017 per person per year)
    η                       = Parameter()                                   # Inequality aversion
    nb_quantile             = Parameter()                                   # Number of quantiles
    l                       = Parameter(index=[time, country])              # Population (thousands)
    mapcrwpp                = Parameter(index=[country])                    # Map from country index to wpp region index

    cons_EDE_country        = Variable(index=[time, country])               # Equally distributed welfare equivalent consumption (thousand USD2017 per person per year)
    cons_EDE_rwpp           = Variable(index=[time, regionwpp])             # Regional qually distributed welfare equivalent consumption (thousand USD2017 per person per year)
    cons_EDE_global         = Variable(index=[time])                        # Glibal equally distributed welfare equivalent consumption (thousand USD2017 per person per year)
    welfare_country         = Variable(index=[time, country])               # Country welfare
    welfare_rwpp            = Variable(index=[time, regionwpp])             # WPP region welfare
    welfare_global          = Variable(index=[time])                        # Global welfare

    α                       = Parameter()                                   # Environmental good weight in utility function
    θ                       = Parameter()                                   # Elasticity of substitution between consumption and environmental good
    Env_percapita           = Parameter(index=[time, country, quantile])    # Non_market environmental good
    E_bar                   = Parameter()                                   # Reference level of environment
    Env_country             = Variable(index=[time, country])
    Env_rwpp                = Variable(index=[time, regionwpp])

    function run_timestep(p, v, d, t)

        for c in d.country
            v.cons_EDE_country[t,c] = EDE(
                p.qcpc_post_recycle[t,c,:],
                p.Env_percapita[t,c,:],
                p.E_bar,
                p.η,
                p.θ,
                p.α,
                p.nb_quantile
            )

            v.welfare_country[t,c] = (
                (p.l[t,c] / p.nb_quantile) * sum(utility.(
                    p.qcpc_post_recycle[t,c,:], p.Env_percapita[t,c,:], p.η, p.θ, p.α
                ))
            )
        end # country loop

        for rwpp in d.regionwpp
            country_indices = findall(x -> x == rwpp, p.mapcrwpp)

            v.cons_EDE_rwpp[t,rwpp] = EDE_aggregated(
                v.cons_EDE_country[t,country_indices],
                p.E_bar,
                p.η,
                p.θ,
                p.α,
                p.l[t,country_indices]
            )
            v.welfare_rwpp[t,rwpp] = sum(v.welfare_country[t,country_indices])
        end # region loop

        v.cons_EDE_global[t] = EDE_aggregated(
            v.cons_EDE_country[t,:],
            p.E_bar,
            p.η,
            p.θ,
            p.α,
            p.l[t,:],
        )
        v.welfare_global[t] = sum(v.welfare_country[t,:])
    end # timestep
end


"""
    utility(consumption::Real, environment::Real, η::Real, θ::Real, α::Real)

Calculate utility of consumption and environmental goods.

# Arguments
- `η::Real`: inequality aversion (coefficient of relative risk aversion).
- `θ::Real`: substitutability parameter. Accepts value between -∞ and 1, and cannot be null.
- `α::Real`: share of `environment` the utility function. Must be in ``[0, 1]``.
"""
function utility(consumption::Real, environment::Real, η::Real, θ::Real, α::Real)
    if η == 1
        utility = log(
            ((1 - α) * consumption^θ + α * environment^θ)^(1 / θ)
        )
    else
        utility = ((1 - α) * consumption^θ + α * environment^θ)^((1 - η) / θ) / (1 - η)
    end

    return utility
end


"""
    inverse_utility(utility::Real, environment::Real, η::Real, θ::Real, α::Real)

Calculate the consumption that would give a certain utility with the `utility` function.
"""
function inverse_utility(utility::Real, environment::Real, η::Real, θ::Real, α::Real)
    if η == 1
        consumption = (
            (1 / (1 - α)) * (exp(utility)^θ - α * environment^θ)
        )^(1 / θ)
    else
        consumption = (
            (1 / (1 - α)) * ( ((1 - η) * utility)^(θ / (1 - η)) - α * environment^θ)
        )^(1 / θ)
    end

    return consumption
end


"""
    EDE(
    consumption::Vector,
    environment::Union{Real,Vector},
    baseline_environment::Real,
    η::Real,
    θ::Real,
    α::Real,
    nb_quantile::Int,
)

Calculate Equally Distributed Equivalent (EDE) consumption at the country level.

EDE consumption is the consumption level that would provide the same welfare if there were
no inequalities, given a shared `baseline_environment` level of envrionmental consumption.
"""
function EDE(
    consumption::Vector,
    environment::Union{Real,Vector},
    baseline_environment::Real,
    η::Real,
    θ::Real,
    α::Real,
    nb_quantile::Int,
)
    average_utility = (1 / nb_quantile) * sum(utility.(
        consumption, environment, η, θ, α
    ))
    EDE = inverse_utility.(average_utility, baseline_environment, η, θ, α)
    return EDE
end


"""
    EDE_aggregated(
    country_level_EDE::Vector,
    baseline_environment::Real,
    η::Real,
    θ::Real,
    α::Real,
    population::Vector,
)

Aggregate country-level EDE consumption.
"""
function EDE_aggregated(
    country_level_EDE::Vector,
    baseline_environment::Real,
    η::Real,
    θ::Real,
    α::Real,
    population::Vector,
)
    total_utility = sum(population .* utility.(
        country_level_EDE, baseline_environment, η, θ, α
    ))
    total_population = sum(population)
    average_utility = total_utility / total_population
    aggregated_EDE = inverse_utility(average_utility, baseline_environment, η, θ, α)
    return aggregated_EDE
end
