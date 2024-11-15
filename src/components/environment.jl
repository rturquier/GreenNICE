@defcomp environment begin

    country                 = Index()                           #Note that a regional index is defined here
    quantile		        = Index()

    Env0                    = Parameter(index=[country])   # Initial level of environmental good
    Env                     = Variable(index=[time, country, quantile])   # Environmental variable
    E_bar                   = Variable()                        # Average level of environment at time 0

    function run_timestep(p, v, d, t)
    # Note that the country dimension is defined in d and parameters and variables are indexed by 'c'

        v.E_bar = mean(p.Env0)/1000

        for c in d.country, q in d.quantile
            v.Env[t,c,q] = 100
            #is_first(t) ? p.Env0[c]/100 : v.Env[t-1,c,q]
        end

    end


end #end component
