#########################################################
# This file produces example runs for the NICE2020 model
#########################################################

# Activate the project and make sure all packages we need
# are installed.
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
#Pkg.resolve() # To resolve inconsistencies between Manifest.toml and Project.toml
Pkg.instantiate()

# Load required Julia packages.
using Mimi, MimiFAIRv2, DataFrames, CSVFiles

println("Load NICE2020 source code.")
# Load NICE2020 source code.
include("../src/GreenNICE.jl")

include("functions_analysis.jl")
m = GreenNICE.create()

## Set E and parameters
update_param!(m, :environment, :dam_assessment, 1)

run(m)


using DataFrames, RCall, CSV, Downloads

Damages = get_env_damages_year(m, 2300)

AAA = plot_env_damages!(Damages, "Percentage_loss_env")

BBB = get_env_damage_temp(m, 1)
