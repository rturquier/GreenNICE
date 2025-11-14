@defcomp environment begin
    country     = Index()                           #Note that a regional index is defined here
    quantile    = Index()
    regionwpp   = Index()                           #WPP regions

    l               = Parameter(index=[time, country])      # Labor - population (thousands)
    nb_quantile     = Parameter()                           # Number of quantiles
    mapcrwpp        = Parameter(index=[country])

    E_stock0        = Parameter(index=[country])            # Initial level of stock Natural capital (2017 million USD)

    LOCAL_DAM_ENV       = Parameter(index=[time,country])  # Damage factor by country
    LOCAL_DAM_ENV_EQUAL = Parameter(index=[time,country])  # Damage factor by country, assuming equal damages

    dam_assessment  = Parameter()                           #Switch to determine type of assessment

    E_stock             = Variable(index=[time, country])               # Stock of Natural capital (2017 million usd)
    E_flow              = Variable(index=[time, country, quantile])     # Flow of natural capital (2017 million usd per quantile per year)
    E_bar               = Variable()                                    # Average level of environment per capita at time 0 (thousand usd per capita)
    E_flow_percapita    = Variable(index=[time, country, quantile])     # Flow of natural capital per capita (2017 thousand usd per capita)
    E_flow_country      = Variable(index=[time,country])                # Flow of natural capital per country (2017 million usd per year)
    E_flow_rwpp         = Variable(index=[time, regionwpp])             # Flow of natural capital per WPP region (2017 million usd per year)
    E_flow_global       = Variable(index=[time])                        # Flow of natural capital globally (2017 million usd per year)

    function run_timestep(p, v, d, t)

        E_discount_rate = 0.04

        stock_to_flow_factor    = (1 - E_discount_rate) / (1 - E_discount_rate^100)

        E_stock0_percapita = (sum(p.E_stock0[:])) / sum(p.l[TimestepIndex(1), :])

        v.E_bar = E_stock0_percapita * stock_to_flow_factor

        for c in d.country, q in d.quantile

            if p.dam_assessment == 4                    # same E stock per capita, equal damages

                v.E_stock[t,c] = is_first(t) ?
                (E_stock0_percapita * p.l[t,c]) :
                (v.E_stock[TimestepIndex(1),c] * p.LOCAL_DAM_ENV_EQUAL[t,c])

            elseif p.dam_assessment == 3                # different E stock per capita, equal damages

                v.E_stock[t,c] = is_first(t) ?
                (p.E_stock0[c]) :
                (p.E_stock0[c] * p.LOCAL_DAM_ENV_EQUAL[t,c])

            elseif p.dam_assessment == 2                #same E, different damages

                v.E_stock[t,c] = is_first(t) ?
                (E_stock0_percapita * p.l[t,c]) :
                (v.E_stock[TimestepIndex(1),c] * p.LOCAL_DAM_ENV[t,c])

            else

                v.E_stock[t,c] = is_first(t) ?
                (p.E_stock0[c]) :
                (p.E_stock0[c] * p.LOCAL_DAM_ENV[t,c])

            end

            v.E_flow[t, c, q] = v.E_stock[t,c] * stock_to_flow_factor * (1 / p.nb_quantile)

            v.E_flow_percapita[t, c, q] = v.E_flow[t,c,q] / (p.l[t,c] / p.nb_quantile)
        end

        #Evolution of E_flow over time for plots

        for c in d.country, q in d.quantile
            v.E_flow_country[t,c] = sum(v.E_flow[t,c,:])
        end

        for rwpp in d.regionwpp
            country_indices = findall(x -> x == rwpp, p.mapcrwpp)
            v.E_flow_rwpp[t,rwpp] = sum(v.E_flow_country[t,country_indices])
        end

        v.E_flow_global[t] = sum(v.E_flow_country[t,:])


    end
end #end component
