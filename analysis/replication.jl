using Mimi, MimiFAIRv2

include("../src/GreenNICE.jl")
include("functions_analysis.jl")
include("scc.jl")
include("descriptives.jl")

# Get descriptive figures

df_raw = get_descriptives_df()

Initial_E_stock = map_E_percapita_country(df_raw)

Gini_E_stock0 = plot_gini_E_stock0(df_raw)

Descriptive_plot = plot_descriptive_coefficients(df_raw)



## Save figures
VegaLite.save("outputs/maps/initial_E_stock_percapita.svg", Initial_E_stock)
VegaLite.save("outputs/figures/gini_E_stock0.svg", Gini_E_stock0)
VegaLite.save("outputs/figures/descriptive_coefficients.svg", Descriptive_plot)
