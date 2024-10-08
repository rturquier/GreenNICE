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

explore(V0)