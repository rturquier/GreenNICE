# -----------------------------------------------------------
# Country-level Climate Damages
# -----------------------------------------------------------

@defcomp damages begin

    country      = Index() # Set country index

    local_temp_anomaly = Parameter(index=[time, country]) # Country-level average surface temperature anomaly (°C above pre-industrial [year 1750]).
    β1_KW              = Parameter(index=[country]) # Linear damage coefficient on local temperature anomaly for Kalkuhl and Wenz based damage function
    β2_KW              = Parameter(index=[country])  # Quadratic damage coefficient on local temperature anomaly for Kalkuhl and Wenz based damage function

    θ_env              = Parameter(index=[country]) # Linear damage coeficient Natural capital loss

    LOCAL_DAMFRAC_KW   = Variable(index=[time, country]) # Country-level damages based on local temperatures and on Kalkuhl & Wenz (share of net output)

    LOCAL_DAM_ENV      = Variable(index=[time, country]) # Country-level damages based on local tempertures and on Bastien-Olvera et al parameters
    temp_anomaly_N    = Variable(index=[time]) # 2020 temperature anomaly (°C above year 2020)

    function run_timestep(p, v, d, t)

        # Loop through countries.
        for c in d.country

        	# Calculate country level damages (as share of GROSS output) based on country level temperature anomaly and Kalkuhl & Wenz coefficients, and store in temporary variable
		temp_LOCAL_DAMFRAC_KW_GROSS = p.β1_KW[c] * p.local_temp_anomaly[t,c] + p.β2_KW[c] *(p.local_temp_anomaly[t,c])^2

		# Convert the country level damages based Kalkuhl & Wenz coefficients from a share of GROSS output to a share of NET output, for use in other components
		# Y_net_of_damages = Y_gross/(1+DAMFRAC_net) = (1-DAMFRAC_gross)*Y_gross , so DAMFRAC_net = DAMFRAC_gross / (1-DAMFRAC_gross)
		v.LOCAL_DAMFRAC_KW[t,c] = temp_LOCAL_DAMFRAC_KW_GROSS / (1-temp_LOCAL_DAMFRAC_KW_GROSS)

            # Calculate changes in temperature with respect to year 2020 (N Damage function).
            if is_first(t)
                v.temp_anomaly_N[t] = 0
            else
                v.temp_anomaly_N[t] = p.temp_anomaly[t] - p.temp_anomaly[TimestepIndex(1)]
            end

            #Calculate country-level damages on nat cap using Bastien-Olvera et al.'s (2024) coefficients.
            v.LOCAL_DAM_ENV[t,c] = 1 + p.θ_env[c] * v.temp_anomaly_N[t]

        end


    end
end
