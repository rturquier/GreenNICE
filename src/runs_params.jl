### RUN AND PLOT SIMULATIONS

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
#Pkg.resolve() # To resolve inconsistencies between Manifest.toml and Project.toml
Pkg.instantiate()
# Load required Julia packages.
using Mimi, MimiFAIRv2, DataFrames, CSVFiles, VegaLite
include("nice2020_module.jl")

plot_1 = MimiNICE2020.create_nice2020()
run(plot_1)

t = getdataframe(plot_1, :welfare=>:welfare_global)
tt = plot_1[:welfare, :welfare_global]

# Assuming tt is a vector or a DataFrame column, add it as a new column to t
t[!, Symbol("welfare, θ = 0.5")] = tt
t

vector = 0.1:0.1:1.0

function plot_welfare_world(model, values, param)

    # Run the model and store values
    first_iteration = true
    results = DataFrame()


if param == 1

    for x in values
        set_param!(model, :θ, x)
        run(model)

        if first_iteration
            results = getdataframe(model, :welfare=>:welfare_global)
            rename!(results, :welfare_global => Symbol("θ = $x"))
            first_iteration = false
        else
            welfare_data = model[:welfare, :welfare_global]
            results[!, Symbol("θ = $x")] = welfare_data
        end
    end

    results_long = stack(results, Not(:time), variable_name=:θ, value_name=:welfare_global)

    fig = results_long |> @vlplot(
        :line, 
        x=:time, 
        y=:welfare_global, 
        color=:θ,
        title="Global Welfare Over Time for Different θ Values"
    )
    return fig
end #end case θ

if param == 2 
    for x in values
        set_param!(model, :α, x)
        run(model)

        if first_iteration
            results = getdataframe(model, :welfare=>:welfare_global)
            rename!(results, :welfare_global => Symbol("α = $x"))
            first_iteration = false
        else
            welfare_data = model[:welfare, :welfare_global]
            results[!, Symbol("α = $x")] = welfare_data
        end
    end

    results_long = stack(results, Not(:time), variable_name=:α, value_name=:welfare_global)

    fig = results_long |> @vlplot(
        :line, 
        x=:time, 
        y=:welfare_global, 
        color=:α,
        title="Global Welfare Over Time for Different α Values"
    )
    return fig

end #end case α

if param == 3
    for x in values_θ
        set_param!(model, :η, x)
        run(model)

        if first_iteration
            results = getdataframe(model, :welfare=>:welfare_global)
            rename!(results, :welfare_global => Symbol("η = $x"))
            first_iteration = false
        else
            welfare_data = model[:welfare, :welfare_global]
            results[!, Symbol("η = $x")] = welfare_data
        end
    end

    results_long = stack(results, Not(:time), variable_name=:η, value_name=:welfare_global)

    fig = results_long |> @vlplot(
        :line, 
        x=:time, 
        y=:welfare_global, 
        color=:η,
        title="Global Welfare Over Time for Different η Values"
    )
    return fig
end #end case η

end

A = plot_welfare_world(plot_1, vector, 2)







