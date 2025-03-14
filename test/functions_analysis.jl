using DataFrames, RCall, CSV, Downloads
using VegaLite, VegaDatasets

function get_e0(m)

    # Create a new DataFrame for damage assessment
    Damage_table = DataFrame(CSV.File(joinpath(@__DIR__, "..", "data", "country_list.csv"),
                                        header=true))
    rename!(Damage_table, :countrycode => :iso3)
    sort!(Damage_table, :iso3)

    # Add the values of m[:environment, :Env0] as a column to the Damage_table DataFrame
    Damage_table[!, :e0] = m[:environment, :Env0]

    return(Damage_table)
end


function get_env_damages_year(m, year_end)

    Damage_table = get_e0(m)

    e_damages = m[:environment, :Env_country]

    year_analysis = year_end - 2019

    Damage_table[!, :e_end] = e_damages[year_analysis, :]

    Damage_table[!, :abs_loss] = Damage_table.e_end .- Damage_table.e0

    Damage_table[!, :percent_change] =
    (Damage_table.e_end .- Damage_table.e0) ./ Damage_table.e0 * 100

    return (Damage_table)

end

function get_env_damage_temp(m, temperature)

    Damage_table = get_e0(m)

    coef_damages = DataFrame(CSV.File(joinpath(@__DIR__,
                                        "..",
                                        "data",
                                        "coef_env_damage.csv"),
                                        header=true))

    rename!(coef_damages, :countrycode => :iso3)

    Damage_table= leftjoin(Damage_table, coef_damages, on=:iso3)

    Damage_table[!, :e_end] = Damage_table.e0 .* (1 .+ temperature .* Damage_table.coef)

    Damage_table[!, :abs_loss] = Damage_table.e_end .- Damage_table.e0

    Damage_table[!, :percent_change] =
    (Damage_table.e_end .- Damage_table.e0) ./ Damage_table.e0 * 100

    return(Damage_table)

end

function map_damage!(damages, title, save_name)

    world110m = dataset("world-110m")

    damages.id = [alpha3_to_numeric[iso3] for iso3 in damages.iso3]

    map = @vlplot(
        width = 640,
        height = 360,
        title = "$(title)",
        projection = {type = :mercator}
    ) +
    @vlplot(
        data = {
            values = world110m,
            format = {
                type = :topojson,
                feature = :countries
            }
        },
        transform = [{
            lookup = "id",
            from = {
                data = damages,
                key = :id,
                fields = ["percent_change"]
            }
        }],
        mark = :geoshape,
        encoding = {
            color = {
                field = "percent_change",
                type = "quantitative"
            }
        }
    )

    save("test/maps/$(save_name).svg", map)

end

function Env_damages_EDE_trajectories_alpha(m, array_damage_type, array_α)

    list_alpha = []

    for value in array_α
        update_param!(m, :α, value)

        list_models = []
        for param in array_damage_type
            update_param!(m, :environment, :dam_assessment, param)
            run(m)
            push!(list_models, m[:welfare, :cons_EDE_global])
        end
        push!(list_alpha, list_models)
    end
return(list_alpha)
end

function Env_damages_EDE_trajectories_eta(m, array_damage_type, array_η)

    list_eta = []

    for value in array_η
        update_param!(m, :η, value)

        list_models = []
        for param in array_damage_type
            update_param!(m, :environment, :dam_assessment, param)
            run(m)
            push!(list_models, m[:welfare, :cons_EDE_global])
        end
        push!(list_eta, list_models)
    end

return(list_eta)
end

function Env_damages_EDE_trajectories_theta(m, array_damage_type, array_θ)

    list_theta = []

    for value in array_θ
        update_param!(m, :θ, value)

        list_models = []
        for param in array_damage_type
            update_param!(m, :environment, :dam_assessment, param)
            run(m)
            push!(list_models, m[:welfare, :cons_EDE_global])
        end
        push!(list_theta, list_models)
    end

return(list_theta)
end



