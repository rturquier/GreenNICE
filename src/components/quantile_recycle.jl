@defcomp quantile_recycle begin

    country          = Index()
    regionwpp       = Index()
	quantile		 = Index()

    ABATEFRAC               	= Parameter(index=[time, country])      		# Cost of CO2 emission reductions (share of gross economic output)
    LOCAL_DAMFRAC_KW            = Parameter(index=[time, country])              # Country-level damages based on local temperatures and on Kalkuhl & Wenz (share of net output)
    CPC                     	= Parameter(index=[time, country])      		# Country level consumption per capita (thousand USD2017 per person per year)
	l           				= Parameter(index=[time, country])  			# Country population (thousands)
	mapcrwpp   				    = Parameter(index=[country])        			# Map from country index to wpp region index
	Y           				= Parameter(index=[time, country]) 				# Output net of damages and abatement costs (1e6 USD2017 per year)
    Y_pc                        = Parameter(index=[time, country]) 	            # Per capita output net of abatement and damages (USD2017 per person per year)
    country_pc_dividend 	    = Parameter(index=[time, country]) 				# Total per capita carbon tax revenue, including any international transfers (thousand USD2017 per person per year)
    tax_pc_revenue              = Parameter(index=[time, country])              # Carbon tax revenue per capita from country emissions  (thousand USD2017 per person per year)
    switch_recycle              = Parameter()                                   # Switch recycling of tax revenues
    nb_quantile                	= Parameter(default=10)							# Number of quantiles
	min_study_gdp               = Parameter()                          			# Minimum observed per capita GDP value found in elasticity studies (USD2017 per person)
    max_study_gdp            	= Parameter()                          			# Maximum observed per capita GDP value found in elasticity studies (USD2017 per person)
    elasticity_intercept     	= Parameter()                          			# Intercept term to estimate time-varying income elasticity
    elasticity_slope         	= Parameter()                          			# Slope term to estimate time-varying income elasticity
    damage_elasticity        	= Parameter()                          			# Income elasticity of climate damages (1 = proportional to income)
	quantile_consumption_shares = Parameter(index=[time, country, quantile]) 	# Income shares of deciles
    recycle_share           	= Parameter(index=[country, quantile]) 		    # Share of carbon tax revenue recycled back to each quantile
    γ                           = Parameter()                                   # Change in income distribution parameter

    adjusted_consumption_shares = Variable(index=[time, country, quantile])     # Adjusted shares of deciles (equals `quantile_consumption_shares` for γ == 1)
    CO2_income_elasticity    	= Variable(index=[time, country])             	# Elasticity of CO2 price exposure with respect to income
    abatement_cost_dist		 	= Variable(index=[time, country, quantile]) 	# Quantile distribution shares of mitigation costs
    carbon_tax_dist		     	= Variable(index=[time, country, quantile]) 	# Quantile distribution shares of CO2 tax burden
    damage_dist					= Variable(index=[time, country, quantile]) 	# Quantile distribution shares of climate damages

	qcpc_base                  	= Variable(index=[time, country, quantile])  	# Pre-damage, pre-abatement cost, pre-tax quantile consumption per capita (thousand USD2017 per person per year)
	qcpc_damages             	= Variable(index=[time, country, quantile])  	# Damages to per-capita consumption in each quantile
    qcpc_post_damage_abatement 	= Variable(index=[time, country, quantile])  	# Post-damage, post-abatement cost per capita quantile consumption (thousand USD2017 per person per year)
    qcpc_post_tax              	= Variable(index=[time, country, quantile])  	# Quantile per capita consumption after subtracting out carbon tax (thousand USD2017 per person per year)
    qcpc_post_recycle          	= Variable(index=[time, country, quantile])  	# Quantile per capita consumption after recycling tax back to quantiles (thousand USD2017 per person per year)
    qc_share				 	= Variable(index=[time, country, quantile])  	# Quantile share of per capita consumption (%)
	sum_qcpc_post_recycle  	 	= Variable(index=[time, country]) 				# Sum of quantiles consumption per capita after abatement, damages and revenue recycling (thousand USD2017 per (capita per quantile) per year)
    CPC_post                    = Variable(index=[time, country])               # Country consumption per capita post recycle (thousand USD2017 per person per year)
    CPC_post_rwpp               = Variable(index=[time, regionwpp])             # Region consumption per capita post recycle (thousand USD2017 per person per year)
    CPC_post_global             = Variable(index=[time])                        # Global consumption per capita post recycle (thousand USD2017 per person per year)

	gini_cons          		 	= Variable(index=[time, country])				# Country consumption gini (%)
    gini_cons_rwpp              = Variable(index=[time, regionwpp])             # Region consumption gini (%)
    gini_cons_global            = Variable(index=[time])                        # Global consumption gini (%)
	mu_cons				        = Variable(index=[time, country])				# Parameter mu of the lognormal distribution of consumption
	sigma_cons			        = Variable(index=[time, country])				# Parameter sigma of the lognormal distribution of consumption


    function run_timestep(p, v, d, t)

        # temporary variable for global population in t
        temp_pop_global = sum(p.l[t,:])

        #temporary variable for quantile population in t (country x quantile)
        temp_pop_quantile = repeat( (p.l[t,:] / p.nb_quantile), 1, p.nb_quantile) # all quantiles within a country have same pop, by definition

        for c in d.country

            ########################################################################################################
            ## Calculate time-varying income elasticity of CO2 price exposure (requires  Y_pc units in $/person).
            # Note, hold elasticity constant at boundary value if GDP falls outside the study support range.

            if p.Y_pc[t,c] < p.min_study_gdp
               # GDP below observed study values.
               v.CO2_income_elasticity[t,c] = p.elasticity_intercept + p.elasticity_slope * log(p.min_study_gdp)
           elseif p.Y_pc[t,c] > p.max_study_gdp
               # GDP above observed study values.
               v.CO2_income_elasticity[t,c] = p.elasticity_intercept + p.elasticity_slope * log(p.max_study_gdp)
           else
               #GDP within observed study values.
               v.CO2_income_elasticity[t,c] = p.elasticity_intercept + p.elasticity_slope * log(p.Y_pc[t,c])
           end

            #################################################
            ## Compute consumption distributions for quantiles
            #################################################

           #Update consumption shares for a given γ

           v.adjusted_consumption_shares[t,c,:] = adjust_inequality(p.quantile_consumption_shares[t,c,:], p.γ)

            # Calculate quantile distribution shares of CO2 tax burden and mitigation costs (assume both distributions are equal) and climate damages.
			v.abatement_cost_dist[t,c,:] = rescale_distribution(v.adjusted_consumption_shares[t,c,:], v.CO2_income_elasticity[t,c])
			v.carbon_tax_dist[t,c,:]     = rescale_distribution(v.adjusted_consumption_shares[t,c,:], v.CO2_income_elasticity[t,c])
			v.damage_dist[t,c,:]         = rescale_distribution(v.adjusted_consumption_shares[t,c,:], p.damage_elasticity)

			# Create a temporary variable used to calculate NICE baseline quantile consumption (just for convenience).
			temp_qcpc = p.nb_quantile * p.CPC[t,c] * (1.0 + p.LOCAL_DAMFRAC_KW[t,c]) / (1.0 - p.ABATEFRAC[t,c])
			for q in d.quantile

				# Calculate pre-damage, pre-abatement cost quantile consumption.
				v.qcpc_base[t,c,q] = temp_qcpc * v.adjusted_consumption_shares[t,c,q]

				# Calculate post-damage, post-abatement cost per capita quantile consumption (bounded below to ensure consumptions don't collapse to zero or go negative).
				# Note, this differs from standard NICE equation because quantile CO2 abatement cost and climate damage shares can now vary over time.
                v.qcpc_damages[t, c, q] = (
                    p.nb_quantile
                    * p.CPC[t,c]
                    * p.LOCAL_DAMFRAC_KW[t,c]
                    * v.damage_dist[t,c,q]
                )
				v.qcpc_post_damage_abatement[t,c,q] = max(
                    v.qcpc_base[t,c,q]
                    - v.qcpc_damages[t, c, q]
                    - (temp_qcpc * p.ABATEFRAC[t,c] * v.abatement_cost_dist[t,c,q]),
                    1e-8
                )

				# Subtract tax revenue from each quantile based on quantile CO2 tax burden distributions.
				# Note, per capita tax revenue and consumption should both be in $1000/person.
				v.qcpc_post_tax[t,c,q] =  v.qcpc_post_damage_abatement[t,c,q] - (p.nb_quantile * p.tax_pc_revenue[t,c] * v.carbon_tax_dist[t,c,q])

				# Recycle tax revenue by adding shares back to all quantiles
				if p.switch_recycle==0 # In the NO revenue recycling case (distributionally neutral), refund tax revenues equal to the initial burden

					v.qcpc_post_recycle[t,c,q] = v.qcpc_post_tax[t,c,q] + (p.nb_quantile * p.tax_pc_revenue[t,c] * v.carbon_tax_dist[t,c,q])

				elseif p.switch_recycle==1 # In the revenue recycling case, distribute divididends from country and/or global tax revenue (assume recycling shares constant over time)

					v.qcpc_post_recycle[t,c,q] = v.qcpc_post_tax[t,c,q] + (p.nb_quantile * p.country_pc_dividend[t,c] * p.recycle_share[c,q])
				end

			end # quantile

			#calculate sum of quantile CPC consumption (to calculate consumption shares at later stage)
			v.sum_qcpc_post_recycle[t,c] = sum(v.qcpc_post_recycle[t,c,:])

            # CPC = (sum  quantile_pop* quantile_cpc) / population = (population/nb_quantile * (sum quantile_cpc)) / population = (sum quantile_cpc) / nb_quantile
            v.CPC_post[t,c] = v.sum_qcpc_post_recycle[t,c] / p.nb_quantile

            v.qc_share[t,c,:] .= v.qcpc_post_recycle[t,c,:]./ v.sum_qcpc_post_recycle[t,c]*100

            #################
            ## Compute Gini
            ################

			#gini consumption
            v.gini_cons[t,c] =  gini(convert(Vector{Real}, v.qc_share[t,c,:])) *100

            if !(v.gini_cons[t,c]  > 0 && v.gini_cons[t,c] <100)
                v.gini_cons[t,c] = missing
            end
        end # country loop

        for rwpp in d.regionwpp
            country_indices = findall(x->x==rwpp , p.mapcrwpp) #Country indices for the region

            v.CPC_post_rwpp[t,rwpp] = sum(p.l[t,country_indices] .* v.CPC_post[t, country_indices]) / sum(p.l[t,country_indices])
            v.gini_cons_rwpp[t,rwpp] = gini(convert(Vector{Real},vec(v.qcpc_post_recycle[t,country_indices,:])), convert(Vector{Real},vec(temp_pop_quantile[country_indices,:])))*100

        end # region loop

        v.CPC_post_global[t] = sum(v.sum_qcpc_post_recycle[t,:] .* p.l[t,:] ./ p.nb_quantile) / temp_pop_global
        v.gini_cons_global[t] = gini(convert(Vector{Real},vec(v.qcpc_post_recycle[t,:,:])), convert(Vector{Real},vec(temp_pop_quantile))) *100

    end # timestep
