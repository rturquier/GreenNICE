# Calibration for environmental data.
using CSVFiles
using DataFrames
using HTTP
using JSON
using XLSX
using Statistics

nice_inputs = JSON.parsefile("data/nice_inputs.json") # This file contains the economic and emissions calibration and the list of used country codes
# the json file reads in a several nested dictionaries, where in each case the "last" dictionary contains the keys, "units", "dimensions", "notes", and "x". The "x" key always contains the data to be read into a DataFrame.

countries = nice_inputs["country_set_ssp_183"]["x"]["countrycode"] # country set (ISO3 codes in alphabetic order)countries = string.(countries)

# REMOVE SOMALIA, VENEZUELA, NEW CALEDONIA, and TRINIDAD AND TOBAGO
filter!(x -> !(x in ["SOM", "VEN", "NCL", "TTO"]), countries)

sort!(countries) # Sort country names to be in alphabetical order.

# Save the filtered and sorted country codes as a CSV file
country_list_file_path = "data/country_list.csv"
CSVFiles.save(country_list_file_path, DataFrame(; countrycode=countries))

# 1. Set initial values for E--a non-market environmental good.

# Select natural capital for 3 environmental services (pg 145 CWON)
#es 1: Recreation. es 2: non-wood forest products. es 3: Water regulation

#1.1 Download excel file from the World Bank

file_url =
    "https://datacatalogfiles.worldbank.org/ddh-published/0042066/DR0084043/" *
    "CWON%202024%20Country%20Tool%2010082024.xlsx?versionId=2024-10-23T12:54:29.3317026Z"

file_path = "data/CWON_2024.xlsx"

HTTP.download(file_url, file_path)

#1.2 Create a data frame file with the data from the "country" sheet

country_e0 = XLSX.readtable(file_path, "country"; first_row=2) |> DataFrame

# Filter data for the year 2020 and select columns of interest

country_e0 = filter(row -> row[:year] == 2020, country_e0)

country_e0 = select(
    country_e0,
    [:countrycode, :torn_real_forest_es1, :torn_real_forest_es2, :torn_real_forest_es3],
)

country_e0[!, :e0] =
    country_e0.torn_real_forest_es1 .+ country_e0.torn_real_forest_es2 .+
    country_e0.torn_real_forest_es3

country_e0 = select(country_e0, [:countrycode, :e0])

#1.3 Create a CSV file with initial natural capital values

e0 = CSVFiles.load(country_list_file_path) |> DataFrame

e0 = leftjoin(e0, country_e0; on=:countrycode, makeunique=true)

# Replace missing values with the average so there is an starting value for all countries

avg_e0 = mean(skipmissing(e0.e0))
e0.e0 = coalesce.(e0.e0, avg_e0)

#Get the flow of the nat cap stock. r = 4%. t = 100 years

e0.e0 = e0.e0 .* ((1 - 0.04) / (1 - 0.04^100))

# Scale down the values by dividing by 1,000,000 to get the units in million USD

e0.e0 = e0.e0 ./ 1000000

e0_file_path = "data/e0.csv"
CSVFiles.save(e0_file_path, e0)

# 2. Get environmental damage function aprameters from Bastien-Olver et al. 2024

damage_coef_url = "https://raw.githubusercontent.com/BerBastien/NatCap_DGVMs/main/Data/" *
                    "Damage_coef_Submission3v2_06052023.csv"
damage_coef_file_path = "data/raw_env_damage.csv"

HTTP.download(damage_coef_url, damage_coef_file_path)

# Load the environmental damage coefficients data
damage_coef = CSVFiles.load(damage_coef_file_path) |> DataFrame

# Filter the data to only include rows where the first column has the value "temp7"
damage_coef_filtered = filter(row -> row[:formula] == "lin" &&
                              row[:capital] == "nN" &&
                              row[:dgvm] == "all", damage_coef)

damage_coef_filtered = select(damage_coef_filtered,
                            [:iso3, :coef, :se, :pval])

rename!(damage_coef_filtered, :iso3 => :countrycode)

coef_env_damage = CSVFiles.load(country_list_file_path) |> DataFrame

coef_env_damage = leftjoin(coef_env_damage, damage_coef_filtered, on=:countrycode,
                            makeunique=true)

# Replace missing values with the average so there is an starting value for all countries

avg_coef = mean(skipmissing(coef_env_damage.coef))

for i in 1:nrow(coef_env_damage)
    if ismissing(coef_env_damage[i, :coef])
        coef_env_damage[i, :coef] = avg_coef
    end
end

# Save the filtered data to a new CSV file
filtered_damage_coef_file_path = "data/coef_env_damage.csv"
CSVFiles.save(filtered_damage_coef_file_path, damage_coef_filtered)
