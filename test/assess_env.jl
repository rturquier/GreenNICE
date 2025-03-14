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
using Mimi, MimiFAIRv2, DataFrames, CSVFiles

include("../src/GreenNICE.jl")
include("functions_analysis.jl")



m = GreenNICE.create()

#############
# Make plots
############

# Map damages

run(m)

Damages_2200 = get_env_damages_year(m, 2200)

map_damage!(Damages_2200,
                    "Percent change in non-market natural capital by 2200",
                    "Percentage_loss_env")

Damages_1c = get_env_damage_temp(m, 1)

map_damage!(Damages_1c,
                    "Percentage changes in non-market natural capital with a 1C increase",
                    "Percentage_loss_1c")

## Scatter Plot GDP and Env (both per capita)

year_vector = [2020, 2200]

scater_plots = make_env_gdp_plots(m, year_vector)

## Map Env percapita

maps_env_pc = map_env_pc(m, year_vector)

# Plot EDE

damage_options = [4, 3, 1]

m = GreenNICE.create()

alpha_params = [0.1, 0.2, 0.3]

EDE = Env_damages_EDE_trajectories_alpha(m, damage_options, alpha_params)

plot_EDE_trajectories!(EDE, damage_options,
                        alpha_params,
                        2200,
                        "α",
                        "EDE_Trajectories_alpha")

#Test η and damage options
m = GreenNICE.create()

eta_params = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]

EDE_eta = Env_damages_EDE_trajectories_eta(m, damage_options, eta_params)

plot_EDE_trajectories!(EDE_eta,
                        damage_options,
                        eta_params,
                        2200,
                        "η",
                        "EDE_Trajectories_eta")

#Test θ and damage options

m = GreenNICE.create()

theta_params = [-4, -0.5, 0.5, 1.0]

EDE_theta = Env_damages_EDE_trajectories_theta(m, damage_options, theta_params)

plot_EDE_trajectories!(EDE_theta,
                        damage_options,
                        theta_params,
                        2200,
                        "θ",
                        "EDE_Trajectories_theta")



# Plot for selected countries

m = GreenNICE.create()
update_param!(m, :α, 0.3)

iso3_list = ["IND", "USA", "CHN", "RUS", "BRA", "ZAF"]

damage_options = [4, 3, 1]

country_damages = Env_damages_EDE_country(m, damage_options, iso3_list)

plot_EDE_country!(country_damages, iso3_list, damage_options, 2200, "EDE_Country")
