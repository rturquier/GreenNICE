using DataFrames, RCall, CSV, Downloads
using VegaLite, VegaDatasets
using PrettyTables
using StatsPlots

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
        projection = {type = :equirectangular}
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
            type = "quantitative",
            title = "e percentage change",
            scale = {
                scheme = "redblue",
                domainMid = 0
            }
            }
        }
    )

    save("outputs/maps/$(save_name).svg", map)

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

function EDE_trajectories(m, array_damage_type, array_values, parameter)

    list = []

    for value in array_values
        update_param!(m, Symbol(parameter), value)

        list_models = []
        for param in array_damage_type
            update_param!(m, :environment, :dam_assessment, param)
            run(m)
            push!(list_models, m[:welfare, :cons_EDE_global])
        end
        push!(list, list_models)
    end

return(list)
end

function reset!(m)

    update_param!(m, :α, 0.1)
    update_param!(m, :η, 1.5)
    update_param!(m, :θ, 0.5)
    update_param!(m, :environment, :dam_assessment, 1)

    return(m)
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
            y = {field = :EDE, type = :quantitative, scale = {domain=[0, 65]}},
            color = {field = :var, type = :nominal, title = param_name},
            strokeDash = {
            field = :damage_label,
            type = :nominal,
            legend = nothing
            #tittle = "Damage type"
            }
        },
        title = nothing
    )

    # Show the plot
    display(p)

    # Optionally, save the plot to a file (e.g., as SVG)
    save("outputs/figures/$(save_name).svg", p)
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

    save("outputs/figures/$(save_name).svg", p)

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
        :point,
        x = {:GDP,
            axis={title="GDP per capita ($year)"}
            },
        y = {:Env,
            axis={title="Env per capita ($year)"}
            }#,
        #text = {:iso3, title="Country"}
    },
    {
        transform = [{
                regression = "Env",
                on = "GDP"
                    }],

        mark = {:line, color = "firebrick"},
        x = {:GDP},
        y = {:Env}
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
        save("outputs/figures/scatter_env_gdp_$(year).svg", scat_plot)
    end

    return scatter_plots
end

function plot_env_gdp_faceted!(m, year_vector)

    GDP_table = get_Y_pc(m, year_vector)

    Env_table = get_Env_pc(m, year_vector)

    merged_table = DataFrame(iso3 = String[], GDP = Float64[], Env = Float64[], year = Int[])

    for year in year_vector
        gdp_data = GDP_table[:, [:iso3, Symbol(year)]]
        env_data = Env_table[:, [:iso3, Symbol(year)]]
        rename!(gdp_data, Symbol(year) => :GDP)
        rename!(env_data, Symbol(year) => :Env)
        gdp_data.year .= year
        env_data.year .= year
        combined_data = innerjoin(gdp_data, env_data, on = [:iso3, :year])
        append!(merged_table, combined_data)
    end

   plot =  merged_table|>
    @vlplot(
        :point,
        row = :year,
        x = {:GDP, axis={title="GDP per capita"}},
        y = {:Env, axis={title="E per capita"}}#,
        #text = {:iso3, title="Country"}
    )

    save("outputs/figures/env_gdp_faceted.svg", plot)

end

function plot_env_gdp_evo!(m, year_vector)

    GDP_table = get_Y_pc(m, year_vector)

    Env_table = get_Env_pc(m, year_vector)

    merged_table = DataFrame(iso3 = String[], GDP = Float64[], Env = Float64[], year = Int[])

    for year in year_vector
        gdp_data = GDP_table[:, [:iso3, Symbol(year)]]
        env_data = Env_table[:, [:iso3, Symbol(year)]]
        rename!(gdp_data, Symbol(year) => :GDP)
        rename!(env_data, Symbol(year) => :Env)
        gdp_data.year .= year
        env_data.year .= year
        combined_data = innerjoin(gdp_data, env_data, on = [:iso3, :year])
        append!(merged_table, combined_data)
    end

    plot = @vlplot(
        :point,
        data = merged_table,
        encoding = {
            x = {:GDP, axis={title="GDP per capita (k USD)"}},
            y = {:Env, axis={title="e per capita (k USD)"}},
            color = {
            :year,
            type = :ordinal,
            title = "Year",
            scale = {scheme = "viridis"}  # Use a color scheme for better visualization
            }
        },
        layer = [
            {
            :point  # Scatter points
            },
            {
            :line,  # Trend line
            transform = [{
            regression = "Env",
            on = "GDP",
            groupby = ["year"]
            }],
            encoding = {
            color = {
            :year,
            type = :ordinal,
            title = "Year",
            scale = {scheme = "viridis"},
            legend = {orient = :bottom}  # Place legend below the chart
            }
            }
            }
        ]
    )

    save("outputs/figures/env_gdp_evolution.svg", plot)

end

function plot_scatter_e_coeff!(m)

    Env_table = get_Env_pc(m, [2020])
    coef_env_damage = CSV.read("data/coef_env_damage.csv", DataFrame)
    rename!(coef_env_damage, :countrycode => :iso3)

    Env_table = leftjoin(Env_table, coef_env_damage, on=:iso3)

    scatter_data = Env_table[:, [:iso3, Symbol("2020"), :coef]]

    p_scatter = @vlplot(
        mark = :point,
        data = scatter_data,
        encoding = {
            x = {field = Symbol("2020"), type = :quantitative, title = "E (k USD / per capita)"},
            y = {field = :coef, type = :quantitative, title = "Coefficient (1 / °C)"},
            tooltip = {field = :iso3, type = :nominal, title = "Country"}
        },
        title = nothing
    )


    save("outputs/figures/scatter_E_coef.svg", p_scatter)
end

function plot_scatter_gdp_coeff!(m)

    GDP_table = get_Y_pc(m, [2020])

    coef_env_damage = CSV.read("data/coef_env_damage.csv", DataFrame)
    rename!(coef_env_damage, :countrycode => :iso3)

    GDP_table = leftjoin(GDP_table, coef_env_damage, on=:iso3)

    scatter_data = GDP_table[:, [:iso3, Symbol("2020"), :coef]]

    p_scatter = @vlplot(
        mark = :point,
        data = scatter_data,
        encoding = {
            x = {field = Symbol("2020"), type = :quantitative, title = "GDP per capita (k USD)"},
            y = {field = :coef, type = :quantitative, title = "Coefficient (1/°C)"},
            tooltip = {field = :iso3, type = :nominal, title = "Country"}
        },
        title = nothing
    )

    save("outputs/figures/scatter_GDP_coef.svg", p_scatter)

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
            title = nothing,
            projection = {type = :equirectangular}
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
                     title = "",
                     scale = {domain = [0, 20]}}
        )

        push!(map_env_list, map_env)
        save("outputs/maps/map_env_pc_$(year).svg", map_env)
    end

    return map_env_list

