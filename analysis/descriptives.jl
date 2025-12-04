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

    damage_coeficient = @chain getdataframe(m, :damages, :θ_env) begin
        @mutate(θ_env = Float64.(θ_env))
    end

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
        @mutate(E_stock0_percapita = Float64.(E_stock0_percapita))
        @mutate(gini_cons = Float64.(gini_cons))
    end

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
                mark = { :point },
                x = {field = :E_stock0_percapita,
                     title = "Natural capital stock per capita (k USD)"},
                y = {field = :gini_cons,
                     title = "Consumption gini index (2020)"}
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
    )

    return plot
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
