#########################################################
# Get changes in environment
#########################################################

# Activate the project and make sure all packages we need
# are installed.
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
#Pkg.resolve() # To resolve inconsistencies between Manifest.toml and Project.toml
Pkg.instantiate()

# Load required Julia packages.
using Mimi, MimiFAIRv2, DataFrames, CSVFiles, Plots

println("Load NICE2020 source code.")
# Load NICE2020 source code.
include("../src/GreenNICE.jl")

include("functions_analysis.jl")
m = GreenNICE.create()

## Set E and parameters
update_param!(m, :environment, :dam_assessment, 1)

run(m)

Damages_2030 = get_env_damages_year(m, 2200)

AAA = plot_env_damages!(Damages_2030,
                        "Percent change in non-market natural capital by 2200",
                        "Percentage_loss_env")

Damages_1c = get_env_damage_temp(m, 1)

BBB = plot_env_damages!(Damages_1c,
                        "Percentage changes in non-market natural capital with a 1C increase",
                        "Percentage_loss_1c")



alpha_params = [0.1, 0.2, 0.3]
damage_options = [4, 3, 1]

EDE = Env_damages_EDE_trajectories(m, damage_options, alpha_params)

plot_EDE_trajectories!(EDE, damage_options, alpha_params, 2200)
