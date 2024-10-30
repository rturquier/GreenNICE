##Check that the model runs

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
#Pkg.resolve() # To resolve inconsistencies between Manifest.toml and Project.toml
Pkg.instantiate()

# Load required Julia packages.
using Mimi, MimiFAIRv2, DataFrames, CSVFiles

include("nice2020_module.jl")


Env_1 = MimiNICE2020.create_nice2020()

nb_steps   = length(dim_keys(Env_1, :time))
nb_country = length(dim_keys(Env_1, :country))
nb_quantile = length(dim_keys(Env_1, :quantile))

run(Env_1)

explore(Env_1)

#Save results
output_directory_Env_1 = joinpath(@__DIR__, "..", "results", "Env_1")
mkpath(output_directory_Env_1)

MimiNICE2020.save_nice2020_results(Env_1, output_directory_Env_1, revenue_recycling=false)

update_param!(Env_1, :α, 0.0)

Env_2 = Env_1
update_param!(Env_2, :GreenNice, 0)

run(Env_2)

output_directory_Env_2 = joinpath(@__DIR__, "..", "results", "Env_2")
mkpath(output_directory_Env_2)

MimiNICE2020.save_nice2020_results(Env_2, output_directory_Env_2, revenue_recycling=false)

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

###TEST EDE consumption

env_ede = MimiNICE2020.create_nice2020()
nice_ede = MimiNICE2020.create_nice2020()

update_param!(env_ede, :α, 0.0)
update_param!(nice_ede, :GreenNice, 0)

run(env_ede)
run(nice_ede)

explore(env_ede)
explore(nice_ede)

#They work!

###Test welfare consumption eta = 1 works

test_welf = MimiNICE2020.create_nice2020()
nice = MimiNICE2020.create_nice2020()

update_param!(test_welf, :η, 1.0)
update_param!(test_welf, :α, 0.0)
update_param!(nice, :η, 1.0)
update_param!(nice, :GreenNice, 0.0)

run(test_welf)
run(nice)

explore(test_welf)
explore(nice)

#Welfare works!

###Test EDE when \eta == 1
include("nice2020_module.jl")

env_ede_0 = MimiNICE2020.create_nice2020()
env_ede_05 = MimiNICE2020.create_nice2020()

update_param!(env_ede_0, :η, 1)
update_param!(env_ede_0, :α, 0.0)
update_param!(env_ede_05, :η, 1)


run(env_ede_0)
explore(env_ede_0)

run(env_ede_05)
explore(env_ede_05)

update_param!(env_ede_05, :α, 0.9)
run(env_ede_05)
explore(env_ede_05)
