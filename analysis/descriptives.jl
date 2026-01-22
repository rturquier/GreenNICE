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

    E_flow0_percapita = @chain getdataframe(m, :environment, :E_flow_percapita) begin
        @filter(time == 2020)
        @filter(quantile == "First")
        @mutate(E_flow0_percapita = 1000 .* E_flow_percapita)
        @select(country, E_flow0_percapita)
    end

    df = @chain getdataframe(m, :quantile_recycle, :gini_cons) begin
        @filter(time == 2020)
        @left_join(E_flow0_percapita)
        @left_join(damage_coeficient)
        @mutate(gini_cons = Float64.(gini_cons))
        @mutate(E_flow0_percapita = Float64.(E_flow0_percapita))
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

    df = @left_join(df, df_regions)

    return df
end

function get_country_id(df::DataFrame)::DataFrame

    df_country = @chain begin
        DataFrame(all_countries())
        @select(country = alpha3, id = numeric)
        @mutate(country = Symbol.(country))
        @left_join(df)
    end

    df_country.ξ = Float64.(coalesce.(df_country.ξ, NaN))
    df_country.E_flow0_percapita = Float64.(coalesce.(df_country.E_flow0_percapita, NaN))

    return df_country
end

function plot_gini_E_stock0(df::DataFrame)::VegaLite.VLSpec
    plot = @vlplot(
        data = df,
        mark = :circle,
        x = {field = :E_flow0_percapita,
                title = "Initial yearly flow of ecosystem services per capita (USD)"},
        y = {field = :gini_cons,
                title = "Consumption Gini index"},
        width = 500,
        height = 200,
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
                     title = "Damage coefficient (1/°C)"}
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

    @vlplot(
        width = 640,
        height = 360,
        projection = { type = :equirectangular },
        data = {
            values = world110m,
            format = { type = :topojson, feature = :countries }
        },
        transform = [{
            lookup = "id",
            from = {
                data = df_country,
                key = :id,
                fields = ["E_flow0_percapita"]
            }
        }],
        mark = :geoshape,
        encoding = {
            color = {
                field = "E_flow0_percapita",
                type = :quantitative,
                bin = {
                    step = nothing,
                    thresholds = [0, 20, 100, 200]
                },
                scale = {
                    scheme = "greenblue"
                },
                legend = {
                    title = "E per capita (USD)"
                }
            }
        }
    )
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
        transform = [
            {
                lookup = "id",
                from = {
                    data = df_country,
                    key = :id,
                    fields = ["ξ"]
                }
            },
            {
                filter = "datum.ξ != null"
            },
            {
                bin = {step = 0.05, extent = [-0.05, 0.05]},
                field = "ξ",
                as = "ξ_binned"
            }
        ],
        mark = :geoshape,
        encoding = {
            color = {
                field = "ξ_binned",
                type = "ordinal",
                title = "ξ",
                legend = {
                    labelExpr = "datum.label == -0.05 ? '[-0.05, 0)' : " *
                                "datum.label == 0 ? '[0, 0.05)' : " *
                                "datum.label < 0 ? '< -0.05' : " *
                                "'≥ 0.05'"
                },
                scale = {
                    scheme = "purplegreen",
                    reverse = false
                }
            }
        }
    )

    return ξ_country
end

function plot_temperature_trajectory(model::Mimi.Model)
    temperature_df = getdataframe(m, :damages => :temp_anomaly)
    initial_temperature = temperature_df.temp_anomaly[1]
    temperature_plot = temperature_df |> @vlplot(
        mark={:line, color="#AA1144"},
        x={
            :time,
            axis={
                title="Year",
                format="d",
                labelFlush=false,
                values=[2020, 2050, 2100, 2150, 2200, 2250, 2300]
            }
        },
        y={
            :temp_anomaly,
            axis={
                title="Temperature anomaly (°C)",
                labelExpr="format(datum.value, '+.3~r') + '°'",
                values=[0, initial_temperature, 1.5, 2.0]
            }
        },
        width=500,
        height=250,
    )
    return temperature_plot
end
