using Mimi
using TidierData
using TidierFiles
using VegaLite

include("../src/GreenNICE.jl")
using .GreenNICE

function get_descriptives_df()::DataFrame

    m = GreenNICE.create()
    run(m)

    E_stock0_percapita = @chain getdataframe(m, :environment, :E_flow_percapita) begin
        @filter(time == 2020)
        @filter(quantile == "First")
        @mutate(E_stock0_percapita = E_flow_percapita / 0.96)
        @select(country, E_stock0_percapita)
    end


    df = @chain getdataframe(m, :quantile_recycle, :gini_cons) begin
        @filter(time == 2020)
        leftjoin(E_stock0_percapita, on = :country)
        @mutate(E_stock0_percapita = Float64.(E_stock0_percapita))
        @mutate(gini_cons = Float64.(gini_cons))
    end

    return df
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
