##Check that the model runs

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
#Pkg.resolve() # To resolve inconsistencies between Manifest.toml and Project.toml
Pkg.instantiate()

# Load required Julia packages.
using Mimi, MimiFAIRv2, DataFrames, CSVFiles

println("Load NICE2020 source code.")
# Load NICE2020 source code.
include("nice2020_module.jl")


println("Testing changes in Env component.")

Env_1 = MimiNICE2020.create_nice2020()

nb_steps   = length(dim_keys(Env_1, :time))
nb_country = length(dim_keys(Env_1, :country))
nb_quantile = length(dim_keys(Env_1, :quantile))

run(Env_1)

#Save results
output_directory_Env_1 = joinpath(@__DIR__, "..", "results", "Env_1")
mkpath(output_directory_Env_1)

MimiNICE2020.save_nice2020_results(Env_1, output_directory_Env_1, revenue_recycling=false)


####Make changes in Env function

include("nice2020_module.jl")

Env_2 = MimiNICE2020.create_nice2020()
run(Env_2)

output_directory_Env_2 = joinpath(@__DIR__, "..", "results", "Env_2")
mkpath(output_directory_Env_2)

MimiNICE2020.save_nice2020_results(Env_2, output_directory_Env_2, revenue_recycling=false)

explore(Env_2)
explore(Env_1)

####Make changes in Env function

include("nice2020_module.jl")

Env_3 = MimiNICE2020.create_nice2020()
run(Env_3)

output_directory_Env_3 = joinpath(@__DIR__, "..", "results", "Env_3")
mkpath(output_directory_Env_3)

MimiNICE2020.save_nice2020_results(Env_3, output_directory_Env_3, revenue_recycling=false)

explore(Env_3)

Env_4 = MimiNICE2020.create_nice2020()
update_param!(Env_4, :α, 0.0)

run(Env_4)

explore(Env_4)