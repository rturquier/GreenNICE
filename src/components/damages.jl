# -----------------------------------------------------------
# Country-level Climate Damages
# -----------------------------------------------------------

@defcomp damages begin

    country             = Index() # Set country index

    temp_anomaly        = Parameter(index=[time]) # Global average surface temperature anomaly (°C above pre-industrial [year 1750]).
    local_temp_anomaly  = Parameter(index=[time, country]) # Country-level average surface temperature anomaly (°C above pre-industrial [year 1750]).
    β1_KW               = Parameter(index=[country]) # Linear damage coefficient on local temperature anomaly for Kalkuhl and Wenz based damage function
    β2_KW               = Parameter(index=[country])  # Quadratic damage coefficient on local temperature anomaly for Kalkuhl and Wenz based damage function

    LOCAL_DAMFRAC_KW    = Variable(index=[time, country]) # Country-level damages based on local temperatures and on Kalkuhl & Wenz (share of net output)

    ξ                   = Parameter(index=[country]) # Linear damage coeficient Natural capital loss (Bastien-Olvera et al. 2025)

    E_stock_temp_anomaly    = Variable(index=[time]) # Temperature anomaly with respect to year 2020 (°C above year 2020)

    LOCAL_DAM_ENV       = Variable(index=[time, country]) # Country-level damage function at country level. Based on Bastien-Olvera et al (2025))
    LOCAL_DAM_ENV_EQUAL = Variable(index=[time, country]) # Equal country-level damage function.  Average of Bastien-Olvera et al (2025) estimates

    function run_timestep(p, v, d, t)

        mean_ξ = mean(p.ξ[:]) # Mean of ξ across countries, used in LOCAL_DAM_ENV_EQUAL

        # Loop through countries.
        for c in d.country

        # Calculate country level damages (as share of GROSS output) based on country level temperature anomaly and Kalkuhl & Wenz coefficients, and store in temporary variable
		temp_LOCAL_DAMFRAC_KW_GROSS = p.β1_KW[c] * p.local_temp_anomaly[t,c] + p.β2_KW[c] *(p.local_temp_anomaly[t,c])^2

		# Convert the country level damages based Kalkuhl & Wenz coefficients from a share of GROSS output to a share of NET output, for use in other components
		# Y_net_of_damages = Y_gross/(1+DAMFRAC_net) = (1-DAMFRAC_gross)*Y_gross , so DAMFRAC_net = DAMFRAC_gross / (1-DAMFRAC_gross)
		v.LOCAL_DAMFRAC_KW[t,c] = temp_LOCAL_DAMFRAC_KW_GROSS / (1-temp_LOCAL_DAMFRAC_KW_GROSS)

            # Calculate changes in temperature with respect to year 2020 for damage function
            if is_first(t)
                v.E_stock_temp_anomaly[t] = 0
            else
                v.E_stock_temp_anomaly[t] = p.temp_anomaly[t] - p.temp_anomaly[TimestepIndex(1)]
            end

            #Calculate country-level damages on nat cap using Bastien-Olvera et al.'s (2024) coefficients.
            v.LOCAL_DAM_ENV[t,c] = 1 + p.ξ[c] * v.E_stock_temp_anomaly[t]
            v.LOCAL_DAM_ENV_EQUAL[t,c] = 1 + mean_ξ * v.E_stock_temp_anomaly[t]
        end

    end
end
