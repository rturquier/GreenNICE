using Test
using Mimi

@testset "Global tests" begin
    include("../src/GreenNICE.jl")
    using .GreenNICE

    # Test that the model builds
    m = GreenNICE.create(; parameters=Dict(:E_multiplier => 2))
    @test m isa Model

    # Test that the model runs
    @test run(m) |> isnothing
end

@testset "Welfare tests" begin
    include("../src/components/welfare.jl")
    for η = [0, 0.5, 1, 2], θ = [-1, 0, 0.5, 1], α = [0, 0.5]
        c = 2
        E = 2
        u = utility(c, E, η, θ, α)

        # Test that utility is increasing in consumption
        @test utility(c + 1, E, η, θ, α) > u
    end
end

@testset "Quantile tests" begin
    using Random, Statistics
    include("../src/components/quantile_recycle.jl")

    n_quantiles = 10
    quantiles = rand(1:1000, n_quantiles) |> sort

    @test adjust_inequality(quantiles, 1) ≈ quantiles
    @test adjust_inequality(quantiles, 0) ≈ mean(quantiles) * ones(n_quantiles)

    @test rescale_distribution(quantiles, 1) == quantiles / sum(quantiles)
    @test rescale_distribution(quantiles, 0) == ones(n_quantiles) / n_quantiles
end
