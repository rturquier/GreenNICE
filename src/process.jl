### Results Analysis

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
#Pkg.resolve() # To resolve inconsistencies between Manifest.toml and Project.toml
Pkg.instantiate()
using Mimi, MimiFAIRv2, DataFrames, CSVFiles, Statistics, VegaLite

include("../src/GreenNICE.jl")

base_model = GreenNICE.create()

run(base_model)

getdataframe(base_model, :welfare, :cons_EDE_decilecountry)

getdataframe(base_model, :welfare, :l)

EDE_decile = EDE_globaldecile(base_model)

Table_decileEDE = combine(groupby(EDE_decile, [:year, :global_decile]),
            [:EDE, :population] => ((x, y) -> sum(x .*y) / sum(y)) => :EDE_w_mean)

plot = @vlplot(
    :line,
    x = :year,
    y = :EDE_w_mean,
    color = {field=:global_decile, type="nominal"},
    data = Table_decileEDE
    )

display(plot)



function EDE_globaldecile(model)
    EDE_decilecountry = model[:welfare, :cons_EDE_decilecountry]
    t0 = 1
    l = base_model[:welfare, :l]
    nb_quantile = model[:welfare, :nb_quantile]

    total_population_0 = sum(l[t0, :])

    df = DataFrame(Country = Int64[], Decile = Int64[], EDE_init = Float64[],
        Pop = Float64[])

    for c in 1:size(EDE_decilecountry, 2)
        for d in 1:size(EDE_decilecountry, 3)
            push!(df, (c, d, EDE_decilecountry[t0, c, d], (l[t0,c] / nb_quantile) ))
        end
    end

    sort!(df, 3)

    df.key = string.(df.Country, "_", df.Decile)
    df.cumulative_population = cumsum(df[:, 4])
    df.global_decile = 10 .* ceil.(df.cumulative_population ./ total_population_0, digits = 1)

    EDE_globaldecile = DataFrame(year = Int64[], Country = Int64[], Decile = Int64[],
        population = Float64[],  EDE = Float64[])

    for t in 1:size(EDE_decilecountry,1)
        for c in 1:size(EDE_decilecountry, 2)
            for d in 1:size(EDE_decilecountry, 3)
                push!(EDE_globaldecile, (t, c, d, (l[t,c] / nb_quantile),
                    EDE_decilecountry[t, c, d]))
            end
        end
    end

    EDE_globaldecile.key = string.(EDE_globaldecile.Country, "_", EDE_globaldecile.Decile)
    EDE_globaldecile = leftjoin(EDE_globaldecile, df[:, ["key", "global_decile"]], on = :key)

    return EDE_globaldecile

end