function plot_EDE_trajectories!(EDE_estimates,
                                damage_params,
                                var_params,
                                end_year,
                                param_name,
                                save_name)

    # Prepare the data for plotting
    data = DataFrame(year = Int[], EDE = Float64[], var = Float64[], damage_type = Int[],
                     damage_label = String[])

    damage_type_labels = Dict(1 => "GreenNice",
                                2 => "Unequal damages",
                                3 => "Unequal natural capital",
                                4 => "Same natural capital and damages"
                             )



    # Generate the data based on the input parameters
    for (j, alpha) in enumerate(var_params)
        for (i, param) in enumerate(damage_params)
            EDE = EDE_estimates[j][i]
            for (k, year) in enumerate(2020:end_year)
                push!(data, (year = year,
                             EDE = EDE[k],
                             var = alpha,
                             damage_type = param,
                             damage_label = get(damage_type_labels, param, "Unknown")))
            end
        end
    end

    p = @vlplot(
        mark = {type=:line, strokeWidth=0.5},
        data = data,
        encoding = {
            x = {field = :year, type = :quantitative},
            y = {field = :EDE, type = :quantitative},
            color = {field = :var, type = :nominal, title = param_name},
            strokeDash = {
            field = :damage_label,
            type = :nominal,
            tittle = "Damage type"
            }
        },
        title = "EDE Trajectories for Different Values of $param_name"
    )

    # Show the plot
    display(p)

    # Optionally, save the plot to a file (e.g., as SVG)
    save("test/figures/$(save_name).svg", p)

end

function get_EDE_country(m, iso3_list, country_list)

    EDE_country_list = []

    EDE_matrix = m[:welfare, :cons_EDE_country]

    for iso3 in iso3_list
        index = findfirst(row -> row == iso3, country_list[!,:countrycode])
        EDE_country = EDE_matrix[:, index]
        push!(EDE_country_list, EDE_country)
    end

    return(EDE_country_list)
end


function Env_damages_EDE_country(m, damage_options, iso3_list)

    country_list = DataFrame(CSV.File("data/country_list.csv"))

    damages_country_list = []

    for param in damage_options
        update_param!(m, :environment, :dam_assessment, param)
        run(m)
        EDE_country_list = get_EDE_country(m, iso3_list, country_list)
        push!(damages_country_list, EDE_country_list)

    end

    return(damages_country_list)

end




function plot_EDE_country!(EDE_estimates, iso3_list,  damage_params, end_year, save_name)

    data = DataFrame(year = Int[], EDE = Float64[], countrycode = String[],
        damage_type = Int[], damage_label = String[])

    damage_type_labels = Dict(1 => "GreenNice",
                                2 => "Unequal damages",
                                3 => "Unequal natural capital",
                                4 => "Same natural capital and damages"
                                )
    for (j, iso3) in enumerate(iso3_list)
        for (i, param) in enumerate(damage_params)
            EDE = EDE_estimates[i][j]
            for (k, year) in enumerate(2020:end_year)
                push!(data, (year = year,
                             EDE = EDE[k],
                             countrycode = iso3,
                             damage_type = param,
                             damage_label = get(damage_type_labels, param, "Unknown")))
            end
        end
    end

    p = @vlplot(
        mark = {type=:line, strokeWidth=0.5},
        data = data,
        encoding = {
            x = {field = :year, type = :quantitative},
            y = {field = :EDE, type = :quantitative},
            color = {field = :countrycode, type = :nominal, title = "Country"},
            strokeDash = {
            field = :damage_label,
            type = :nominal,
            tittle = "Damage type"
            }
        },
        title = "EDE Trajectories by country"
    )


    display(p)

    save("test/figures/$(save_name).svg", p)

end

function get_Y_pc(m, year_vector)

    GDP_table = DataFrame(CSV.File(joinpath(@__DIR__, "..", "data", "country_list.csv"),
                            header=true))
    rename!(GDP_table, :countrycode => :iso3)
    Y_pc = m[:neteconomy, :Y_pc]

    for year in year_vector
        GDP_table[!, Symbol(string(year))] = Y_pc[year-2019, :]
    end

    return GDP_table

end

function get_Env_pc(m, year_vector)
    Env_table = DataFrame(CSV.File(joinpath(@__DIR__, "..", "data", "country_list.csv"),
                                header=true))

    rename!(Env_table, :countrycode => :iso3)

    Env_pcq = m[:environment, :Env_percapita]
    Env_pc = Env_pcq[:, :, 1] .* m[:environment, :nb_quantile]

    for year in year_vector
        Env_table[!, Symbol(string(year))] = Env_pc[year-2019, :]
    end

    return Env_table

end

function plot_scatter_env_y(Env_table, GDP_table, year)

    data = DataFrame(
        iso3 = GDP_table.iso3,
        GDP = GDP_table[:, string(year)],
        Env = Env_table[:, string(year)]
    )

    # Plot GDP vs Env for 2020
    data|>
    @vlplot(
    layer =[
    {
        :text,
        x = {:GDP, axis={title="GDP per capita ($year)"}},
        y = {:Env, axis={title="Env per capita ($year)"}},
        text = {:iso3, title="Country"}
    },
    {
        transform = [{
                regression = "Env",
                on = "GDP"
                    }],

        mark = {:line, color = "firebrick"},
        x = :GDP,
        y = :Env
    }
    ]
    )
