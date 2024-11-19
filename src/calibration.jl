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

# Keep only the columns 'countrycode' and 'torn_real_renew'
#We use renewable natural capital
country_e0 = select(country_e0, [:countrycode, :torn_real_renew])

#1.3 Create a CSV file with initial natural capital values

# Open file country list, merge, scale values and save
country_list_file_path = "data/country_list.csv"
e0 = CSVFiles.load(country_list_file_path) |> DataFrame

# Perform a left join and update e0_data
e0 = leftjoin(e0, country_e0; on=:countrycode, makeunique=true)

# Rename torn_real_renew to e0
rename!(e0, :torn_real_renew => :e0)

# Replace missing values with the average
avg_e0 = mean(skipmissing(e0.e0))

replace!(e0.e0, missing => avg_e0)

# Scale the values by dividing by 1,000,000
e0.e0 = e0.e0 ./ 1000000

# Save the updated data back to the CSV file
e0_file_path = "data/e0.csv"
CSVFiles.save(e0_file_path, e0)
