#########################################################
# Get changes in environment
#########################################################

# Activate the project and make sure all packages we need
# are installed.
using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
#Pkg.resolve() # To resolve inconsistencies between Manifest.toml and Project.toml
Pkg.instantiate()

# Load required Julia packages.
using Mimi, MimiFAIRv2, DataFrames, CSVFiles, Plots

println("Load NICE2020 source code.")
# Load NICE2020 source code.
include("../src/GreenNICE.jl")

include("functions_analysis.jl")
m = GreenNICE.create()

## Set E and parameters
update_param!(m, :environment, :dam_assessment, 1)

run(m)

Damages_2030 = get_env_damages_year(m, 2200)

AAA = plot_env_damages!(Damages_2030,
                        "Percent change in non-market natural capital by 2200",
                        "Percentage_loss_env")

Damages_1c = get_env_damage_temp(m, 1)

BBB = plot_env_damages!(Damages_1c,
                        "Percentage changes in non-market natural capital with a 1C increase",
                        "Percentage_loss_1c")



alpha_params = [0.1, 0.2, 0.3]
array_params = [4, 3, 1]

Damages_plot = Env_damages_EDE_trajectories(m, array_params, alpha_params)


function plot_EDE_trajectories(test_array, array_params, alpha_params, end_year)
    p = plot()

    # Create a mapping for alpha values to line styles
    linestyle_map = Dict(0.1 => :solid, 0.2 => :dash, 0.3 => :dashdotdot)

    for (j, alpha) in enumerate(alpha_params)
        for (i, param) in enumerate(array_params)
            linestyle = linestyle_map[alpha]
            color = [:blue, :green, :red, :purple][param % 4 + 1]

            plot!(p,
                test_array[j][i],
                label="",
                linestyle=linestyle,
                color=color)
        end
    end

    # Create labels by plotting invisible lines
    plot!(p, rand(1), color= :blue, label = "Equal E, equal damages")
    plot!(p, rand(1), color= :green, label = "Different E, different damages")
    plot!(p, rand(1), color= :red, label = "Same E, different damages")
    plot!(p, rand(1), color= :purple, label = "Different E, equal damages")
    plot!([1], [0], linestyle = :solid, label = "α = 0.1", color = "black")
    plot!([1], [0], linestyle = :dash, label = "α = 0.2", color = "black")
    plot!([1], [0], linestyle = :dashdotdot, label = "α = 0.3", color = "black")

    # Labels and title
    xlabel!("Year")
    ylabel!("EDE Global Consumption")
    title!("EDE Trajectories for Different Parameters")

    # Move legend to the right down corner
    plot!(p, legend=:bottomright)

    # Display the plot
    display(p)
    # Save the plot as SVG
    savefig(p, "test/figures/EDE_Trajectories.svg")
end

plot_EDE_trajectories(Damages_plot, array_params, alpha_params, 2200)