end

function map_env_pc_faceted!(m, year_vector)

    world110m = dataset("world-110m")

    long_table = get_Env_pc(m, year_vector)

    Env = DataFrame()

    for year in year_vector
        append!(Env, DataFrame(iso3=long_table.iso3,
                                E_percapita=long_table[:, string(year)],
                                year=year))
    end

    Env.id = [alpha3_to_numeric[iso3] for iso3 in Env.iso3]

    map = @vlplot(
        width=640,
        height=360,
        :geoshape,
        data=Env,
        transform=[{
            lookup=:id,
            from={
                data={
                    values=world110m,
                    format={
                        type=:topojson,
                        feature=:countries
                    }
                },
                key=:id
            },
            as=:geo
        }],
        projection={type=:equirectangular},
        encoding={
            shape={field=:geo,type=:geojson},
            color={field=:E_percapita,type=:quantitative},
            row={field=:year,type=:nominal}
        }
    )

    save("outputs/maps/map_env_faceted.svg", map)
end

function EDE_GreenNICE_NICE(emissions_scenarios)

    list_scenario = []
    for scenario in emissions_scenarios

        list_EDE = []

        #first GreenNICE
        m = GreenNICE.create(scenario)
        run(m)
        push!(list_EDE, m[:welfare, :cons_EDE_global])

        #Second, Original NICE
        update_param!(m, :α, 0.0)
        run(m)
        push!(list_EDE, m[:welfare, :cons_EDE_global])

        push!(list_scenario, list_EDE)
    end

    return(list_scenario)

end

function plot_EDE_GreenNICE_NICE!(emissions_scenario, end_year, save_name)

    EDE_list = EDE_GreenNICE_NICE(emissions_scenario)

