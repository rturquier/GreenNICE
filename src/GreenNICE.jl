module GreenNICE

using Mimi, MimiFAIRv2, Statistics

# Calibration
include("../data/parameters.jl")

# Model components
include(joinpath("components", "gross_economy.jl"))
include(joinpath("components", "abatement.jl"))
include(joinpath("components", "emissions.jl"))
include(joinpath("components", "environment.jl"))
include(joinpath("components", "pattern_scale.jl"))
include(joinpath("components", "damages.jl"))
include(joinpath("components", "net_economy.jl"))
include(joinpath("components", "revenue_recycle.jl"))
include(joinpath("components", "quantile_recycle.jl"))
include(joinpath("components", "welfare.jl"))


function _set_dimensions!(m::Model)::Model
    quantiles = [
            "First",
            "Second",
            "Third",
            "Fourth",
            "Fifth",
            "Sixth",
            "Seventh",
            "Eighth",
            "Ninth",
            "Tenth"
        ]
	set_dimension!(m, :quantile, quantiles)
	set_dimension!(m, :country, Symbol.(countries))
	set_dimension!(m, :regionwpp, Symbol.(wpp_regions))  # 20 wpp regions
    return m
end


function _add_components!(m::Model)::Model
    # Add emissions and gross economy components before FAIR carbon cycle
	add_comp!(m, emissions, before = :co2_cycle)
	add_comp!(m, abatement, before = :emissions)
	add_comp!(m, grosseconomy, before = :abatement)

	# Couple pattern scaling, regional damages, and neteconomy after FAIR
	add_comp!(m, pattern_scale, after = :temperature)
	add_comp!(m, damages, after = :pattern_scale)
	add_comp!(m, neteconomy, after = :damages)
	add_comp!(m, revenue_recycle, after = :neteconomy)
	add_comp!(m, environment, after = :neteconomy)
	add_comp!(m, quantile_recycle, after = :revenue_recycle)
	add_comp!(m, welfare, after = :quantile_recycle)
    return m
end


function _add_shared_parameters!(m::Model)::Model
    nb_quantile = length(dim_keys(m, :quantile))
	add_shared_param!(m, :nb_quantile, 	nb_quantile)

    add_shared_param!(m, :switch_recycle, 0) # No revenue recycling by default
	add_shared_param!(m, :l, Matrix(pop), dims=[:time, :country])
	add_shared_param!(m, :mapcrwpp, map_country_region_wpp, dims=[:country])
	add_shared_param!(m, :η, 1.5)
	add_shared_param!(m, :σ, Matrix(emissionsrate), dims=[:time, :country])
	add_shared_param!(m, :s, Matrix(srate), dims=[:time, :country])
	add_shared_param!(m, :α, 0.1)
	add_shared_param!(m, :θ, 0.5)

    return m
end


function _connect_shared_parameters!(m::Model)::Model
    connect_param!(m, :grosseconomy, :l, :l)

    connect_param!(m, :environment, :l, :l)
    connect_param!(m, :environment, :nb_quantile, :nb_quantile)
    connect_param!(m, :environment, :mapcrwpp,  :mapcrwpp)

	connect_param!(m, :abatement, :s, :s)
	connect_param!(m, :abatement, :l, :l)
	connect_param!(m, :abatement, :η, :η)
	connect_param!(m, :abatement, :σ, :σ)

	connect_param!(m, :emissions, :mapcrwpp,  :mapcrwpp)
	connect_param!(m, :emissions, :σ, :σ)

	connect_param!(m, :neteconomy, :s, :s)
	connect_param!(m, :neteconomy, :l, :l)
	connect_param!(m, :neteconomy, :mapcrwpp,  :mapcrwpp)

	connect_param!(m, :revenue_recycle, :l, :l)
	connect_param!(m, :revenue_recycle, :switch_recycle, :switch_recycle)

	connect_param!(m, :quantile_recycle, :switch_recycle, :switch_recycle)
	connect_param!(m, :quantile_recycle, :l, 			:l)
	connect_param!(m, :quantile_recycle, :mapcrwpp,  :mapcrwpp)
	connect_param!(m, :quantile_recycle, :nb_quantile, 	:nb_quantile)

	connect_param!(m, :welfare, :η, :η)
	connect_param!(m, :welfare, :nb_quantile, :nb_quantile)
	connect_param!(m, :welfare, :l, :l)
	connect_param!(m, :welfare, :mapcrwpp,  :mapcrwpp)
	connect_param!(m, :welfare, :α, :α)
	connect_param!(m, :welfare, :θ, :θ)
    return m
end


