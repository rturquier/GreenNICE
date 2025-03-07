using DataFrames, RCall, CSV, Downloads
using VegaLite

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

    coef_damages = DataFrame(CSV.File(joinpath(@__DIR__, "..", "data", "coef_env_damage.csv"),
                                        header=true))
    rename!(coef_damages, :countrycode => :iso3)


    Damage_table= leftjoin(Damage_table, coef_damages, on=:iso3)

    Damage_table[!, :e_end] = Damage_table.e0 .* (1 .+ temperature .* Damage_table.coef)

    Damage_table[!, :abs_loss] = Damage_table.e_end .- Damage_table.e0

    Damage_table[!, :percent_change] =
    (Damage_table.e_end .- Damage_table.e0) ./ Damage_table.e0 * 100

    return(Damage_table)

end

function plot_env_damages!(Damage_table, title, save_name)

    ## Function, plot to map based on ISO 3 (taken from: https://github.com/alfaromartino/coding/blob/main/assets/PAGES/01_heatmaps_world/codeDownload/allCode.jl)
    R"""
    library(ggplot2)
    library(svglite) #to save graphs in svg format, otherwise not necessary

    """

    get_coordinates = Downloads.download("https://alfaromartino.github.io/data/countries_mapCoordinates.csv")
    df_coordinates = DataFrame(CSV.File(get_coordinates)) |> x-> dropmissing(x, :iso3)

    merged_df = leftjoin(df_coordinates, Damage_table, on=:iso3)
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
                                            fill=percent_change),
                                        color = "black", linewidth = 0.1) +
                            user_theme() +
                            coord_fixed(1.3) +
                            scale_fill_gradient2(low = "#d73027",
                                                mid = "#ffffbf",
                                                high ="#1a9850",
                                                name = "Non-market Natural Capital\nPercent Change") +
                            ggtitle($(title))



    height <- 5

    ggsave(filename = file.path($(graphs_folder), paste0($(save_name), ".svg")),
                            plot = map_damages,
                            width = height * 3,
                            height = height)
    """

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