# Prepare the data for plotting
    data = DataFrame(year = Int[], EDE = Float64[], scenario = String[], model = String[])

    for (i, scenario) in enumerate(EDE_list)
        for (j) in 1:2

            EDE = EDE_list[i][j]
                for (k, year) in enumerate(2020:end_year)
                    push!(data, (year = year,
                                EDE = EDE[k],
                                scenario = emissions_scenario[i],
                                model = j == 1 ? "GreenNICE" : "NICE"))
                end
        end
    end

    # create and save plot
    p = @vlplot(
    mark = {type=:line, strokeWidth=0.5},
    data = data,
    encoding = {
        x = {field = :year, type = :quantitative},
        y = {field = :EDE, type = :quantitative},
        color = {field = :scenario, type = :nominal},
        strokeDash = {
            field = :model,
            type = :nominal,
            legend = :model
        }
        },
    title = nothing
    )

    save("outputs/figures/$(save_name).svg", p)
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

# See if it can be improved. Otherwise, delete.

function Plot_all_EDE!( m,
    damage_params,
    alpha_params,
    theta_params,
    eta_params,
    end_year)

# Prepare the data for plotting
data = DataFrame(year = Int[], EDE = Float64[], var = Float64[], damage_type = Int[],
damage_label = String[], parameter = String[])

damage_type_labels = Dict(1 => "GreenNice",
    2 => "Unequal damages",
    3 => "Unequal natural capital",
    4 => "Same natural capital and damages"
 )

parameters_list = [alpha_params, theta_params, eta_params]

greek_letter = "α"

for var_params in parameters_list
    reset!(m)
    if var_params == alpha_params
    greek_letter = "α"
        elseif var_params == theta_params
        greek_letter = "θ"
        elseif var_params == eta_params
        greek_letter = "η"
    end

    EDE_estimates = EDE_trajectories(m, damage_params, var_params, greek_letter)

# Generate the data based on the input parameters
    for (j, alpha) in enumerate(var_params)
        for (i, param) in enumerate(damage_params)
        EDE = EDE_estimates[j][i]
            for (k, year) in enumerate(2020:end_year)
            push!(data, (year = year,
            EDE = EDE[k],
            var = alpha,
            damage_type = param,
            damage_label = get(damage_type_labels, param, "Unknown"),
            parameter = greek_letter))
            end
        end
    end
end

p = @vlplot(
mark = {type=:line, strokeWidth=0.5},
data = data,
encoding = {
column = :parameter,
x = {field = :year, type = :quantitative},
y = {field = :EDE, type = :quantitative},
color = {field = :var, type = :nominal},
strokeDash = {
field = :damage_label,
type = :nominal,
legend = nothing
}
}#,
#title = "EDE Trajectories for Different Values of $param_name"
)

# Show the plot
display(p)

# Optionally, save the plot to a file (e.g., as SVG)
save("outputs/figures/TESTING.svg", p)

end

function get_Atkinson_index(m, year_end, region_level)

    if region_level == "country"
        c_EDE = m[:welfare, :cons_EDE_country]
        c = m[:quantile_recycle, :CPC_post]

    elseif region_level == "region"
        c_EDE = m[:welfare, :cons_EDE_rwpp]
        c = m[:quantile_recycle, :CPC_post_rwpp]
    else
        c_EDE = m[:welfare, :cons_EDE_global]
        c = m[:quantile_recycle, :CPC_post_global]
    end

    Atkinson = 1 .- (c_EDE ./ c)

    Atkinson = Atkinson[1:year_end-2019, :]

    return Atkinson
end

function get_Atkinson_dataframe(m, year_end, region_level)

    atkinson_index = get_Atkinson_index(m, year_end, region_level)

    if region_level == "country"
        column_names = DataFrame(CSV.File("data/country_list.csv"))
        sort!(column_names, :countrycode)
        column_names = column_names.countrycode
    elseif region_level == "region"
        regions = DataFrame(CSV.File("data/WPP_regions_country_list.csv"))
        sort!(regions, :WPP_region_number)
        column_names = unique(regions.WPP_region_name)
    else
        column_names = ["Atkinson_index"]
    end

    Atkinson_dataframe = DataFrame(atkinson_index, Symbol.(column_names))
    Atkinson_dataframe.year = 2020:(2020 + size(atkinson_index, 1) - 1)

    return Atkinson_dataframe
end