function _connect_component_parameters!(m::Model)::Model
    # Syntax is:
    """
    connect_param!(
        model_name,
        :component_requiring_value => :name_of_required_value,
        :component_calculating_value => :name_of_calculated_value
    )
    """

    connect_param!(m, :grosseconomy    	=> :I, 					:neteconomy 		=> :I )
	connect_param!(m, :abatement 	   	=> :YGROSS, 			:grosseconomy 		=> :YGROSS)
	connect_param!(m, :emissions 	   	=> :YGROSS, 			:grosseconomy 		=> :YGROSS)
	connect_param!(m, :emissions 	   	=> :μ, 					:abatement 			=> :μ)
	connect_param!(m, :co2_cycle 	  	=> :E_co2, 				:emissions 			=> :E_Global_gtc)
	connect_param!(m, :pattern_scale   	=> :global_temperature,	:temperature 		=> :T)
	connect_param!(m, :damages 		   	=> :temp_anomaly, 		:temperature 		=> :T)
    connect_param!(m, :damages 	 	   	=> :local_temp_anomaly, :pattern_scale 		=> :local_temperature)
	connect_param!(m, :neteconomy 	   	=> :ABATEFRAC, 			:abatement 			=> :ABATEFRAC)
	connect_param!(m, :neteconomy 	  	=> :LOCAL_DAMFRAC_KW, 	:damages 			=> :LOCAL_DAMFRAC_KW)
	connect_param!(m, :neteconomy 	   	=> :YGROSS, 			:grosseconomy 		=> :YGROSS )
	connect_param!(m, :revenue_recycle 	=> :E_gtco2, 			:emissions			=> :E_gtco2)
	connect_param!(m, :revenue_recycle 	=> :LOCAL_DAMFRAC_KW,	:damages 			=> :LOCAL_DAMFRAC_KW)
	connect_param!(m, :revenue_recycle 	=> :country_carbon_tax,	:abatement 			=> :country_carbon_tax)
	connect_param!(m, :revenue_recycle  => :Y, 					:neteconomy 		=> :Y)
	connect_param!(m, :quantile_recycle => :ABATEFRAC,			:abatement 			=> :ABATEFRAC)
	connect_param!(m, :quantile_recycle => :LOCAL_DAMFRAC_KW,	:damages 			=> :LOCAL_DAMFRAC_KW)
	connect_param!(m, :quantile_recycle => :CPC, 				:neteconomy 		=> :CPC)
	connect_param!(m, :quantile_recycle => :Y,					:neteconomy 		=> :Y)
	connect_param!(m, :quantile_recycle => :Y_pc,				:neteconomy 		=> :Y_pc)
	connect_param!(m, :quantile_recycle => :country_pc_dividend,:revenue_recycle	=> :country_pc_dividend)
	connect_param!(m, :quantile_recycle => :tax_pc_revenue,		:revenue_recycle	=> :tax_pc_revenue)
    connect_param!(m, :environment      => :LOCAL_DAM_ENV,      :damages            => :LOCAL_DAM_ENV)
    connect_param!(m, :environment      => :LOCAL_DAM_ENV_EQUAL,:damages            => :LOCAL_DAM_ENV_EQUAL)
	connect_param!(m, :welfare 			=> :E_flow_percapita, 	:environment		=> :E_flow_percapita)
	connect_param!(m, :welfare 			=> :E_bar, 				:environment		=> :E_bar)
	connect_param!(m, :welfare 			=> :qcpc_post_recycle, 	:quantile_recycle	=> :qcpc_post_recycle)

    return m
end


