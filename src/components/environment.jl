@defcomp environment begin
    country     = Index()                           #Note that a regional index is defined here
    quantile    = Index()

    l               = Parameter(index=[time, country])      # Labor - population (thousands)
    nb_quantile     = Parameter()                           # Number of quantiles
    damage          = Parameter()                           # percetage loss of E over time
    Env0            = Parameter(index=[country])            # Initial level of environmental good
    mapcrwpp        = Parameter(index=[country])

    Env             = Variable(index=[time, country, quantile])     # Environmental variable
    Env_percapita   = Variable(index=[time, country, quantile])     #E percapita
    E_bar           = Variable()                                    # Average level of environment per capita at time 0
    Env_country     = Variable(index=[time,country])
    Env_rwpp        = Variable(index=[time, regionwpp])
    Env_global      = Variable(index=[time])
    Env_decile      = Variable(index=[time, quantile])

    function run_timestep(p, v, d, t)
        # Note that the country dimension is defined in d and parameters and variables are indexed by 'c'

        for c in d.country, q in d.quantile
            v.Env[t, c, q] = is_first(t) ?
            (p.Env0[c] / p.nb_quantile) : v.Env[t - 1, c, q] * (1-p.damage)
        end

        for c in d.country, q in d.quantile
            #Assume environmental good is equally distributed
            v.Env_percapita[t, c, q] =
                (1 / p.nb_quantile) * (sum(v.Env[t, c, :]) / p.l[t, c])
        end

        #Evolution of Env over time for plots

        for c in d.country, q in d.quantile
            v.Env_country[t,c] = sum(v.Env[t,c,:])
        end

        for rwpp in d.regionwpp
            country_indices = findall(x -> x == rwpp, p.mapcrwpp)
            v.Env_rwpp[t,rwpp] = sum(v.Env_country[t,country_indices])
        end

        v.Env_global[t] = sum(v.Env_country[t,:])

        for q in d.quantile
            v.Env_decile[t,q] = Env_distribution(v.Env[t,:,q], p.l[t,:], p.nb_quantile)
        end

        v.E_bar = sum(p.Env0[:]) / sum(p.l[TimestepIndex(1), :])
    end
end #end component

function Env_distribution(
    environment,
    population,
    nb_quantile
)
    total_population = sum(population)
    Env_decile = (1 / total_population) * sum( (population ./ nb_quantile) .*
    environment)
    return Env_decile
end
