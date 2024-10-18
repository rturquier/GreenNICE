# -----------------------------------------------------------
# Environment
# -----------------------------------------------------------
# Measures Natural Capital Evolution

@defcomp environment begin
    
    country                 = Index()                           #Note that a regional index is defined here
    quantile		        = Index()

    Env0                   = Parameter(index=[country])   # Initial level of environmental quality
   
    Env                     = Variable(index=[time, country, quantile])   # Environmental quality

    E_bar                  = Variable()                        # Average level of environment at time 0

    

    function run_timestep(p, v, d, t)
    # Note that the country dimension is defined in d and parameters and variables are indexed by 'c'


    v.E_bar = mean(p.Env0)/1000

        for c in d.country
            for q in d.quantile
                    if is_first(t)
                    v.Env[t,c,q] = p.Env0[c]/100
                    else
                    v.Env[t,c,q] = v.Env[t-1,c,q]*1
                    end #end if
            end #end quantile loop
        end #end country loop
    
    
    end 


end #end component
