@defcomp welfare begin

    country         = Index()
    regionwpp       = Index()
	quantile        = Index()

    qcpc_post_recycle       = Parameter(index=[time, country, quantile])    # Quantile per capita consumption after recycling tax back to quantiles (thousand USD2017 per person per year)
    η                       = Parameter()                                   # Inequality aversion
    nb_quantile             = Parameter()                                   # Number of quantiles
    l                       = Parameter(index=[time, country])              # Population (thousands)
    mapcrwpp                = Parameter(index=[country])                    # Map from country index to wpp region index

    welfare_country         = Variable(index=[time, country])               # Country welfare
    welfare_rwpp            = Variable(index=[time, regionwpp])             # WPP region welfare
    welfare_global          = Variable(index=[time])                        # Global welfare

    α                       = Parameter()                                   # Environmental good weight in utility function
    θ                       = Parameter()                                   # Elasticity of substitution between consumption and environmental good
    E_flow_percapita        = Parameter(index=[time, country, quantile])    # Flow of non-market environmental good per capita (thousand USD2017 per person per year)

    function run_timestep(p, v, d, t)

        for c in d.country
            v.welfare_country[t,c] = (
                (p.l[t,c] / p.nb_quantile) * sum(utility.(
                    p.qcpc_post_recycle[t,c,:], p.E_flow_percapita[t,c,:], p.η, p.θ, p.α
                ))
            )
        end # country loop

        for rwpp in d.regionwpp
            country_indices = findall(x -> x == rwpp, p.mapcrwpp)
            v.welfare_rwpp[t,rwpp] = sum(v.welfare_country[t,country_indices])
        end # region loop

        v.welfare_global[t] = sum(v.welfare_country[t,:])
    end # timestep
end

"""
    v(consumption::Real, environment::Real, θ::Real, α::Real)

Combine consumption and environment with a constant elasticity of substitution.

This is an intermediate function to the `utility` function.

# Arguments
- `c::Real`: consumption of market goods.
- `E::Real`: consumption of non-market environmental goods.
- `θ::Real`: substitutability parameter. Accepts value between -∞ and 1.
- `α::Real`: share of `environment` the utility function. Must be in ``[0, 1]``.
"""
function v(c::Real, E::Real, θ::Real, α::Real)
    if θ ≠ 0
        # CES general case
        value = ((1 - α) * c^θ + α * E^θ)^(1 / θ)
    elseif θ == 0
        # Cobb-Douglas special case
        value = c^(1 - α) * E^α
    end

    return value
end

"""
    utility(consumption::Real, environment::Real, η::Real, θ::Real, α::Real)

Calculate utility of consumption and environmental goods.

# Arguments
- `c::Real`: consumption of market goods.
- `E::Real`: consumption of non-market environmental goods.
- `η::Real`: inequality aversion (coefficient of relative risk aversion).
- `θ::Real`: substitutability parameter. Accepts value between -∞ and 1.
- `α::Real`: share of `environment` the utility function. Must be in ``[0, 1]``.
"""
function utility(c::Real, E::Real, η::Real, θ::Real, α::Real)
    # define concave (CRRA) transformation to be applied to function `v`
    if η ≠ 1
        # CRRA general case
        φ = x -> x^(1 - η) / (1 - η)
    elseif η == 1
        # logarithm special case
        φ = x -> log(x)
    end

    utility = φ(v(c, E, θ, α))
    return utility
end
