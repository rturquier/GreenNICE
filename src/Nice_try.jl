using Pkg
Pkg.activate(joinpath(@__DIR__))
Pkg.instantiate()

# Load required Julia packages.
using Mimi, MimiFAIRv2, DataFrames, CSVFiles

# Load NICE2020 source code.
include("nice2020_module.jl")

base_model = MimiNICE2020.create_nice2020()

nb_steps   = length(dim_keys(base_model, :time))
nb_country = length(dim_keys(base_model, :country))
nb_quantile = length(dim_keys(base_model, :quantile))

#Example linear uniform carbon tax pathway (not optimised), 2017 USD per tCO2
global_co2_tax = MimiNICE2020.linear_tax_trajectory(tax_start_value = 25, increase_value=5, year_tax_start=2025, year_tax_end=2200)

# Share of recycled carbon tax revenue that each region-quantile pair receives (row = country, column = quantile)
recycle_share = ones(nb_country,nb_quantile) .* 1/nb_quantile

#------------
# DIRECTORIES
#------------

output_NICEtry_BAU = joinpath(@__DIR__, "..", "results", "bau_no_policy_at_all")
mkpath(output_NICEtry_BAU)

output_NICEtry_TaxPolicy = joinpath(@__DIR__, "..", "results", "uniform_tax_example")
mkpath(output_NICEtry_TaxPolicy)

BAU_NICEtry = MimiNICE2020.create_nice2020()

update_param!(BAU_NICEtry, :abatement, :control_regime, 2)
update_param!(BAU_NICEtry, :abatement, :μ_input, zeros(nb_steps, nb_country))

run(BAU_NICEtry)

MimiNICE2020.save_nice2020_results(BAU_NICEtry, output_NICEtry_BAU, revenue_recycling=false)

#I am macking changes