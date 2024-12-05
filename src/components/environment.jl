@defcomp environment begin

    country                 = Index()                           #Note that a regional index is defined here
    quantile		        = Index()

    l                       = Parameter(index=[time, country]) # Labor - population (thousands)
    nb_quantile             = Parameter()                      # Number of quantiles


    Env0                    = Parameter(index=[country])   # Initial level of environmental good
    Env                     = Variable(index=[time, country, quantile])   # Environmental variable
    Env_percapita           = Variable(index=[time, country, quantile])     #E percapita
    E_bar                   = Variable()                        # Average level of environment at time 0

    function run_timestep(p, v, d, t)
    # Note that the country dimension is defined in d and parameters and variables are indexed by 'c'

        for c in d.country, q in d.quantile
            v.Env[t,c,q] = is_first(t) ? (p.Env0[c] / p.nb_quantile) : v.Env[t-1,c,q]
        end

        for c in d.country, q in d.quantile
            #Assume environmental good is equally distributed
            v.Env_percapita[t,c,q] = (1 / p.nb_quantile) * (sum(v.Env[t,c,:]) / p.l[t,c])
        end

        v.E_bar = sum(p.Env0[:]) / sum(p.l[TimestepIndex(1),:])
    end

end #end component
