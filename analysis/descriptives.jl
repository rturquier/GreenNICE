using Mimi
using TidierData
using TidierFiles
using VegaLite
using Countries
using VegaDatasets

include("../src/GreenNICE.jl")
using .GreenNICE

function get_descriptives_df()::DataFrame

    m = GreenNICE.create()
    run(m)

    damage_coeficient = getdataframe(m, :damages, :ξ)

    E_stock0_percapita = @chain getdataframe(m, :environment, :E_flow_percapita) begin
        @filter(time == 2020)
        @filter(quantile == "First")
        @mutate(E_stock0_percapita = E_flow_percapita / 0.96)
        @select(country, E_stock0_percapita)
    end


    df = @chain getdataframe(m, :quantile_recycle, :gini_cons) begin
        @filter(time == 2020)
        leftjoin(E_stock0_percapita, on = :country)
        leftjoin(damage_coeficient, on = :country)
        @mutate(gini_cons = Float64.(gini_cons))
        @mutate(E_stock0_percapita = Float64.(E_stock0_percapita))
        @mutate(ξ = Float64.(ξ))
        @select(-:time)
    end

    return df
end

function get_WPP_regions(df::DataFrame)::DataFrame

    df_regions = @chain CSV.read("data/WPP_regions_country_list.csv", DataFrame) begin
        @mutate(country = Symbol.(countrycode))
        @mutate(WPP_region_name = Symbol.(WPP_region_name))
        @select(-(:WPP_region_number, :countrycode))
    end

    df = leftjoin(df, df_regions, on = :country)

    return df
end

function get_country_id(df::DataFrame)::DataFrame

    df_country = @chain begin
        DataFrame(all_countries())
        @select(country = alpha3, id = numeric)
        @mutate(country = Symbol.(country))
        leftjoin(df, on = :country)
    end

    return df_country
end

function plot_gini_E_stock0(df::DataFrame)::VegaLite.VLSpec
    plot = @vlplot(
        data = df,
        layer = [
            {
                mark = :point ,
                x = {field = :E_stock0_percapita,
                     title = "Natural capital stock per capita (k USD)"},
                y = {field = :gini_cons,
                     title = "Consumption gini index"}
            }
        ]
    )

    return plot
end

function plot_theta_E_stock0(df::DataFrame)::VegaLite.VLSpec
    plot = @vlplot(
        data = df,
        layer = [
            {
                mark = :point,
                x = {field = :E_stock0_percapita,
                     title = "Natural capital stock per capita (k USD)"},
                y = {field = :θ_env,
                     title = "Damage coefficient (1/ \u00B0C)"}
            },
            {
                transform = [
                    {
                        regression = :θ_env,
                        on = :E_stock0_percapita
                    }
                ],
                mark = { :line, color = "firebrick", opacity = 0.8 },
                x = :E_stock0_percapita,
                y = :θ_env
            }
        ]
    )

    return plot
end

function plot_E_stock_0_hconcat(df::DataFrame)::VegaLite.VLSpec

    vconcat_plot= @vlplot(
    data = df,
    hconcat=[
     {
        layer = [
            {
                mark = :point,
                x = {field = :E_stock0_percapita,
                     title = "Natural capital stock per capita (k USD)",
                     type = "quantitative"},
                y = {field = :gini_cons,
                     title = "Consumption gini index",
                     type = "quantitative"}
            },
            {
                transform = [
                    {
                        regression = :gini_cons,
                        on = :E_stock0_percapita
                    }
                ],
                mark = { :line, color = "firebrick", opacity = 0.8 },
                x = :E_stock0_percapita,
                y = :gini_cons
            }
        ]
    },
    {
        layer = [
            {
                mark = :point ,
                x = {field = :E_stock0_percapita,
                     title = "Natural capital stock per capita (k USD)",
                     type = "quantitative"},
                y = {field = :θ_env,
                     title = "Damage coefficient (1/ \u00B0C)",
                     type = "quantitative"}
            },
            {
                transform = [
                    {
                        regression = :θ_env,
                        on = :E_stock0_percapita
                    }
                ],
                mark = { :line, color = "firebrick", opacity = 0.8 },
                x = :E_stock0_percapita,
                y = :θ_env
            }
        ]
    }
    ]
    )

    return vconcat_plot
end

function plot_descriptive_coefficients(df::DataFrame)::VegaLite.VLSpec

    df = get_WPP_regions(df)

    circle_plot = @vlplot(
        :circle,
        data = df,
        y = {field = :θ_env, title = "Damage coefficient (1/ °C)"},
        x = {field = :gini_cons, title = "Consumption gini index"},
        color = {field = :WPP_region_name,
                 type = "nominal",
                 title = "Region",
                 legend = {orient = "right", columns = 2},
                 scale = {scheme = "category20"}},
        size = {field = :E_stock0_percapita,
                title = ["Natural capital stock", "percapita (k USD)"],
                legend = {orient = "right", direction = "horizontal" }}
    )

    return circle_plot
end


function map_E_percapita_country(df::DataFrame)::VegaLite.VLSpec

    df_country = get_country_id(df)

    world110m = dataset("world-110m")

    E_percapita_country = @vlplot(
        width = 640,
        height = 360,
        title = "",
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
                data = df_country,
                key = :id,
                fields = ["E_stock0_percapita"]
            }
        }],
        mark = :geoshape,
        encoding = {
            color = {
                field = "E_stock0_percapita",
                type = "quantitative",
                title = "",
                scale = {
                    scheme = "greenblue"
                }
            }
        }
    )

    return E_percapita_country
end


function map_damage_coefficient_country(df::DataFrame)::VegaLite.VLSpec

    df_country = get_country_id(df)

    world110m = dataset("world-110m")

    ξ_country = @vlplot(
        width = 640,
        height = 360,
        title = "",
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
                data = df_country,
                key = :id,
                fields = ["ξ"]
            }
        }],
        mark = :geoshape,
        encoding = {
            color = {
                field = "ξ",
                type = "quantitative",
                title = "ξ",
                scale = {
                    scheme = "plasma"
                }
            }
        }
    )

    return ξ_country
end
