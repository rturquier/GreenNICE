### Results Analysis

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
#Pkg.resolve() # To resolve inconsistencies between Manifest.toml and Project.toml
Pkg.instantiate()
using Mimi, MimiFAIRv2, DataFrames, CSVFiles, Statistics, VegaLite, TidierData

include("../src/GreenNICE.jl")

base_model = GreenNICE.create()

run(base_model)

# EDE by decile. Deciles constant.
EDE_decile = EDE_globaldecile_constant(base_model)


Table_decileEDE = EDE_weightedavg_decile(EDE_decile)
EDE_10_40 = get_10_40(EDE_decile)
EDE_depalmaRatio = get_env_depalma_ratio(EDE_decile)

# EDE by decile. Deciles evolve over time.
EDE_decile_var = EDE_globaldecile_evolution(base_model)

Table_decileEDE_variable = EDE_weightedavg_decile(EDE_decile_var)
EDE_10_40_variable = get_10_40(EDE_decile_var)
EDE_depalmaRatio_var = get_env_depalma_ratio(EDE_decile_var)



#PLOTS

plot = @vlplot(
    :line,
    x = {field=:time, axis={labelAngle=-90}},
    y = :EDE_w_mean,
    color = {field=:global_decile, type="nominal"},
    data = Table_decileEDE,
    width=800,
    height=600
    )

display(plot)

plot_TT = @vlplot(
    :line,
    x = {field=:time, axis={labelAngle=-90}},
    y = {field=:EDE, type="quantitative"},
    color = {field=:global_decile, type="nominal"},
    data = TT,
    width=800,
    height=600
)

display(plot_TT)

plot_10_40 = @vlplot() + @vlplot(
    :line,
    x = {field=:time, axis={labelAngle=-90}},
    y = {field="top 10%", type="quantitative"},
    color = {value="blue"},
    data = EDE_10_40,
    width=800,
    height=600
) + @vlplot(
    :line,
    x = {field=:time, axis={labelAngle=-90}},
    y = {field="bottom 40%", type="quantitative"},
    color = {value="red"},
    data = EDE_10_40,
    width=800,
    height=600
)

display(plot_10_40)

plot_depalma = @vlplot(
    :line,
    x = {field=:time, axis={labelAngle=-90}},
    y = {field=:ratio, type="quantitative"},
    color = {value="green"},
    data = EDE_depalmaRatio,
    width=800,
    height=600
)

display(plot_depalma)


# FUNCTIONS

function quantile_to_int(dataframe)
    dataframe.quantile .= replace(dataframe.quantile,
        "First" => 1, "Second" => 2, "Third" => 3, "Fourth" => 4,
        "Fifth" => 5, "Sixth" => 6, "Seventh" => 7, "Eighth" => 8,
        "Ninth" => 9, "Tenth" => 10)
    return dataframe
end

function make_decile(pop, nb_quantile)
    pop = pop[repeat(1:nrow(pop), inner=nb_quantile), :]
    pop.quantile = repeat(1:nb_quantile, outer=nrow(pop) ÷ nb_quantile)
    pop.l = pop.l / nb_quantile
    return pop
end

function set_globaldecile(EDE_decilecountry, population, year)

    df = deepcopy(EDE_decilecountry)
    df = filter(row -> row.time == year, df)
    population_T = filter(row -> row.time == year, population)
    total_population_T = sum(population_T.l)

    df.population = [population_T.l[(population_T.country .== row.country) .&
        (population_T.quantile .== row.quantile)][1] for row in eachrow(df)]

    sort!(df, 3)

    df.cumulative_population = cumsum(df[:, 5])
    df.global_decile = 10 .*
        ceil.(df.cumulative_population ./ total_population_T, digits = 1)

    return df
end