end


"""
    adjust_inequality(consumption_shares::Vector, γ::Real)

Adjust income distribution in a given country and time by a given γ.

For γ = 1, there is no change. For γ = 0, the consumption of every quantile is set to
average consumption.

# Arguments
- quantile_consumption_shares::Vector: consumption deciles in a given country and year
- γ::Real: parameter that controls the degree of inequality.
"""
function adjust_inequality(quantile_consumption_shares::Vector, γ::Real)

    average_consumption = mean(quantile_consumption_shares)

    δ = (quantile_consumption_shares .- average_consumption) ./ average_consumption

    adjusted_quantile_consumption_shares = average_consumption .* (1 .+ δ .* γ)

    return adjusted_quantile_consumption_shares
end


"""
    rescale_distribution(income_shares::Vector, elasticity::Real)

Calculate quantile distribution shares for a country based on a provided elasticity.

This function returns a vector of the same size as `income_shares`, that sums to 1,
and contains a rescaled distribution. If `elasticity` is 0, it returns a vector of
identical values that sum to 1. If `elasticity` is 1, the returned distribution is
proportional to `income_shares`.

It is used to calculate distributions of damages, CO₂ mitigation cost, or
CO₂ tax burden, across a country's quantiles.

# Arguments
- income_shares::Vector: a vector of quantile income shares for a given country.
- elasticity::Real: Income elasticity of climate damages, CO₂ mitigation costs,
    CO₂ tax burdens, etc.
"""
function rescale_distribution(income_shares::Vector, elasticity::Real)
    scaled_shares = income_shares .^ elasticity
    updated_quantile_distribution = scaled_shares / sum(scaled_shares)
    return updated_quantile_distribution
