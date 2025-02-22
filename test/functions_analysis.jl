using DataFrames, RCall, CSV, Downloads

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

function Env_damages_EDE_trajectories(m, array_damage_type, array_α)

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

function plot_EDE_trajectories!(EDE_estimates, array_params, alpha_params, end_year)
    p = plot()

    # Create a mapping for alpha values to line styles
    linestyle_map = Dict(0.1 => :solid, 0.2 => :dash, 0.3 => :dashdotdot)

    for (j, alpha) in enumerate(alpha_params)
        for (i, param) in enumerate(array_params)
            linestyle = linestyle_map[alpha]
            color = [:blue, :green, :red, :purple][param % 4 + 1]

            plot!(p,
                EDE_estimates[j][i],
                label="",
                linestyle=linestyle,
                color=color)
        end
    end

    # Create labels by plotting invisible lines
    plot!(p, rand(1), color= :blue, label = "Equal E, equal damages")
    plot!(p, rand(1), color= :green, label = "Different E, different damages")
    plot!(p, rand(1), color= :red, label = "Equal E, different damages")
    plot!(p, rand(1), color= :purple, label = "Different E, equal damages")
    plot!([1], [0], linestyle = :solid, label = "α = 0.1", color = "black")
    plot!([1], [0], linestyle = :dash, label = "α = 0.2", color = "black")
    plot!([1], [0], linestyle = :dashdotdot, label = "α = 0.3", color = "black")

    # Labels and title
    xlabel!("Year")
    ylabel!("EDE Global Consumption")
    title!("EDE Trajectories for Different Parameters")
    plot!(p, legend=:bottomright)

    # Display the plot
    display(p)
    # Save the plot as SVG
    savefig(p, "test/figures/EDE_Trajectories.svg")
end
