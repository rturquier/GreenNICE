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

# Different E, equal damages
update_param!(m, :environment, :dam_assessment, 1)

run(m)


using DataFrames, RCall, CSV, Downloads

# Create a new DataFrame for damage assessment
Damage_table = DataFrame(CSV.File(joinpath(@__DIR__, "..", "data", "country_list.csv"), header=true))
rename!(Damage_table, :countrycode => :iso3)
sort!(Damage_table, :iso3)

# Add the values of m[:environment, :Env0] as a column to the Damage_table DataFrame
Damage_table.e0 = m[:environment, :Env0]

e_damages = m[:environment, :Env_country]
Damage_table.e_last = e_damages[end, :]
Damage_table

Damage_table.percent_loss =
                        (Damage_table.e_last .- Damage_table.e0) ./ Damage_table.e0 * 100

Damage_table.abs_loss = (Damage_table.e_last .- Damage_table.e0)

R"""
library(ggplot2)
library(svglite) #to save graphs in svg format, otherwise not necessary
"""


# Assuming `damages` is a DataFrame with columns: :ISO3 and :Damage
damages = DataFrame(iso3 = ["USA", "CAN", "MEX"], Damage = [10.0, 5.0, 3.0])

get_coordinates = Downloads.download("https://alfaromartino.github.io/data/countries_mapCoordinates.csv")
df_coordinates = DataFrame(CSV.File(get_coordinates)) |> x-> dropmissing(x, :iso3)

merged_df = leftjoin(df_coordinates, damages, on=:iso3)

isdir(joinpath(@__DIR__, "maps")) || mkdir(joinpath(@__DIR__, "maps"))
graphs_folder = joinpath(@__DIR__, "maps")

R"""
#baseline code
our_gg <- ggplot() + geom_polygon(data = $(merged_df),
                                  aes(x=long, y = lat, group = group,
                                      fill=Damage))

#saving the graph
ggsave(filename = file.path($(graphs_folder),"file_graph0.svg"), plot = our_gg)
"""

@rput merged_df     # we send our merged dataframe to R

# we create the graph using RCall
R"""
#baseline code
our_gg <- ggplot() + geom_polygon(data = merged_df,
                                  aes(x=long, y = lat, group = group,
                                      fill=Damage))

#saving the graph
ggsave(filename = file.path($(graphs_folder),"file_graph0.jpg"), plot = our_gg)
"""