end

function make_env_gdp_plots(m, year_vector)

    GDP_table = get_Y_pc(m, year_vector)

    Env_table = get_Env_pc(m, year_vector)

    scatter_plots = []

    for year in year_vector
        scat_plot = plot_scatter_env_y(Env_table, GDP_table, year)
        push!(scatter_plots, scat_plot)
        save("test/figures/scatter_env_gdp_$(year).svg", scat_plot)
    end

    return scatter_plots
end

function map_env_pc(m, year_vector)

    world110m = dataset("world-110m")

    map_env_list = []

    for year in year_vector

        Env = get_Env_pc(m, year)
        Env.id = [alpha3_to_numeric[iso3] for iso3 in Env.iso3]

        map_env = @vlplot(
            width = 640,
            height = 360,
            title = "Non-market natural capital per capita in $(year)",
            projection = {type = :mercator}
        ) +
        @vlplot(
            data = {
                values = world110m,
                format = {
                    type = :topojson,
                    feature = :countries
                }
            },
            transform = [{
                lookup = "id",
                from = {
                    data = Env,
                    key = :id,
                    fields = [Symbol(string(year))]
                }
            }],
            mark = :geoshape,
            color = {field = Symbol(string(year)),
                     type = "quantitative",
                     title = "million USD"}
        )

        push!(map_env_list, map_env)
        save("test/maps/map_env_pc_$(year).svg", map_env)
    end

    return map_env_list

end

