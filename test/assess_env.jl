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

# Map damages

run(m)

#############
# Make plots
############

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

### Both plots no trend line.
plot_env_gdp_faceted!(m, year_vector)

### Separate plots with trend line
scater_plots = make_env_gdp_plots(m, year_vector)

## Map Env percapita
maps_env_pc = map_env_pc(m, year_vector)

### plot map faceted
map_env_pc_faceted!(m, year_vector)

# Plot EDE

damage_options = [4, 3, 1]

m = GreenNICE.create()

alpha_params = [0.1, 0.2, 0.3]

EDE_alpha = EDE_trajectories(m, damage_options, alpha_params, "α")


plot_EDE_trajectories!(EDE_alpha, damage_options,
                        alpha_params,
                        2200,
                        "α",
                        "EDE_Trajectories_alpha")

## Test η and damage options
reset!(m)

eta_params = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]

EDE_eta = EDE_trajectories(m, damage_options, eta_params, "η")

plot_EDE_trajectories!(EDE_eta,
                        damage_options,
                        eta_params,
                        2200,
                        "η",
                        "EDE_Trajectories_eta")

## Test θ and damage options

reset!(m)

theta_params = [-0.5, 0.5, 1.0]

EDE_theta = EDE_trajectories(m, damage_options, theta_params, "θ")

plot_EDE_trajectories!(EDE_theta,
                        damage_options,
                        theta_params,
                        2200,
                        "θ",
                        "EDE_Trajectories_theta")

## Plot for selected countries
reset!(m)
update_param!(m, :α, 0.3)

iso3_list = ["IND", "USA", "CHN", "RUS", "BRA", "ZAF"]

damage_options = [4, 3, 1]

country_damages = Env_damages_EDE_country(m, damage_options, iso3_list)

plot_EDE_country!(country_damages, iso3_list, damage_options, 2200, "EDE_Country")


# Numbers to report in paper
## pct change of EDE conditional on climate damages
pct_change_01 = (EDE_alpha[1][1][end] - EDE_alpha[1][3][end]) / EDE_alpha[1][3][end] * 100
pct_change_02 = (EDE_alpha[2][1][end] - EDE_alpha[2][3][end]) / EDE_alpha[2][3][end] * 100
pct_change_03 = (EDE_alpha[3][1][end] - EDE_alpha[3][3][end]) / EDE_alpha[3][3][end] * 100

## changes in EDE conditional on parameters
### alpha
pct_change_alpha_1 = (EDE_alpha[1][3][end] - EDE_alpha[2][3][end]) / EDE_alpha[1][3][end] * 100
pct_change_alpha_2 = (EDE_alpha[1][3][end] - EDE_alpha[3][3][end]) / EDE_alpha[1][3][end] * 100

### theta
pct_change_theta = (EDE_theta[3][3][end] - EDE_theta[2][3][end]) / EDE_theta[2][3][end] * 100

### eta
pct_change_eta_up = (EDE_eta[1][3][end] - EDE_eta[4][3][end]) / EDE_eta[4][3][end] * 100
pct_change_eta_down = (EDE_eta[7][3][end] - EDE_eta[4][3][end]) / EDE_eta[4][3][end] * 100
