@defcomp environment begin
    country     = Index()                           #Note that a regional index is defined here
    quantile    = Index()

    l               = Parameter(index=[time, country])      # Labor - population (thousands)
    nb_quantile     = Parameter()                           # Number of quantiles
    damage          = Parameter()                           # percetage loss of E over time
    Env0            = Parameter(index=[country])            # Initial level of environmental good (million)
    mapcrwpp        = Parameter(index=[country])
    dam_assessment  = Parameter()                           #Switch to determine type of assessment

    LOCAL_DAM_ENV   = Parameter(index=[time,country])

    Env             = Variable(index=[time, country, quantile])     # Environmental variable
    Env_percapita   = Variable(index=[time, country, quantile])     # E percapita (thousand)
    E_bar           = Variable()                                    # Average level of environment per capita at time 0 (thousand usd)
    Env_country     = Variable(index=[time,country])
    Env_rwpp        = Variable(index=[time, regionwpp])
    Env_global      = Variable(index=[time])

    function run_timestep(p, v, d, t)
        # Note that the country dimension is defined in d and parameters and variables are indexed by 'c'

        v.E_bar = sum(p.Env0[:]) / sum(p.l[TimestepIndex(1), :])

        for c in d.country, q in d.quantile

            if p.dam_assessment == 4                    # samel E per capita, equal damages
                v.Env[t, c, q] = is_first(t) ?
                (v.E_bar * p.l[t,c] / p.nb_quantile) : v.Env[t - 1, c, q] * (1-p.damage)

            elseif p.dam_assessment == 3                # different E, equal damages
                v.Env[t, c, q] = is_first(t) ?
                (p.Env0[c] / p.nb_quantile) : v.Env[t - 1, c, q] * (1-p.damage)

            elseif p.dam_assessment == 2                #same E, different damages
                v.Env[t, c, q] = is_first(t) ?          ###PROBLEM
                (v.E_bar * p.l[t,c] / p.nb_quantile) :
                (v.Env[TimestepIndex(1),c,q] * p.LOCAL_DAM_ENV[t,c])
                #((v.E_bar * p.l[TimestepIndex(1),c] / p.nb_quantile) * p.LOCAL_DAM_ENV[t,c])

            else                                        # GreenNICE
                v.Env[t, c, q] = is_first(t) ?
                (p.Env0[c] / p.nb_quantile) :
                (p.Env0[c] * p.LOCAL_DAM_ENV[t,c] * (1 / p.nb_quantile))
            end

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


    end
end #end component
