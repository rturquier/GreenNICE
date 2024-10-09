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


println("Running Green Nice version 0")

V0 = MimiNICE2020.create_nice2020()

nb_steps   = length(dim_keys(V0, :time))
nb_country = length(dim_keys(V0, :country))
nb_quantile = length(dim_keys(V0, :quantile))

run(V0)


## Update variables to check that results are the same as in the original model

#Test 1: Check that changes in alpha change the output.
# Test 1.1 Set \alpha = 0

V1_1 = MimiNICE2020.create_nice2020()

update_param!(V1_1, :α, 0.0)
run(V1_1)

#Save results
output_directory_1_1 = joinpath(@__DIR__, "..", "results", "alpha=0")
mkpath(output_directory_1_1)

MimiNICE2020.save_nice2020_results(V1_1, output_directory_1_1, revenue_recycling=false)

#Test 1.2 Set \alpha = 0.5 and see if results change

V1_2 = MimiNICE2020.create_nice2020()
update_param!(V1_2, :α, 0.5)
run(V1_2)

output_directory_1_2 = joinpath(@__DIR__, "..", "results", "alpha=0.5")
mkpath(output_directory_1_2)

MimiNICE2020.save_nice2020_results(V1_2, output_directory_1_2, revenue_recycling=false)

#Test 1.3 Set \alpha = 1 and see if results change

V1_3 = MimiNICE2020.create_nice2020()
update_param!(V1_3, :α, 1)  # Set alpha to 1    
run(V1_3)

output_directory_1_3 = joinpath(@__DIR__, "..", "results", "alpha=1")
mkpath(output_directory_1_3)

MimiNICE2020.save_nice2020_results(V1_3, output_directory_1_3, revenue_recycling=false)

#Test 2: Check that changes in θ change the output.

#Test 2.1 Set θ = -5 and see if results change
V2_1 = MimiNICE2020.create_nice2020()
update_param!(V2_1, :θ, -5)
run(V2_1)

output_directory_2_1 = joinpath(@__DIR__, "..", "results", "theta=-5")
mkpath(output_directory_2_1)

MimiNICE2020.save_nice2020_results(V2_1, output_directory_2_1, revenue_recycling=false)

#Test 2.2 Set θ = 0 and see if results change
V2_2 = MimiNICE2020.create_nice2020()
update_param!(V2_2, :θ, 0)
run(V2_2)

output_directory_2_2 = joinpath(@__DIR__, "..", "results", "theta=0")
mkpath(output_directory_2_2)

MimiNICE2020.save_nice2020_results(V2_2, output_directory_2_2, revenue_recycling=false)

#Test 3: iF \theta = 1 and \eta = 0, welfare should be half when \alpha = 0.5 and Env = 0.0

V3_1 = MimiNICE2020.create_nice2020()
update_param!(V3_1, :θ, 1)
update_param!(V3_1, :η, 0)
update_param!(V3_1, :α, 0.5)
run(V3_1)

output_directory_3_1 = joinpath(@__DIR__, "..", "results", "theta=1_eta=0_alpha=0.5")
mkpath(output_directory_3_1)

MimiNICE2020.save_nice2020_results(V3_1, output_directory_3_1, revenue_recycling=false)

V3_2 = MimiNICE2020.create_nice2020()
update_param!(V3_2, :θ, 1)
update_param!(V3_2, :η, 0)
update_param!(V3_2, :α, 0.0)
run(V3_2)

output_directory_3_2 = joinpath(@__DIR__, "..", "results", "theta=1_eta=0_alpha=0")
mkpath(output_directory_3_2)

MimiNICE2020.save_nice2020_results(V3_2, output_directory_3_2, revenue_recycling=false)

#Test 4: Match results with original NICE 
### THE 
### FIRE 
### TEST 

V4 = MimiNICE2020.create_nice2020()
update_param!(V4, :α, 0.0)
#θ should cancel output

run(V4)

output_directory_4 = joinpath(@__DIR__, "..", "results", "fire_test")   
mkpath(output_directory_4)

MimiNICE2020.save_nice2020_results(V4, output_directory_4, revenue_recycling=false)

#RUN ORIGINAL NICE