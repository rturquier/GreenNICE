# -----------------------------------------------------------
# Regional Climate Damages
# -----------------------------------------------------------

@defcomp damages begin

    country      = Index() # Set a Mimi index for the modeled regions.

    β1                 = Parameter() # Linear damage coefficient on temperature.
    β2                 = Parameter() # Power damage coefficient on temperature.
    temp_anomaly       = Parameter(index=[time]) # Global average surface temperature anomaly (°C above pre-industrial [year 1750]).
    local_temp_anomaly = Parameter(index=[time, country]) # Country-level average surface temperature anomaly (°C above pre-industrial [year 1750]).
    β1_KW              = Parameter(index=[country]) # Linear damage coefficient on local temperature anomaly for Kalkuhl and Wenz based damage function
    β2_KW              = Parameter(index=[country])  # Quadratic damage coefficient on local temperature anomaly for Kalkuhl and Wenz based damage function

    θ_env              = Parameter(index=[country]) #Linear damage coeficient Natural capital loss

    LOCAL_DAMFRAC_KW   = Variable(index=[time, country]) # Country-level damages based on local temperatures and on Kalkuhl & Wenz (share of net output)
    DAMFRAC            = Variable(index=[time, country]) # Country-level damages based on global temperatures (share of net outpu)

    LOCAL_DAM_ENV      = Variable(index=[time, country]) #Country-level damages based on local tempertures and on Bastien-Olvera et al parameters ()
    temp_anomaly_N     = Variable(index=[time, country]) # 2020 temperature anomaly (°C above year 2020)

    function run_timestep(p, v, d, t)

        # Loop through countries.
        for c in d.country

            # Calculate country level damages based on global temperatures.
            v.DAMFRAC[t,c] = p.β1 * p.temp_anomaly[t] ^ p.β2

            # Calculate country level damages based on country level temperature anomaly and Kalkuhl & Wenz coefficients
            v.LOCAL_DAMFRAC_KW[t,c] = p.β1_KW[c] * p.local_temp_anomaly[t,c] + p.β2_KW[c] *(p.local_temp_anomaly[t,c])^2

            v.temp_anomaly_N[t, c] = is_first(t) ?
            (p.local_temp_anomaly[t,c] - p.local_temp_anomaly[t,c]) :
            (p.local_temp_anomaly[t,c] - p.local_temp_anomaly[TimestepIndex(1),c])

            #Calculate country-level damages on nat cap using Bastien-Olvera et al.'s coefficients.
            v.LOCAL_DAM_ENV[t,c] = 1 + p.θ_env[c] * v.temp_anomaly_N[t,c]

        end


    end
end
