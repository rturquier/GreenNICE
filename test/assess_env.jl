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

m = GreenNICE.create()

## Set E and parameters
update_param!(m, :environment, :dam_assessment, 1)

run(m)


using DataFrames, RCall, CSV, Downloads

## Function: Get damage loss by determined year.

# Create a new DataFrame for damage assessment
Damage_table = DataFrame(CSV.File(joinpath(@__DIR__, "..", "data", "country_list.csv"), header=true))
rename!(Damage_table, :countrycode => :iso3)
sort!(Damage_table, :iso3)

# Add the values of m[:environment, :Env0] as a column to the Damage_table DataFrame
Damage_table[!, :e0] = m[:environment, :Env0]
e_damages = m[:environment, :Env_country]

enter_year = 2300
year_analysis = enter_year - 2019

Damage_table[!, :e_end] = e_damages[year_analysis, :]

Damage_table[!, :abs_loss] = Damage_table.e_end .- Damage_table.e0
Damage_table[!, :percent_change] =
                        (Damage_table.e_end .- Damage_table.e0) ./ Damage_table.e0 * 100

## Function, plot to map based on ISO 3 (taken from: https://github.com/alfaromartino/coding/blob/main/assets/PAGES/01_heatmaps_world/codeDownload/allCode.jl)

R"""
library(ggplot2)
library(svglite) #to save graphs in svg format, otherwise not necessary
"""


# Assuming `damages` is a DataFrame with columns: :ISO3 and :Damage
damages = Damage_table

get_coordinates = Downloads.download("https://alfaromartino.github.io/data/countries_mapCoordinates.csv")
df_coordinates = DataFrame(CSV.File(get_coordinates)) |> x-> dropmissing(x, :iso3)

merged_df = leftjoin(df_coordinates, damages, on=:iso3)
merged_df = merged_df[.!(occursin.(r"Antarct", merged_df.short_name_country)),:]


isdir(joinpath(@__DIR__, "maps")) || mkdir(joinpath(@__DIR__, "maps"))
graphs_folder = joinpath(@__DIR__, "maps")


R"""

user_theme <- function(){
  theme(
    panel.background = element_blank(),
    panel.border     = element_blank(),
    panel.grid.major = element_blank(),
    panel.grid.minor = element_blank(),
    panel.grid       = element_blank(),

    axis.line    = element_blank(),
    axis.text.x  = element_blank(),
    axis.text.y  = element_blank(),
    axis.ticks   = element_blank(),
    axis.title.x = element_blank(),
    axis.title.y = element_blank()
      )
      }

#baseline code
map_damages <- ggplot() + geom_polygon(data = $(merged_df),
                                  aes(x=long, y = lat, group = group,
                                      fill=percent_change)) +
                        user_theme() +
                        coord_fixed(1.3) +
                        scale_fill_gradient(low = "red",
                                            high ="green",
                                            name = "Non-market Natural Capital Percent Change")



height <- 5

ggsave(filename = file.path($(graphs_folder),"Percent_loss_env.svg"),
                        plot = map_damages,
                        width = height * 3,
                        height = height)
"""

@rput merged_df     # we send our merged dataframe t
