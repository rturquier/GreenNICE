using Pkg
using DataFrames
using GLM
using RegressionTables

Pkg.activate(joinpath(@__DIR__, ".."))
#Pkg.resolve() # To resolve inconsistencies between Manifest.toml and Project.toml
Pkg.instantiate()

include("../src/GreenNICE.jl")
include("scc.jl")

η = 1.5
θ = 0.5
α = 0.1
γ = 1.0
ρ = 0.001
γ_list = [0.0, 1.0]
pulse_year = 2025
pulse_size = 1.0 # ton CO2

m_descriptives = GreenNICE.create()
run(m_descriptives)

# Replicate Numbers reported in paper

## Section 3: Making NICE Green

### Natural capital

E_stock_2020_pc = @chain getdataframe(m_descriptives, :environment, :E_flow_percapita) begin
    @filter(time == 2020)
    @filter(quantile == "First")
    @mutate(E_stock_percapita = E_flow_percapita / 0.96)
    @select(country, E_stock_percapita)
end

top5_E_stock0_pc = first(sort(E_stock_2020_pc, :E_stock_percapita, rev=true), 5)
bottom5_E_stock0_pc = first(sort(E_stock_2020_pc, :E_stock_percapita, rev=false), 5)

### ξ
ξ_country = getdataframe(m_descriptives, :damages, :ξ)

top_3_ξ = first(sort(ξ_country, :ξ, rev=true), 3)
bottom_3_ξ = first(sort(ξ_country, :ξ, rev=false), 3)

### Gini

gini_cons = @chain getdataframe(m_descriptives, :quantile_recycle, :gini_cons) begin
    @mutate(country = string.(country), gini_cons = float.(gini_cons))
    @filter(time in (2020, 2100))
    @select(country, time, gini_cons)
    unstack(:time, :gini_cons)
    rename!(:("2020") => :gini_cons_2020)
    rename!(:("2100") => :gini_cons_2100)
end


top3_gini = first(sort(gini_cons, :gini_cons_2020, rev=true), 3)
bottom3_gini = first(sort(gini_cons, :gini_cons_2020, rev=false), 3)

top3_gini_2100 = first(sort(gini_cons, :gini_cons_2100, rev=true), 3)
bottom3_gini_2100 = first(sort(gini_cons, :gini_cons_2100, rev=false), 3)

## Section 4: Interaction effect

### Global interaction effect
country_interaction_df = get_SCC_interaction(η, θ, α, γ_list, ρ)

decomposition_BAU = get_SCC_decomposition(η, θ, α, γ, ρ)

SCC_global = decomposition_BAU.present_cost_of_damages_to_c +
             decomposition_BAU.present_cost_of_damages_to_E

SCC_env = decomposition_BAU.present_cost_of_damages_to_E

I_effect = sum(country_interaction_df.interaction)

I_effect_pct = I_effect ./ SCC_env * 100

### Interaction by country

top3_level = first(sort(country_interaction_df, :interaction, rev=true), 3)
bottom3_level = first(sort(country_interaction_df, :interaction, rev=false), 3)

top5_pct = first(sort(country_interaction_df, :interaction_pct, rev=true), 5)
bottom5_pct = first(sort(country_interaction_df, :interaction_pct, rev=false), 5)

### Correlation between ξ, gini and interaction

correlations_df = @chain ξ_country begin
    @mutate(country = string.(country))
    @mutate(θ_env = float.(θ_env))
    leftjoin(country_interaction_df, on=:country)
    leftjoin(gini_cons, on=:country)
    @mutate(interaction = float.(interaction))
end

correlation_gini_2020_2100 = lm(@formula(gini_cons_2020 ~ gini_cons_2100), correlations_df)
regtable(correlation_gini_2020_2100,
        render = LatexTable(),
        file="outputs/tables/correlation_gini_2020_2100.tex")

correlation_ξ_gini_2020 = lm(@formula(interaction ~ θ_env + gini_cons_2020), correlations_df)
regtable(correlation_ξ_gini_2020,
        render = LatexTable(),
        file="outputs/tables/correlation_damage_gini_2020.tex")

correlation_ξ_gini_2100 = lm(@formula(interaction ~ θ_env + gini_cons_2100), correlations_df)
regtable(correlation_ξ_gini,
        render = LatexTable(),
        file="outputs/tables/correlation_damage_gini_2100.tex")


## Make figures showing interaction effect at country and region levels

interaction_effect_map = map_SCC_decomposition_level(country_interaction_df)

VegaLite.save("outputs/maps/interaction_effect_map.svg", interaction_effect_map)