function _set_default_values!(m::Model)::Model
    nb_quantile = length(dim_keys(m, :quantile))
	nb_country = length(dim_keys(m, :country))
    nb_year = length(dim_keys(m, :time))

    paris_target_abatement_rate = 0.8

    FAIR_initial_values_2020 = Dict(
        (:aerosol_plus_cycles, :aerosol_plus_0) => init_aerosol[:, :concentration],
        (:aerosol_plus_cycles, :R0_aerosol_plus) => Matrix(init_aerosol[:, [:R1, :R2, :R3, :R4]]),
        (:aerosol_plus_cycles, :GU_aerosol_plus_0) => init_aerosol[:, :GU],

        (:ch4_cycle, :ch4_0) => init_ch4[1,:concentration],
        (:ch4_cycle, :R0_ch4) => vec(Matrix(init_ch4[!, [:R1, :R2, :R3, :R4]])),
        (:ch4_cycle, :GU_ch4_0) => init_ch4[1,:GU],

        (:co2_cycle, :co2_0) => init_co2[1,:concentration],
        (:co2_cycle, :R0_co2) => vec(Matrix(init_co2[!, [:R1, :R2, :R3, :R4]])),
        (:co2_cycle, :GU_co2_0) => init_co2[1,:GU],

        (:flourinated_cycles, :flourinated_0) => init_flourinated[!,:concentration],
        (:flourinated_cycles, :R0_flourinated) => Matrix(init_flourinated[!, [:R1, :R2, :R3, :R4]]),
        (:flourinated_cycles, :GU_flourinated_0) => init_flourinated[!,:GU],

        (:montreal_cycles, :montreal_0) => init_montreal[!,:concentration],
        (:montreal_cycles, :R0_montreal) => Matrix(init_montreal[!, [:R1, :R2, :R3, :R4]]),
        (:montreal_cycles, :GU_montreal_0) => init_montreal[!,:GU],

        (:n2o_cycle, :n2o_0) => init_n2o[1,:concentration],
        (:n2o_cycle, :R0_n2o) => vec(Matrix(init_n2o[!, [:R1, :R2, :R3, :R4]])),
        (:n2o_cycle, :GU_n2o_0) => init_n2o[1,:GU],

        (:temperature, :Tj_0) => init_tj[!,:Tj],
        (:temperature, :T_0) => init_temperature[1,:Temperature],
    )
    other_defaults = Dict(
        (:grosseconomy, :tfp) => Matrix(productivity),
        (:grosseconomy, :depk) => Matrix(depreciation),
        (:grosseconomy, :k0) => k0,
        (:grosseconomy, :share) => 0.3,

        (:environment, :E_stock0) => E_stock0,
        (:environment, :dam_assessment) => 1,

        (:abatement, :control_regime) => 3,  # 1:"global_carbon_tax", 2:"country_carbon_tax", 3:"country_abatement_rate"
        (:abatement, :global_carbon_tax) => zeros(nb_year),
        (:abatement, :reference_carbon_tax) => zeros(nb_year),
        (:abatement, :reference_country_index) => findfirst(x -> x == "USA", countries),
        (:abatement, :μ_input) => zeros(nb_year, nb_country) .+ paris_target_abatement_rate,
        (:abatement, :θ2) => 2.6,
        (:abatement, :pbacktime) => full_pbacktime,

        (:emissions, :co2_pulse) => zeros(nb_year),

        (:pattern_scale, :β_temp) => cmip_pattern,

        (:damages, :β1_KW) => beta1_KW,
        (:damages, :β2_KW) => beta2_KW,
        (:damages, :ξ) => ξ,

        (:revenue_recycle, :switch_scope_recycle) => 0,
        (:revenue_recycle, :switch_global_pc_recycle) => 0,
        (:revenue_recycle, :global_recycle_share) => zeros(nb_country),
        (:revenue_recycle, :lost_revenue_share) => 0.0,

        (:quantile_recycle, :min_study_gdp) => meta_min_study_gdp,  # minimum(elasticity_studies.pcGDP)
        (:quantile_recycle, :max_study_gdp) => meta_max_study_gdp,  # maximum(elasticity_studies.pcGDP)
        (:quantile_recycle, :elasticity_intercept) => meta_intercept,
        (:quantile_recycle, :elasticity_slope) => meta_slope,
        (:quantile_recycle, :damage_elasticity) => 0.6,  # Gilli et al. (2024), estimate based on SSP2 projection
        (:quantile_recycle, :quantile_consumption_shares) => consumption_distribution_2020_2300,
        # (:quantile_recycle, :quantile_consumption_shares) => consumption_distribution, # Static version
        (:quantile_recycle, :recycle_share) => ones(nb_country, nb_quantile) .* 1 / nb_quantile,
        (:quantile_recycle, :γ) => 1.0,  # change in income distribution
    )
    all_defaults = merge(FAIR_initial_values_2020, other_defaults)

    update_params!(m, all_defaults)
    return m
end

function _set_custom_values!(m, parameters)
    # allow diffent types of keys and values to avoid type errors when setting a new value
    parameters = Dict{Union{Symbol, Tuple{Symbol, Symbol}}, Any}(parameters)

    E_multiplier = pop!(parameters, :E_multiplier, 1)
    parameters[:environment, :E_stock0] = E_stock0 * E_multiplier

    update_params!(m, parameters)
    return m
end

function create(; parameters::Dict=Dict())::Model
	m = MimiFAIRv2.get_model(
        emissions_forcing_scenario="ssp245",
        start_year=2020,
        end_year=2300,
        param_type = "Number"
    )

    _set_dimensions!(m)
    _add_components!(m)
    _add_shared_parameters!(m)
    _connect_shared_parameters!(m)
    _connect_component_parameters!(m)
    _set_default_values!(m)
    _set_custom_values!(m, parameters)

    return m
end

end #module