function plot_Atkinson_envdamage(m, damage_options, year_end=2100)

    Atk_damage = []

    damage_type_labels = Dict(1 => "GreenNice",
    2 => "Unequal damages",
    3 => "E baseline",
    4 => "E equal share"
    )

    for param in damage_options
        update_param!(m, :environment, :dam_assessment, param)
        run(m)

        Atk_df = get_Atkinson_dataframe(m, year_end, "global")
        Atk_df[:, :damage_options] .= damage_type_labels[param]
        push!(Atk_damage, Atk_df)
    end
    Atk_damage_long = vcat(Atk_damage...)

 p = @vlplot(
    mark = {type = :line, strokeWidth = 1.5},
    data = Atk_damage_long,
    encoding = {
        x = {field = :year, type = :quantitative},
        y = {field = :Atkinson_index, type = :quantitative, title = "Atkinson Index"},
        color = {
            field = :damage_options,
            type = :nominal,
            title = "Damage Type",
            scale = {
                domain = ["GreenNice", "E baseline", "E equal share"],
                range = ["#ff7f0e", "#2ca02c", "#1f77b4"]
            },
            legend = {orient = :bottom}
        },
        strokeDash = {
            field = :damage_options,
            type = :nominal,
            title = "Damage Type",
            scale = {
                domain = ["GreenNice", "E baseline", "E equal share"],
                range = [[], [1, 3], [5, 5]]
            }
        }
    }
)
    save("outputs/figures/Atkinson_Env_damages.svg", p)

    differences = Atk_damage_long[(Atk_damage_long.damage_options .== "GreenNice") .& (Atk_damage_long.year .== year_end), :Atkinson_index] .-
                  Atk_damage_long[(Atk_damage_long.damage_options .== "E equal share") .& (Atk_damage_long.year .== year_end), :Atkinson_index]

    return differences
end

function get_Atkinson_trajectories(m, alpha_params, theta_params, eta_params, end_year = 2100)

    parameter_list = ["α", "θ", "η"]
    output = []

    for param in parameter_list
        Atk_dataframe = []

        if param == "α"
            list = alpha_params
        elseif param == "θ"
            list = theta_params
        else
            list = eta_params
        end

        values = minimum(list):0.05:maximum(list)

        for value in values
            if param == "θ" && value == 0
                continue
            end

            reset!(m)
            update_param!(m, Symbol(param), value)
            run(m)

            Atk_df = get_Atkinson_dataframe(m, end_year, "global")
            Atk_df[:, param] .= value
            push!(Atk_dataframe, Atk_df)
        end

        Atk_dataframe = vcat(Atk_dataframe...)
        push!(output, Atk_dataframe)
    end

    return output
end

function get_Atkinson_lastyear(m, alpha_params, theta_params, eta_params, end_year)

    Dataframes = get_Atkinson_trajectories(m,
                                        alpha_params,
                                        theta_params,
                                        eta_params,
                                        end_year)
    Atkinson_year_parameter = []

        for Atk_df in Dataframes
            last_year_data = filter(row -> row[:year] == maximum(Atk_df.year), Atk_df)
            push!(Atkinson_year_parameter, last_year_data)
        end

        return Atkinson_year_parameter

end

