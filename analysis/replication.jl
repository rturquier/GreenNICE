using Mimi, MimiFAIRv2

include("../src/GreenNICE.jl")
include("functions_analysis.jl")
include("scc.jl")
include("descriptives.jl")

# Get descriptive figures

df_raw = get_descriptives_df()

Initial_E_stock = map_E_percapita_country(df_raw)

E_stock_correlation = plot_E_stock_0_vconcat(df_raw)

Descriptive_plot = plot_descriptive_coeficients(df_raw)

## Save figures
VegaLite.save("outputs/maps/initial_E_stock_percapita.svg", Initial_E_stock)
VegaLite.save("outputs/figures/E_stock0_vconcat.svg", E_stock_correlation)
VegaLite.save("outputs/figures/descriptive_coeficients.svg", Descriptive_plot)