end



"""
    gini(v)

Compute the Gini Coefficient of a vector `v` .

This function and its documentation is taken from JosepER's Inequality package, available at
https://github.com/JosepER/Inequality.jl under the MIT licence. The package is not imported
in the project because it is no longer maintained, and prevented updating other packages.
If we don't use the Gini index in the end, we can remove this function.

# Examples
```julia
julia> using Inequality
julia> gini([8, 5, 1, 3, 5, 6, 7, 6, 3])
0.2373737373737374
```
"""
function gini(v::AbstractVector{<:Real})::Float64
    (
        2 * sum([x*i for (i,x) in enumerate(sort(v))])
          / sum(sort(v))
        - (length(v)+1)
    ) / (length(v))
end


"""
    gini(v, w)

Compute the weighted Gini Coefficient of a vector `v` using weights given by a weight vector `w`.

Weights must not be negative, missing or NaN. The weights and data vectors must have the same length.

# Examples
```julia
julia> gini([8, 5, 1, 3, 5, 6, 7, 6, 3], collect(0.1:0.1:0.9))
0.20652395514780775
```
"""
function gini(v::AbstractVector{<:Real}, w::AbstractVector{<:Real})::Float64

    checks_weights(v, w)

    w = w[sortperm(v)]/sum(w)
    v = sort(v)
    p = cumsum(w)
    nᵤ = cumsum(w .* v)/cumsum(w .* v)[end]
    sum(nᵤ[2:end] .* p[1:(end-1)]) - sum(nᵤ[1:(end-1)] .* p[2:end])

end


"""
    checks_weights(v::AbstractVector{<:Real}, w::AbstractVector{<:Real})

Check weights used in [`gini`](@gini). Copied from the Inequality package.
"""
function checks_weights(v::AbstractVector{<:Real}, w::AbstractVector{<:Real})
    length(v) == length(w) ? nothing : throw(ArgumentError("`v` and `w` vectors must be the same size, got $(length(v)) and $(length(w))"))
    any([isnan(x) for x in w]) ? throw(ArgumentError("`w` vector cannot contain NaN values")) : nothing
    all(w .>= 0) ? nothing : throw(ArgumentError("`w` vector cannot contain negative entries"))
 end