function plot_Atkinson_param!(m, alpha_params, theta_params, eta_params, end_year = 2100)



    Atkinson_end_year = get_Atkinson_lastyear(m,
                                            alpha_params,
                                            theta_params,
                                            eta_params,
                                            end_year)

    for Atk_df in Atkinson_end_year

         p = @vlplot(
             mark = {type=:line, strokeWidth=1.5},
             data = Atk_df,
             encoding = {
                 x = {field = names(Atk_df)[3], type = :quantitative},
                 y = {field = :Atkinson_index,
                        type = :quantitative,
                        scale = {domain = [0, 0.6]},
                        title = "Atkinson index"},
             }
         )

         display(p)
         if names(Atk_df)[3] == "α"
             save("outputs/figures/Atkinson_alpha.svg", p)
         elseif names(Atk_df)[3] == "θ"
             save("outputs/figures/Atkinson_theta.svg", p)
         elseif names(Atk_df)[3] == "η"
             save("outputs/figures/Atkinson_eta.svg", p)
        end
    end

    for table in Atkinson_end_year
        rename!(table, names(table)[3] => :value)
    end

    Atkinson_end_year[1][:, :parameter] .= "α"
    Atkinson_end_year[2][:, :parameter] .= "θ"
    Atkinson_end_year[3][:, :parameter] .= "η"

    # Merge the tables into one
    merged_table = vcat(Atkinson_end_year...)

    p_faceted = @vlplot(
        mark = {type=:line, strokeWidth=1.5},
        data = merged_table,
        column = {field = :parameter, title = nothing, header = {labelOrient = "bottom"}},
        encoding = {
            x = {field = :value, type = :quantitative, title = nothing},
            y = {field = :Atkinson_index,
                    type = :quantitative,
                    title = "Atkinson Index (2100)"},
        },
        resolve = {
            scale = {x = "independent"}
        },
        config = {
            header = {
                labelFontWeight = "bold"
            }
        }
    )

    save("outputs/figures/Atkinson_param_faceted.svg", p_faceted)

 end

 function plot_Atkinson_scenario_param!(alpha_params,
    theta_params,
    eta_params,
    emissions_scenarios = ["ssp245"],
    end_year = 2100)

    list_scenarios = []

    for emissions in emissions_scenarios

        m = GreenNICE.create(emissions)
        run(m)

        Atkinson_end_year = get_Atkinson_lastyear(m,
                        alpha_params,
                        theta_params,
                        eta_params,
                        end_year)

        for table in Atkinson_end_year
            rename!(table, names(table)[3] => :value)
        end

        Atkinson_end_year[1][:, :parameter] .= "α"
        Atkinson_end_year[2][:, :parameter] .= "θ"
        Atkinson_end_year[3][:, :parameter] .= "η"

        # Merge the tables into one
        merged_table = vcat(Atkinson_end_year...)
        merged_table[:, :scenario] .= emissions

        push!(list_scenarios, merged_table)
    end

    table_scenarios = vcat(list_scenarios...)

    p_faceted = @vlplot(
    mark = {type = :line, strokeWidth = 1.0},
    data = table_scenarios,
    column = {
        field = :parameter,
        title = nothing,
        header = {labelOrient = "bottom"}
    },
    encoding = {
        x = {field = :value, type = :quantitative, title = nothing},
        y = {field = :Atkinson_index, type = :quantitative, title = "Atkinson Index (2100)"},
        color = {field = :scenario,
                type = :nominal,
                title = "Scenario",
                legend = {orient = "bottom"}}
    },
    resolve = {
        scale = {x = "independent"}
    },
    config = {
        header = {
            labelFontWeight = "bold"
        }
    }
)

save("outputs/figures/Atkinson_scenario_param_faceted.svg", p_faceted)

end

function plot_c_EDE!(end_year = 2100)

    m = GreenNICE.create()
    run(m)

    c = m[:quantile_recycle, :CPC_post_global]
    EDE_GreenNICE = m[:welfare, :cons_EDE_global]

    update_param!(m, :α, 0.0)
    run(m)
    EDE_NICE = m[:welfare, :cons_EDE_global]

    year = 2020:end_year
    df = DataFrame(
        year = year,
        c = c[1:length(year)],
        EDE_GreenNICE = EDE_GreenNICE[1:length(year)],
        EDE_NICE = EDE_NICE[1:length(year)]
    )

    df_long = stack(df, Not(:year), variable_name=:c_type, value_name=:Value)

    label_map = Dict(
        "c" => "Consumption",
        "EDE_GreenNICE" => "EDE (greenNICE)",
        "EDE_NICE" => "EDE (NICE)"
    )

    df_long.label = [label_map[c] for c in df_long.c_type]

    # Step 2: Plot using `label` column
    p = @vlplot(
        mark = {type = :line, strokeWidth = 1.5},
        data = df_long,
        encoding = {
            x = {field = :year, type = :quantitative, title = "Year"},
            y = {field = :Value, type = :quantitative, title = "2017 kUSD/year"},
            color = {
                field = :label,
                type = :nominal,
                title = nothing,
                scale = {
                    domain = [
                        "EDE (NICE)",
                        "EDE (greenNICE)",
                        "Consumption"
                    ],
                    range = ["#1f77b4", "#ff7f0e", "#d62728"]
                },
                legend = {
                    orient = :bottom#,
                    #direction = "vertical"
                }
            },
            strokeDash = {
                condition = {test = "datum.c_type === 'EDE_NICE'", value = [5, 5]},
                value = []
            }
        }
    )

display(p)
    save("outputs/figures/c_EDE.svg", p)

end