alpha3_to_numeric = Dict(
    "AFG" => 4,    # Afghanistan
    "ALB" => 8,    # Albania
    "DZA" => 12,   # Algeria
    "ASM" => 16,   # American Samoa
    "AND" => 20,   # Andorra
    "AGO" => 24,   # Angola
    "AIA" => 660,  # Anguilla
    "ATA" => 10,   # Antarctica
    "ATG" => 28,   # Antigua and Barbuda
    "ARG" => 32,   # Argentina
    "ARM" => 51,   # Armenia
    "ABW" => 533,  # Aruba
    "AUS" => 36,   # Australia
    "AUT" => 40,   # Austria
    "AZE" => 31,   # Azerbaijan
    "BHS" => 44,   # Bahamas (the)
    "BHR" => 48,   # Bahrain
    "BGD" => 50,   # Bangladesh
    "BRB" => 52,   # Barbados
    "BLR" => 112,  # Belarus
    "BEL" => 56,   # Belgium
    "BLZ" => 84,   # Belize
    "BEN" => 204,  # Benin
    "BMU" => 60,   # Bermuda
    "BTN" => 64,   # Bhutan
    "BOL" => 68,   # Bolivia (Plurinational State of)
    "BES" => 535,  # Bonaire, Sint Eustatius and Saba
    "BIH" => 70,   # Bosnia and Herzegovina
    "BWA" => 72,   # Botswana
    "BVT" => 74,   # Bouvet Island
    "BRA" => 76,   # Brazil
    "IOT" => 86,   # British Indian Ocean Territory (the)
    "BRN" => 96,   # Brunei Darussalam
    "BGR" => 100,  # Bulgaria
    "BFA" => 854,  # Burkina Faso
    "BDI" => 108,  # Burundi
    "CPV" => 132,  # Cabo Verde
    "KHM" => 116,  # Cambodia
    "CMR" => 120,  # Cameroon
    "CAN" => 124,  # Canada
    "CYM" => 136,  # Cayman Islands (the)
    "CAF" => 140,  # Central African Republic (the)
    "TCD" => 148,  # Chad
    "CHL" => 152,  # Chile
    "CHN" => 156,  # China
    "CXR" => 162,  # Christmas Island
    "CCK" => 166,  # Cocos (Keeling) Islands (the)
    "COL" => 170,  # Colombia
    "COM" => 174,  # Comoros (the)
    "COD" => 180,  # Congo (the Democratic Republic of the)
    "COG" => 178,  # Congo (the)
    "COK" => 184,  # Cook Islands (the)
    "CRI" => 188,  # Costa Rica
    "HRV" => 191,  # Croatia
    "CUB" => 192,  # Cuba
    "CUW" => 531,  # Curaçao
    "CYP" => 196,  # Cyprus
    "CZE" => 203,  # Czechia
    "CIV" => 384,  # Côte d'Ivoire
    "DNK" => 208,  # Denmark
    "DJI" => 262,  # Djibouti
    "DMA" => 212,  # Dominica
    "DOM" => 214,  # Dominican Republic (the)
    "ECU" => 218,  # Ecuador
    "EGY" => 818,  # Egypt
    "SLV" => 222,  # El Salvador
    "GNQ" => 226,  # Equatorial Guinea
    "ERI" => 232,  # Eritrea
    "EST" => 233,  # Estonia
    "SWZ" => 748,  # Eswatini
    "ETH" => 231,  # Ethiopia
    "FLK" => 238,  # Falkland Islands (the) [Malvinas]
    "FRO" => 234,  # Faroe Islands (the)
    "FJI" => 242,  # Fiji
    "FIN" => 246,  # Finland
    "FRA" => 250,  # France
    "GUF" => 254,  # French Guiana
    "PYF" => 258,  # French Polynesia
    "ATF" => 260,  # French Southern Territories (the)
    "GAB" => 266,  # Gabon
    "GMB" => 270,  # Gambia (the)
    "GEO" => 268,  # Georgia
    "DEU" => 276,  # Germany
    "GHA" => 288,  # Ghana
    "GIB" => 292,  # Gibraltar
    "GRC" => 300,  # Greece
    "GRL" => 304,  # Greenland
    "GRD" => 308,  # Grenada
    "GLP" => 312,  # Guadeloupe
    "GUM" => 316,  # Guam
    "GTM" => 320,  # Guatemala
    "GGY" => 831,  # Guernsey
    "GIN" => 324,  # Guinea
    "GNB" => 624,  # Guinea-Bissau
    "GUY" => 328,  # Guyana
    "HTI" => 332,  # Haiti
    "HMD" => 334,  # Heard Island and McDonald Islands
    "VAT" => 336,  # Holy See (the)
    "HND" => 340,  # Honduras
    "HKG" => 344,  # Hong Kong
    "HUN" => 348,  # Hungary
    "ISL" => 352,  # Iceland
    "IND" => 356,  # India
    "IDN" => 360,  # Indonesia
    "IRN" => 364,  # Iran (Islamic Republic of)
    "IRQ" => 368,  # Iraq
    "IRL" => 372,  # Ireland
    "IMN" => 833,  # Isle of Man
    "ISR" => 376,  # Israel
    "ITA" => 380,  # Italy
    "JAM" => 388,  # Jamaica
    "JPN" => 392,  # Japan
    "JEY" => 832,  # Jersey
    "JOR" => 400,  # Jordan
    "KAZ" => 398,  # Kazakhstan
    "KEN" => 404,  # Kenya
    "KIR" => 296,  # Kiribati
    "PRK" => 408,  # Korea (the Democratic People's Republic of)
    "KOR" => 410,  # Korea (the Republic of)
    "KWT" => 414,  # Kuwait
    "KGZ" => 417,  # Kyrgyzstan
    "LAO" => 418,  # Lao People's Democratic Republic (the)
    "LVA" => 428,  # Latvia
    "LBN" => 422,  # Lebanon
    "LSO" => 426,  # Lesotho
    "LBR" => 430,  # Liberia
    "LBY" => 434,  # Libya
    "LIE" => 438,  # Liechtenstein
    "LTU" => 440,  # Lithuania
    "LUX" => 442,  # Luxembourg
    "MAC" => 446,  # Macao
    "MDG" => 450,  # Madagascar
    "MWI" => 454,  # Malawi
    "MYS" => 458,  # Malaysia
    "MDV" => 462,  # Maldives
    "MLI" => 466,  # Mali
    "MLT" => 470,  # Malta
    "MHL" => 584,  # Marshall Islands (the)
    "MTQ" => 474,  # Martinique
    "MRT" => 478,  # Mauritania
    "MUS" => 480,  # Mauritius
    "MYT" => 175,  # Mayotte
    "MEX" => 484,  # Mexico
    "FSM" => 583,  # Micronesia (Federated States of)
    "MDA" => 498,  # Moldova (the Republic of)
    "MCO" => 492,  # Monaco
    "MNG" => 496,  # Mongolia
    "MNE" => 499,  # Montenegro
    "MSR" => 500,  # Montserrat
    "MAR" => 504,  # Morocco
    "MOZ" => 508,  # Mozambique
    "MMR" => 104,  # Myanmar
    "NAM" => 516,  # Namibia
    "NRU" => 520,  # Nauru
    "NPL" => 524,  # Nepal
    "NLD" => 528,  # Netherlands (the)
    "NCL" => 540,  # New Caledonia
    "NZL" => 554,  # New Zealand
    "NIC" => 558,  # Nicaragua
    "NER" => 562,  # Niger (the)
    "NGA" => 566,  # Nigeria
    "NIU" => 570,  # Niue
    "NFK" => 574,  # Norfolk Island
    "MNP" => 580,  # Northern Mariana Islands (the)
    "NOR" => 578,  # Norway
    "OMN" => 512,  # Oman
    "PAK" => 586,  # Pakistan
    "PLW" => 585,  # Palau
    "PSE" => 275,  # Palestine, State of
    "PAN" => 591,  # Panama
    "PNG" => 598,  # Papua New Guinea
    "PRY" => 600,  # Paraguay
    "PER" => 604,  # Peru
    "PHL" => 608,  # Philippines (the)
    "PCN" => 612,  # Pitcairn
    "POL" => 616,  # Poland
    "PRT" => 620,  # Portugal
    "PRI" => 630,  # Puerto Rico
    "QAT" => 634,  # Qatar
    "MKD" => 807,  # Republic of North Macedonia
    "ROU" => 642,  # Romania
    "RUS" => 643,  # Russian Federation (the)
    "RWA" => 646,  # Rwanda
    "REU" => 638,  # Réunion
    "BLM" => 652,  # Saint Barthélemy
    "SHN" => 654,  # Saint Helena, Ascension and Tristan da Cunha
    "KNA" => 659,  # Saint Kitts and Nevis
    "LCA" => 662,  # Saint Lucia
    "MAF" => 663,  # Saint Martin (French part)
    "SPM" => 666,  # Saint Pierre and Miquelon
    "VCT" => 670,  # Saint Vincent and the Grenadines
    "WSM" => 882,  # Samoa
    "SMR" => 674,  # San Marino
    "STP" => 678,  # Sao Tome and Principe
    "SAU" => 682,  # Saudi Arabia
    "SEN" => 686,  # Senegal
    "SRB" => 688,  # Serbia
    "SYC" => 690,  # Seychelles
    "SLE" => 694,  # Sierra Leone
    "SGP" => 702,  # Singapore
    "SXM" => 534,  # Sint Maarten (Dutch part)
    "SVK" => 703,  # Slovakia
    "SVN" => 705,  # Slovenia
    "SLB" => 90,   # Solomon Islands
    "SOM" => 706,  # Somalia
    "ZAF" => 710,  # South Africa
    "SGS" => 239,  # South Georgia and the South Sandwich Islands
    "SSD" => 728,  # South Sudan
    "ESP" => 724,  # Spain
    "LKA" => 144,  # Sri Lanka
    "SDN" => 729,  # Sudan (the)
    "SUR" => 740,  # Suriname
    "SJM" => 744,  # Svalbard and Jan Mayen
    "SWE" => 752,  # Sweden
    "CHE" => 756,  # Switzerland
    "SYR" => 760,  # Syrian Arab Republic
    "TWN" => 158,  # Taiwan (Province of China)
    "TJK" => 762,  # Tajikistan
    "TZA" => 834,  # Tanzania, United Republic of
    "THA" => 764,  # Thailand
    "TLS" => 626,  # Timor-Leste
    "TGO" => 768,  # Togo
    "TKL" => 772,  # Tokelau
    "TON" => 776,  # Tonga
    "TTO" => 780,  # Trinidad and Tobago
    "TUN" => 788,  # Tunisia
    "TUR" => 792,  # Turkey
    "TKM" => 795,  # Turkmenistan
    "TCA" => 796,  # Turks and Caicos Islands (the)
    "TUV" => 798,  # Tuvalu
    "UGA" => 800,  # Uganda
    "UKR" => 804,  # Ukraine
    "ARE" => 784,  # United Arab Emirates (the)
    "GBR" => 826,  # United Kingdom of Great Britain and Northern Ireland (the)
    "UMI" => 581,  # United States Minor Outlying Islands (the)
    "USA" => 840,  # United States of America (the)
    "URY" => 858,  # Uruguay
    "UZB" => 860,  # Uzbekistan
    "VUT" => 548,  # Vanuatu
    "VEN" => 862,  # Venezuela (Bolivarian Republic of)
    "VNM" => 704,  # Viet Nam
    "VGB" => 92,   # Virgin Islands (British)
    "VIR" => 850,  # Virgin Islands (U.S.)
    "WLF" => 876,  # Wallis and Futuna
    "ESH" => 732,  # Western Sahara
    "YEM" => 887,  # Yemen
    "ZMB" => 894,  # Zambia
    "ZWE" => 716,  # Zimbabwe
    "ALA" => 248   # Åland Islands
)
