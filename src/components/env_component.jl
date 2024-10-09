# -----------------------------------------------------------
# Environment
# -----------------------------------------------------------
# Measures Natural Capital Evolution

@defcomp environment begin
    
    country                 = Index()                           #Note that a regional index is defined here
    quantile		        = Index()
   
    Env                     = Variable(index=[time, country, quantile]) 

    function run_timestep(p, v, d, t)
    # Note that the country dimension is defined in d and parameters and variables are indexed by 'c'

        # Define an equation for Env
        for c in d.country
            for q in d.quantile
                v.Env[t,c,q] = 0.0
            end


        end


    end

end #end component