function plot_Atkinson_emissionscenario(emissions_scenarios, year_end = 2100)

    Atkinson_scenario_list = []

    for scenario in emissions_scenarios
        m = GreenNICE.create(scenario)
        run(m)

        Atkinson_scenario = get_Atkinson_dataframe(m, year_end, "global")
        Atkinson_scenario[!, :scenario] .= scenario

        push!(Atkinson_scenario_list, Atkinson_scenario)
    end

    combined_df = vcat(Atkinson_scenario_list...)
    combined_df_long = stack(combined_df,
                            Not([:year, :scenario]),
                            variable_name=:Atkinson_index,
                            value_name=:Value)

    # Calculate percentage difference with respect to :Atkinson_index == ssp245
    reference_scenario = "ssp245"
    reference_df = filter(row -> row[:scenario] == reference_scenario, combined_df)
    reference_values = Dict(row[:year] => row[:Atkinson_index]
                            for row in eachrow(reference_df))

    combined_df_long[!, :Difference] .= [row[:Value] - reference_values[row[:year]]
                                        for row in eachrow(combined_df_long)]


    p = @vlplot(
        mark = {type=:line, strokeWidth=1.5},
        data = combined_df_long,
        encoding = {
            x = {field = :year, type = :quantitative},
            y = {field = :Difference, type = :quantitative, title = "Difference"},
            color = {field = :scenario,
                type = :nominal,
                title = "Scenario",
                scale = {
                    domain = ["ssp119", "ssp126", "ssp245", "ssp370", "ssp585"],
                    range  = ["#1f77b4", "#2ca02c", "#ff7f0e", "#d62728", "#9467bd"]
                },
                legend = {
                    orient = :bottom,
                    columns = 3
                }
            }
        }
    )

    save("outputs/figures/Atkinson_Emissions_Scenarios.svg", p)

    difference_table =
        filter(row -> row[:year] == year_end, combined_df_long)[!, [:scenario, :Difference]]


    return difference_table

end



function plot_Atkinson_global(year_end = 2100)
    m= GreenNICE.create()
    run(m)

    Global_Atkinson = get_Atkinson_dataframe(m, year_end, "global")

    m_0 = GreenNICE.create()
    update_param!(m_0, :α, 0.0)
    run(m_0)

    Atkinson_NICE = get_Atkinson_dataframe(m_0, year_end, "global")

    insertcols!(Global_Atkinson, :model => "GreenNICE")
    insertcols!(Atkinson_NICE, :model => "NICE")

    append!(Global_Atkinson, Atkinson_NICE)

    q = @vlplot(
        mark = {type=:line, strokeWidth=1.5},
        data = Global_Atkinson,
        encoding = {
            x = {field = :year, type = :quantitative},
            y = {field = :Atkinson_index, type = :quantitative, title = "Atkinson Index"},
            color = {
                field = :model,
                type = :nominal,
                scale = {
                    domain = ["GreenNICE", "NICE"],
                    range = ["#ff7f0e", "#1f77b4"]
                },
                legend = {orient = :bottom}
            }
        },
        title = nothing
    )

    save("outputs/figures/Atkinson_Global.svg", q)

    difference = Global_Atkinson[Global_Atkinson.year .== 2100, :Atkinson_index][1] -
                 Global_Atkinson[Global_Atkinson.year .== 2100, :Atkinson_index][2]

    return difference
end

function table_Atkinson_regions!(m, m_0, year_end = 2100)

    Regions_Atkinson = get_Atkinson_dataframe(m, 2100, "region")

    Regions_Atkinson_0 = get_Atkinson_dataframe(m_0, 2100, "region")

    update_param!(m, :environment, :dam_assessment, 4)
    run(m)

    Regions_Atkinson_same = get_Atkinson_dataframe(m, 2100, "region")

    update_param!(m, :environment, :dam_assessment, 3)
    run(m)

    Regions_Atkinson_unequalE = get_Atkinson_dataframe(m, 2100, "region")



    regions = names(Regions_Atkinson)[1:end-1]
    I_GreenNICE = [Regions_Atkinson[end, region] for region in regions]
    I_NICE = [Regions_Atkinson_0[end, region] for region in regions]
    Diff = I_GreenNICE .- I_NICE
    I_same = [Regions_Atkinson_same[end, region] for region in regions]
    I_unequalE = [Regions_Atkinson_unequalE[end, region] for region in regions]

    table_data = DataFrame(
        Region = regions,
        NICE = I_NICE,
        GreenNICE = I_GreenNICE,
       # Difference = Diff,
        Equal_dam = I_same,
        Unequal_dam = I_unequalE
    )

    table_data.GreenNICE .= round.(table_data.GreenNICE, digits=3)
    table_data.NICE .= round.(table_data.NICE, digits=3)
    #table_data.Difference .= round.(table_data.Difference, digits=3)
    table_data.Equal_dam .= round.(table_data.Equal_dam, digits=3)
    table_data.Unequal_dam .= round.(table_data.Unequal_dam, digits=3)

    header = ["Region", "NICE", "greenNICE",
              "E Equal share", "E baseline"]

    # Write LaTeX table to a .tex file using an IO stream
    open("outputs/tables/Atkinson_regions.tex", "w") do io
        pretty_table(
            io,
            table_data;
            backend = Val(:latex),
            tf = tf_latex_double,
            header = header,
            wrap_table = true,
            table_type = :tabular,
            label = "t:Atkinson_regions"
        )
    end