function set_population_decile(EDE_decilecountry, population)

    EDE_globaldecile = deepcopy(EDE_decilecountry)
    EDE_globaldecile.key = string.(EDE_globaldecile.country,"_",EDE_globaldecile.quantile,"_",EDE_globaldecile.time)

    population.key = string.(population.country,"_",population.quantile,"_",population.time)
    EDE_globaldecile = leftjoin(EDE_globaldecile, population[:, ["key", "l"]], on = :key)
    select!(EDE_globaldecile, Not(:key))

    return EDE_globaldecile
end

function EDE_globaldecile_constant(model)

    EDE_decilecountry = getdataframe(model, :welfare, :cons_EDE_decilecountry)
    EDE_decilecountry = quantile_to_int(EDE_decilecountry)

    nb_quantile = model[:welfare, :nb_quantile]

    population = getdataframe(model, :welfare, :l)
    population = make_decile(population, nb_quantile)

    EDE_globaldecile = set_population_decile(EDE_decilecountry, population)

    df = set_globaldecile(EDE_decilecountry, population, 2020)
    df.key2 = string.(df.country, "_", df.quantile)

    EDE_globaldecile.key2 = string.(EDE_globaldecile.country, "_", EDE_globaldecile.quantile)
    EDE_globaldecile = leftjoin(EDE_globaldecile, df[:, ["key2", "global_decile"]], on = :key2)
    select!(EDE_globaldecile, Not(:key2))

    return EDE_globaldecile

end

function EDE_globaldecile_evolution(model)

    EDE_decilecountry = getdataframe(model, :welfare, :cons_EDE_decilecountry)
    EDE_decilecountry = quantile_to_int(EDE_decilecountry)

    nb_quantile = model[:welfare, :nb_quantile]

    population = getdataframe(model, :welfare, :l)
    population = make_decile(population, nb_quantile)
    EDE_globaldecile = set_population_decile(EDE_decilecountry, population)
    EDE_globaldecile = variable_decile(EDE_globaldecile)

    return EDE_globaldecile

end

function EDE_weightedavg_decile(EDE_decile)
    weighted_avg = combine(groupby(EDE_decile, [:time, :global_decile]),
    [:cons_EDE_decilecountry, :l] => ((x, y) -> sum(x .*y) / sum(y)) => :EDE_w_mean)

    return weighted_avg
end

function set_depalmadecile(EDE_decile)
    EDE_globaldecile = deepcopy(EDE_decile)
    EDE_globaldecile = filter(row -> !(row.global_decile > 4 && row.global_decile < 10), EDE_globaldecile)
    replace!(EDE_globaldecile.global_decile,
        1=> 40,
        2=> 40,
        3=> 40,
        4=> 40,
        10=> 10)
    return EDE_globaldecile
end

function get_10_40(EDE_decile)
    EDE_depalma= set_depalmadecile(EDE_decile)
    EDE_ratio = EDE_weightedavg_decile(EDE_depalma)
    EDE_ratio = unstack(EDE_ratio, :global_decile, :EDE_w_mean)
    rename!(EDE_ratio, "10.0" => "top 10%", "40.0" => "bottom 40%")
    return EDE_ratio
end



function get_env_depalma_ratio(EDE_decile)
    EDE_depalma= set_depalmadecile(EDE_decile)
    EDE_ratio = EDE_weightedavg_decile(EDE_depalma)
    EDE_ratio = unstack(EDE_ratio, :global_decile, :EDE_w_mean)
    EDE_ratio.ratio = EDE_ratio[!, "10.0"] ./ EDE_ratio[!, "40.0"]
    return EDE_ratio[:, [:time, :ratio]]
end




function variable_decile(EDE_globaldecile)
    EDE_evo = @chain EDE_globaldecile begin
        @group_by(time)
        @arrange(cons_EDE_decilecountry)
        @mutate(cummulative_pop = cumsum(l))
        @mutate(global_decile =  min(ceil(10 * cummulative_pop / sum(l)), 10))
        @ungroup()
       # @group_by(time, global_decile)
       # @summarize(EDE = sum(l .* cons_EDE_decilecountry) / sum(l))
       # @ungroup()
    end
    return EDE_evo
end
