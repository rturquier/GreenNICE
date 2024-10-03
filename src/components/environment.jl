# -----------------------------------------------------------
# Environment
# -----------------------------------------------------------
# Measures NAtural Capital Evolution

@defcomp environmentdynamic begin
    
    country = Index()                           #Note that a regional index is defined here
    E0      = Parameter(index=[country])        # Initial level of environmental good (1e6 USD2017)
   
    E       = Variable(index=[time, country])   # Environmental good (1e6 USD2017)

    function run_timestep(p, v, d, t)
    # Note that the country dimension is defined in d and parameters and variables are indexed by 'c'

        # Define an equation for K
        for c in d.country
            if is_first(t)
                v.E[t,c] = p.E0[c]
            else
                
                v.E[t,c] = v.E[t-1,c] 
                 
            end
        end


    end

end #end component