end

function plot_Atkinson_regions(m, m_0, list_regions, year_end = 2100)

    Regions_Atkinson = get_Atkinson_dataframe(m, year_end, "region")
    Regions_Atkinson_0 = get_Atkinson_dataframe(m_0, year_end, "region")

    Regions_Atkinson = Regions_Atkinson[:, Cols(:year, list_regions...)]
    Regions_Atkinson_0 = Regions_Atkinson_0[:, Cols(:year, list_regions...)]

    Regions_Atkinson[:, :model] .= "GreenNICE"
    Regions_Atkinson_0[:, :model] .= "NICE"

    Regions_Atkinson_combined= vcat(
        Regions_Atkinson,
        Regions_Atkinson_0
    )
    Regions_Atkinson_combined = stack(Regions_Atkinson_combined,
                                    Not(:year, :model),
                                    variable_name = :Region,
                                    value_name = :Atkinson_index)

    p = @vlplot(
        mark = {type = :line, strokeWidth = 1.5},
        data = Regions_Atkinson_combined,
        encoding = {
            x = {field = :year, type = :quantitative},
            y = {field = :Atkinson_index, type = :quantitative, title = "Atkinson Index"},
            color = {field = :Region, type = :nominal, title = "WPP Region"},
            strokeDash = {
                field = :model,
                type = :nominal,
                scale = {domain = ["GreenNICE", "NICE"]},
                title = "Model"
            }
        },
        title = nothing
    )

    save("outputs/figures/Atkinson_NICEgreenNICE_regions.svg", p)

    Regions_Atkinson_diff = Regions_Atkinson_combined[Regions_Atkinson_combined.year .== year_end, :]
    Regions_Atkinson_diff = unstack(Regions_Atkinson_diff, :model, :Atkinson_index)
    Regions_Atkinson_diff[:, :Difference] .= Regions_Atkinson_diff.GreenNICE .- Regions_Atkinson_diff.NICE

    return Regions_Atkinson_diff

end

function plot_Atkinson_region_envdamage(m, damage_options, list_regions, year_end = 2100)

    Atk_damage = []

    damage_type_labels = Dict(1 => "GreenNice",
    2 => "Unequal damages",
    3 => "E Baseline",
    4 => "E equal share"
    )

    for param in damage_options
        update_param!(m, :environment, :dam_assessment, param)
        run(m)

        Atk_df = get_Atkinson_dataframe(m, year_end, "region")
        Atk_df = Atk_df[:, Cols(:year, list_regions...)]
        Atk_df[:, :damage_options] .= damage_type_labels[param]
        push!(Atk_damage, Atk_df)
    end

    Atk_damage_long = vcat(Atk_damage...)
    Atk_damage_long = stack(Atk_damage_long, Not(:year, :damage_options), variable_name = :region, value_name = :Atkinson_index)
    Atk_damage_long.region .= replace.(Atk_damage_long.region, "Australia and New Zealand" => "Australia an NZ")
    p = @vlplot(
        mark = {type = :line, strokeWidth = 1.0},
        data = Atk_damage_long,
        encoding = {
            x = {field = :year, type = :quantitative},
            y = {field = :Atkinson_index, type = :quantitative, title = "Atkinson Index"},

            color = {
                field = :region,
                type = :nominal,
                title = "Region",
                legend = {orient = :right}
            },

            strokeDash = {
                field = :damage_options,
                type = :nominal,
                scale = {
                    domain = ["GreenNice", "E baseline", "E equal share"],
                    range = [[], [1, 3], [5, 5]]
                },
                legend = {
                    title = "Damage Type",
                    orient = :bottom,
                    columns = 3
                }
            }
        }
    )

    save("outputs/figures/Atkinson_region_Env_damages.svg", p)

    # Calculate the difference in Atkinson index for each region
    Atk_diff = Atk_damage_long[(Atk_damage_long.damage_options .== "GreenNice") .& (Atk_damage_long.year .== year_end), :]
    Atk_diff_4 = Atk_damage_long[(Atk_damage_long.damage_options .== "E equal share") .& (Atk_damage_long.year .== year_end), :]

    diff_table = DataFrame(
        region = Atk_diff.region,
        difference = Atk_diff.Atkinson_index .- Atk_diff_4.Atkinson_index
    )

    return diff_table

