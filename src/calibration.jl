# Calibration for environmental data.
using CSVFiles
using DataFrames
using HTTP
using JSON
using XLSX
using Statistics

# 1. Set initial values for E

#1.1 Download excel file from the World Bank

file_url =
    "https://datacatalogfiles.worldbank.org/ddh-published/0042066/DR0084043/" *
    "CWON%202024%20Country%20Tool%2010082024.xlsx?versionId=2024-10-23T12:54:29.3317026Z"

file_path = "data/CWON_2024.xlsx"

HTTP.download(file_url, file_path)

#1.2 Create a CSV file with the data from the "country" sheet

country_e0 = XLSX.readtable(file_path, "country"; first_row=2) |> DataFrame

# Filter data for the year 2020

country_e0 = filter(row -> row[:year] == 2020, country_e0)

# Select Tornwvist natural capital for 3 environmental services (pg 145 CWON)
#es 1: Recreation. es 2: Other wood products. es 3: Water regulation

country_e0 = select(
    country_e0,
    [:countrycode, :torn_real_forest_es1, :torn_real_forest_es2, :torn_real_forest_es3],
)

country_e0[!, :e0] =
    country_e0.torn_real_forest_es1 .+ country_e0.torn_real_forest_es2 .+
    country_e0.torn_real_forest_es3

country_e0 = select(country_e0, [:countrycode, :e0])

#1.3 Create a CSV file with initial natural capital values

country_list_file_path = "data/country_list.csv"
e0 = CSVFiles.load(country_list_file_path) |> DataFrame

e0 = leftjoin(e0, country_e0; on=:countrycode, makeunique=true)

# Replace missing values with the average of the column so there is an starting value for all countries

avg_e0 = mean(skipmissing(e0.e0))
e0.e0 = coalesce.(e0.e0, avg_e0)

# Scale down the values by dividing by 1,000,000 to get the units in million USD

e0.e0 = e0.e0 ./ 1000000

e0_file_path = "data/e0.csv"
CSVFiles.save(e0_file_path, e0)
