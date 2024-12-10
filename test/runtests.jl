using Test
using Mimi

@testset "Global tests" begin
    include("../src/GreenNICE.jl")
    using .GreenNICE

    # Test that the model builds
    m = GreenNICE.create()
    @test m isa Model

    # Test that the model runs
    @test run(m) |> isnothing
end

@testset "Welfare tests" begin
    include("../src/components/welfare.jl")
    for η = [0, 0.5, 1, 2], θ = [-1, 0.5, 1], α = [0, 0.5]
        c = 2
        E = 2
        u = utility(c, E, η, θ, α)

        # Test that utility in increasnig in consumption
        @test utility(c + 1, E, η, θ, α) > u

        # Test that inverse_utility is the inverse of utility
        @test inverse_utility(u, E, η, θ, α) ≈ c

        # Test that utility of EDE gives average welfare
        nb_quantile = 4
        c_1 = [1, 2, 3, 4]
        E_1 = [1, 2, 3, 4]
        E_bar = 2.5
        average_welfare_1 = sum(utility.(c_1, E_1, η, θ, α)) / nb_quantile
        equivalent_c_1 = EDE(c_1, E_1, E_bar, η, θ, α, nb_quantile)
        @test utility(equivalent_c_1, E_bar, η, θ, α) ≈ average_welfare_1

        # Test that utility of aggregated EDE gives average welfare
        c_2 = [2, 3, 4, 5]
        E_2 = [5, 4, 3, 2]
        c = [c_1 ; c_2]
        E = [E_1 ; E_2]
        average_welfare_2 = sum(utility.(c_2, E_2, η, θ, α)) / nb_quantile
        equivalent_c_2 = EDE(c_2, E_2, E_bar, η, θ, α, nb_quantile)
        average_welfare = (average_welfare_1 + average_welfare_2) / 2
        aggregated_equivalent_c = EDE_aggregated(
            [equivalent_c_1; equivalent_c_2], E_bar, η, θ, α, [1, 1]
        )
        @test utility(aggregated_equivalent_c, E_bar, η, θ, α) ≈ average_welfare
    end

    # Check that inverse utility throws an error when inverse should be undefined
    @test_throws DomainError inverse_utility(-4, 2, 2, 0.5, 0.5)
    @test_throws DomainError inverse_utility(-0.1, 2, 2, -3.3, 0.5)
    @test_throws DomainError inverse_utility(-2, 2, 0.8, -2, 0.5)
    @test_throws DomainError inverse_utility(8, 2, 0.8, -2.3, 0.5)
end
