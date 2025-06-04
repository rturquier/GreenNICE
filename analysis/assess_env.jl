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

run(m)

#############
# Make plots and maps
############

# Map damages

Damages_2100 = get_env_damages_year(m, 2100)

map_damage!(Damages_2100,
                    "",
                    "map_percentage_loss_env")

Damages_1c = get_env_damage_temp(m, 1)

map_damage!(Damages_1c,
                    "Percentage changes in non-market natural capital with a 1C increase",
                    "Percentage_loss_1c")

## Scatter Plot GDP and Env (both per capita)
year_vector = [2020, 2100]

## Both plots no trend line.
plot_env_gdp_faceted!(m, year_vector)

plot_env_gdp_evo!(m, year_vector)

### Separate plots with trend line
scater_plots = make_env_gdp_plots(m, year_vector)

## Map Env percapita
maps_env_pc = map_env_pc(m, year_vector)

### plot map faceted
map_env_pc_faceted!(m, year_vector)
plot_scatter_gdp_coeff!(m)

## Damages distribution

# Load environmental damage coefficients
coef_env_damage = CSV.read("data/coef_env_damage.csv", DataFrame)

plot_density!()

plot_scatter_e_coeff!(m)

# Analysis parameters

alpha_params = 0.0:0.1:0.3
theta_params = 0.1:0.1:1.0
eta_params = 0.6:0.2:2.0
damage_options = [4, 3, 1]
emissions_scenarios = ["ssp119", "ssp126", "ssp245", "ssp370", "ssp585"]
emissions_subgroup = ["ssp126", "ssp245", "ssp585"]
list_regions = ["Eastern Africa", "South America", "Southern Asia",
                "Australia and New Zealand"]
list_countries = ["IND", "USA", "CHN", "RUS", "BRA", "ZAF"]



# Atkinson Index

m = GreenNICE.create()
run(m)

m_0 = GreenNICE.create()
update_param!(m_0, :α, 0.0)
run(m_0)

Regions_Atkinson = get_Atkinson_dataframe(m, 2100, "region")

long_df = stack(Regions_Atkinson, Not(:year), variable_name = :Region, value_name = :Atkinson_index)

p = @vlplot(
    mark = {type=:line, strokeWidth=0.5},
    data = long_df,
    encoding = {
        x = {field = :year, type = :quantitative},
        y = {field = :Atkinson_index, type = :quantitative, title = "Inequality (Iₜ)"},
        color = {field = :Region, type = :nominal, title = "World_Region"}
    },
    title = nothing
)
save("outputs/figures/Atkinson_Regions.svg", p)

m = GreenNICE.create()
run(m)

table_Atkinson_regions!(m, m_0)

diff_NICE_GreenNICE = plot_Atkinson_global()

m_at = GreenNICE.create()
run(m_at)

diff_damage = plot_Atkinson_envdamage(m_at, damage_options)

## Trajectories under different parameters

m_at = GreenNICE.create()
run(m_at)

plot_Atkinson_param!(m_at, alpha_params, theta_params, eta_params, 2100)

plot_Atkinson_scenario_param!(alpha_params, theta_params, eta_params, emissions_subgroup)

plot_c_EDE!()

diff_scenarios = plot_Atkinson_emissionscenario(emissions_scenarios)

m_at = GreenNICE.create()
run(m_at)

m_0 = GreenNICE.create()
update_param!(m_0, :α, 0.0)
run(m_0)

diff_regions = plot_Atkinson_regions(m_at, m_0, list_regions, 2100)

m = GreenNICE.create()
run(m)

diff_regions_damage = plot_Atkinson_region_envdamage(m, damage_options, list_regions)

m = GreenNICE.create()
run(m)

plot_Atkinson_country_envdamage!(m, damage_options, list_countries, 2100)


aux_theta = -1.0:0.1:1.0

Table = plot_rel_price(alpha_params, aux_theta)

# Plot EDE

## Test α and damage options

m = GreenNICE.create()
run(m)

EDE_alpha = EDE_trajectories(m, damage_options, alpha_params, "α")

plot_EDE_trajectories!(EDE_alpha, damage_options,
                        alpha_params,
                        2200,
                        "α",
                        "EDE_Trajectories_alpha")

## Test θ and damage options
reset!(m) #set initial parameters for α, θ and η.

EDE_theta = EDE_trajectories(m, damage_options, theta_params, "θ")

plot_EDE_trajectories!(EDE_theta,
                        damage_options,
                        theta_params,
                        2200,
                        "θ",
                        "EDE_Trajectories_theta")

## Test η and damage options
reset!(m)

EDE_eta = EDE_trajectories(m, damage_options, eta_params, "η")

plot_EDE_trajectories!(EDE_eta,
                        damage_options,
                        eta_params,
                        2200,
                        "η",
                        "EDE_Trajectories_eta")

## Plot EDE for BRICS countries
reset!(m)
update_param!(m, :α, 0.3)

country_damages = Env_damages_EDE_country(m, damage_options, list_countries)

plot_EDE_country!(country_damages, list_countries, damage_options, 2200, "EDE_Country")

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

# Plot EDE for different emissions scenarios

## Compare EDE GreenNICE and NICE
plot_EDE_GreenNICE_NICE!(emissions_scenarios, 2200, "EDE_GreenNICE_NICE")

## Get numbers to describe in paper
EDE_scenarios_values = EDE_GreenNICE_NICE(emissions_scenarios)

### EDE GreenNICE in 2200 in BAU (ssp245), α = 0.1, θ = 0.5 and η = 1.5
EDE_scenarios_values[2][1][end]
### EDE NICE in 2200 BAU
EDE_scenarios_values[2][2][end]
### pct change
( EDE_scenarios_values[2][1][end] -EDE_scenarios_values[2][2][end]) / EDE_scenarios_values[2][2][end] * 100

### Max EDE in scenario ssp119
EDE_scenarios_values[1][1][end]

### Min EDE in scenario ssp370
EDE_scenarios_values[4][1][end]
### compare with NICE
(EDE_scenarios_values[4][2][end] - EDE_scenarios_values[4][1][end]) / EDE_scenarios_values[4][1][end] * 100
