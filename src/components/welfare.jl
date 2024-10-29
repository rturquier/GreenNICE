function utility(consumption, environment, η, θ, α)
    if η == 1
        utility = log(
            ((1 - α) * consumption^θ + α * environment^θ)^(1 / θ)
        )
    else
        utility = ((1 - α) * consumption^θ + α * environment^θ)^((1 - η) / θ) / (1 - η)
    end

    return utility
end


function inverse_utility(utility, environment, η, θ, α)
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


function EDE(consumption, environment, η, θ, α, nb_quantile)
    average_utility = (1 / nb_quantile) * sum(utility.(consumption, environment, η, θ, α))
    EDE = inverse_utility(average_utility, environment, η, θ, α)
    return EDE
end


function EDE_aggregated(country_level_EDE, environment, η, θ, α, population)
    total_utility = sum(population .* utility.(country_level_EDE, environment, η, θ, α))
    total_population = sum(population)
    average_utility = total_utility / total_population
    aggregated_EDE = inverse_utility(average_utility, environment, η, θ, α)
    return aggregated_EDE
end


@defcomp welfare begin

    country         = Index()
    regionwpp       = Index()
	quantile        = Index()

    qcpc_post_recycle       = Parameter(index=[time, country, quantile])    # Quantile per capita consumption after recycling tax back to quantiles (thousand USD2017 per person per year)
    η                       = Parameter()                                   # Inequality aversion
    nb_quantile             = Parameter()                                   # Number of quantiles
    l                       = Parameter(index=[time, country])              # Population (thousands)
    mapcrwpp                = Parameter(index=[country])                    # Map from country index to wpp region index
    Env                     = Parameter(index=[time, country, quantile])

    cons_EDE_country        = Variable(index=[time, country])               # Equally distributed welfare equivalent consumption (thousand USD2017 per person per year)
    cons_EDE_rwpp           = Variable(index=[time, regionwpp])             # Regional qually distributed welfare equivalent consumption (thousand USD2017 per person per year)
    cons_EDE_global         = Variable(index=[time])                        # Glibal equally distributed welfare equivalent consumption (thousand USD2017 per person per year)
    welfare_country         = Variable(index=[time, country])               # Country welfare
    welfare_rwpp            = Variable(index=[time, regionwpp])             # WPP region welfare
    welfare_global          = Variable(index=[time])                        # Global welfare

    α                       = Parameter()                                   # Environmental good weight in utility function
    θ                       = Parameter()                                   # Elasticity of substitution between consumption and environmental good
    Env                     = Parameter(index=[time, country, quantile])    # Environmental good consumption (**Unit to be defined**). Does not vary by quantile
    GreenNice               = Parameter()                                   # GreenNice switch (1 = ON)
   E_bar                   = Parameter()              # Average level of environment at time 0


    function run_timestep(p, v, d, t)
        for c in d.country
            v.cons_EDE_country[t,c] = EDE(
                p.qcpc_post_recycle[t,c,:],
                p.Env,
                p.η,
                p.θ,
                p.α,
                p.nb_quantile
            )

            v.welfare_country[t,c] = (
                (p.l[t,c] / p.nb_quantile) * sum(utility.(
                    p.qcpc_post_recycle[t,c,:], p.Env, p.η, p.θ, p.α
                ))
            )
        end # country loop

        for rwpp in d.regionwpp
            country_indices = findall(x -> x == rwpp, p.mapcrwpp)

            v.cons_EDE_rwpp[t,rwpp] = EDE_aggregated(
                v.cons_EDE_country[t,country_indices],
                p.Env,
                p.η,
                p.θ,
                p.α,
                p.l[t,country_indices]
            )
            v.welfare_rwpp[t,rwpp] = sum(v.welfare_country[t,country_indices])
        end # region loop

        v.cons_EDE_global[t] = EDE_aggregated(
            v.cons_EDE_country[t,:],
            p.Env,
            p.η,
            p.θ,
            p.α,
            p.l[t,:]
        )
        v.welfare_global[t] = sum(v.welfare_country[t,:])
    end # timestep
end
