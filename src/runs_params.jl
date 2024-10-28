### RUN AND PLOT SIMULATIONS

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
#Pkg.resolve() # To resolve inconsistencies between Manifest.toml and Project.toml
Pkg.instantiate()
# Load required Julia packages.
using Mimi, MimiFAIRv2, DataFrames, CSVFiles, VegaLite
include("nice2020_module.jl")


function plot_welfare_world(m, values, param)
    param_names = Dict("θ" => :θ, "α" => :α, "η" => :η)
    param_name = param_names[param]
    results = DataFrame()
    first_iteration = true
    model = deepcopy(m)

    for x in values
        set_param!(model, param_name, x)
        run(model)

        if first_iteration
            results = getdataframe(model, :welfare => :welfare_global)
            rename!(results, :welfare_global => Symbol("$param_name = $x"))
            first_iteration = false
        else
            welfare_data = model[:welfare, :welfare_global]
            results[!, Symbol("$param_name = $x")] = welfare_data
        end
    end

    results_long = stack(results, Not(:time), variable_name=param_name, value_name=:welfare_global)

    fig = results_long |> @vlplot(
        :line,
        x=:time,
        y=:welfare_global,
        color=param_name,
        title="Global Welfare Over Time for Different $param_name Values"
    )
    return fig
end



function plot_EDE_world(m, values, param)
    param_names = Dict("θ" => :θ, "α" => :α, "η" => :η)
    param_name = param_names[param]
    results = DataFrame()
    first_iteration = true
    model = deepcopy(m)

    for x in values
        set_param!(model, param_name, x)
        run(model)

        if first_iteration
            results = getdataframe(model, :welfare => :cons_EDE_global)
            rename!(results, :cons_EDE_global => Symbol("$param_name = $x"))
            first_iteration = false
        else
            EDE_data = model[:welfare, :cons_EDE_global]
            results[!, Symbol("$param_name = $x")] = EDE_data
        end
    end

    results_long = stack(results, Not(:time), variable_name=param_name, value_name=:EDE_data)

    fig = results_long |> @vlplot(
        :line,
        x=:time,
        y=:EDE_data,
        color=param_name,
        title="Global consumption EDE Over Time for Different $param_name Values"
    )
    return fig
end


m2 = MimiNICE2020.create_nice2020()
run(m2)

explore(m2)

vector = 0:0.1:1 #values to test


A = plot_welfare_world(m2, vector, "α")
A
explore(m2)


vector2 = 0:0.5:3
B = plot_EDE_world(m2, vector2,"η")

explore(m2)

C = plot_EDE_world(m1, vector, 2)


explore(m1)

m3 = MimiNICE2020.create_nice2020()
update_param!(m3, :α, 1.0)
update_param!(m3, :η, 0.5)

run(m3)

explore(m3)