end

function get_Atkinson_country(m, list_countries, year_end = 2100)

    countries = DataFrame(CSV.File("data/country_list.csv"))
    country_df = DataFrame(year = Int[], Atkinson_index = Float64[], country = String[])
    years = 2020:year_end

    EDE_matrix = m[:welfare, :cons_EDE_country]
    c_matrix = m[:quantile_recycle, :CPC_post]

        for iso3 in list_countries
            index = findfirst(row -> row == iso3, countries[!,:countrycode])
            Atkinson_country = EDE_matrix[:, index] ./ c_matrix[:, index]
            years = 2020:year_end
            for (i, year) in enumerate(years)
                push!(country_df, (year, Atkinson_country[i], iso3))
            end
        end


    return country_df
end

function plot_Atkinson_country_envdamage!(m, damage_options, list_countries, year_end = 2100)

    atk_dataframe = DataFrame(year = Int[], Atkinson_index = Float64[], country = String[],
                                damage_type = String[])

    damage_type_labels = Dict(1 => "GreenNice",
    2 => "Unequal damages",
    3 => "E Baseline",
    4 => "E equal share"
    )

    for damage in damage_options
        update_param!(m, :environment, :dam_assessment, damage)
        run(m)
        Atk_country = get_Atkinson_country(m, list_countries, year_end)

        for row in eachrow(Atk_country)
            push!(atk_dataframe, (row.year, row.Atkinson_index, row.country, damage_type_labels[damage]))
        end

    end

    p = @vlplot(
        mark = {type=:line, strokeWidth=1.0},
        data = atk_dataframe,
        encoding = {
            x = {field = :year, type = :quantitative},
            y = {field = :Atkinson_index, type = :quantitative, title = "Atkinson Index"},
            color = {field = :country, type = :nominal, title = "Country"},
            strokeDash = {field = :damage_type,
                        type = :nominal,
                        scale = {
                            domain = ["GreenNice", "E baseline", "E equal share"],
                            range = [[], [1, 3], [5, 5]]},
                            legend = {
                                title = "Damage Type",
                                orient = :bottom,
                                columns = 3
                            }
        }
        }
    )

    display(p)
    save("outputs/figures/Atkinson_country_Env_damages.svg", p)
end

function plot_density!()
    coef_env_damage = CSV.read("data/coef_env_damage.csv", DataFrame)

   p = @df coef_env_damage density(:coef,
                            xlabel="Damage coefficient",
                            ylabel="Density",
                            legend=false)

    savefig(p, "outputs/figures/density_coefficient_damage.svg")
end

function plot_rel_price(alpha_params, theta_params, year_end = 2100)

    m = GreenNICE.create()

    alpha_vector = minimum(alpha_params):0.05:maximum(alpha_params)
    theta_vector = minimum(theta_params):0.05:maximum(theta_params)

    Table = DataFrame(Atkinson_Index = Float64[], α = Float64[], θ = Float64[])

    for i in alpha_vector
        for j in theta_vector
            try
                update_param!(m, :α, i)
                update_param!(m, :θ, j)
                run(m)

                c_EDE = m[:welfare, :cons_EDE_global]
                c = m[:quantile_recycle, :CPC_post_global]

                Atkinson = 1 .- (c_EDE ./ c)

                Atkinson = Atkinson[year_end-2019, :]
                Atkinson = Atkinson[1]

                push!(Table, (Atkinson, i, j))
            catch e
                Atkinson = NaN
                push!(Table, (Atkinson, i, j))
                continue
            end
        end
    end

    Table = DataFrame([replace(col, NaN => missing) for col in eachcol(Table)], names(Table))

    plot =  @vlplot(
    width = 400,  # wider
    height = 400,
    mark = {type = :rect},
    data = Table,
    encoding = {
        y = {field = :α, type = :ordinal, title = "α", sort = "descending"},
        x = {field = :θ, type = :ordinal, title = "θ"},
        color = {
            field = :Atkinson_Index,
            type = :quantitative,
            title = "Atkinson Index",
            scale = {
                scheme = "viridis",
                nullValue = "lightgray"
            }
        }
    }
)

    save("outputs/figures/Atkinson_alpha_theta.svg", plot)

    return Table

end
