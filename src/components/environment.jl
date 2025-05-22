@defcomp environment begin
    country     = Index()                           #Note that a regional index is defined here
    quantile    = Index()

    l               = Parameter(index=[time, country])      # Labor - population (thousands)
    nb_quantile     = Parameter()                           # Number of quantiles
    damage          = Parameter()                           # percetage loss of E over time
    N0              = Parameter(index=[country])            # Initial level of stock Natural capital (million)
    mapcrwpp        = Parameter(index=[country])
    dam_assessment  = Parameter()                           #Switch to determine type of assessment

    LOCAL_DAM_ENV   = Parameter(index=[time,country])
    flow            = Parameter()                           # Flow of natural capital stock (million)

    Env             = Variable(index=[time, country, quantile])     # Environmental variable
    Env_percapita   = Variable(index=[time, country, quantile])     # E percapita (thousand)
    E_bar           = Variable()                                    # Average level of environment per capita at time 0 (thousand usd)
    Env_country     = Variable(index=[time,country])
    Env_rwpp        = Variable(index=[time, regionwpp])
    Env_global      = Variable(index=[time])
    N               = Variable(index=[time, country])                  # Natural capital stock (million)

    function run_timestep(p, v, d, t)

        # Note that the country dimension is defined in d and parameters and variables are indexed by 'c'
        E0 = p.N0 .* p.flow
        v.E_bar = sum(E0[:]) / sum(p.l[TimestepIndex(1), :])

        for c in d.country, q in d.quantile

            if p.dam_assessment == 4                    # same N per capita, equal damages

                v.N[t,c] = is_first(t) ?
                ( (sum(p.N0[:])) / sum(p.l[TimestepIndex(1), :]) ) :
                (v.N[t-1,c] * (1-p.damage))

                v.Env[t, c, q] = v.N[t,c] * p.flow * (1 / p.nb_quantile)

            elseif p.dam_assessment == 3                # different E, equal damages

                v.N[t,c] = is_first(t) ?
                (p.N0[c]) :
                (v.N[t-1,c] * (1-p.damage))

                v.Env[t, c, q] = v.N[t,c] * p.flow * (1 / p.nb_quantile)

            elseif p.dam_assessment == 2                #same E, different damages
                v.Env[t, c, q] = is_first(t) ?          ###PROBLEM
                (v.E_bar * p.l[t,c] / p.nb_quantile) :
                (v.Env[TimestepIndex(1),c,q] * p.LOCAL_DAM_ENV[t,c])
                #((v.E_bar * p.l[TimestepIndex(1),c] / p.nb_quantile) * p.LOCAL_DAM_ENV[t,c])

            else
                v.N[t,c] = is_first(t) ?
                (p.N0[c]) :
                (p.N0[c] * p.LOCAL_DAM_ENV[t,c])

                v.Env[t, c, q] = v.N[t,c] * p.flow * (1 / p.nb_quantile)

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
