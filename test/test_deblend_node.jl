@testitem "DeblendNode - perfect efficiency" setup = [EMGNSetup] begin
    using .EMGNSetup
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using EnergyModelsInvestments
    using HiGHS
    using JuMP
    using MathOptInterface
    using PiecewiseAffineApprox
    using SCIP
    using Test
    using TimeStruct
    const EMB = EnergyModelsBase
    const EMGN = EnergyModelsGasNetworks
    const MOI = MathOptInterface
    include("deblend_helpers.jl")

    case, model, nodes, links =
        make_deblend_case(psa_efficiency = 1.0, max_extract_fraction = 1.0)
    m = create_model(case, model)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)

    𝒯 = get_time_struct(case)
    t = first(collect(𝒯))
    deblend = nodes[4]
    l_blend = links[4]
    H2 = first(filter(p -> p.id == "H2", get_products(case)))
    Blend = first(filter(p -> p.id == "Blend", get_products(case)))

    @test JuMP.termination_status(m) ∈ [MOI.OPTIMAL, MOI.ALMOST_OPTIMAL]
    @test value(m[:flow_out][deblend, t, H2]) ≈ 10.0 atol = 1e-4
    @test value(m[:cap_use][deblend, t]) ≈ 10.0 atol = 1e-4
    blend_in = value(m[:flow_in][deblend, t, Blend])
    blend_out = value(m[:link_in][l_blend, t, Blend])
    h2_out = value(m[:flow_out][deblend, t, H2])
    @test blend_in ≈ blend_out + h2_out / 1.0 atol = 1e-4
    @test value(m[:flow_component][l_blend, t, H2]) ≈ 0.0 atol = 1e-4
    @test blend_out ≈ 90.0 atol = 1e-4
end

@testitem "DeblendNode - PSA efficiency" setup = [EMGNSetup] begin
    using .EMGNSetup
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using EnergyModelsInvestments
    using HiGHS
    using JuMP
    using MathOptInterface
    using PiecewiseAffineApprox
    using SCIP
    using Test
    using TimeStruct
    const EMB = EnergyModelsBase
    const EMGN = EnergyModelsGasNetworks
    const MOI = MathOptInterface
    include("deblend_helpers.jl")

    case, model, nodes, links =
        make_deblend_case(psa_efficiency = 0.9, max_extract_fraction = 1.0)
    m = create_model(case, model)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)

    𝒯 = get_time_struct(case)
    t = first(collect(𝒯))
    deblend = nodes[4]
    l_blend = links[4]
    H2 = first(filter(p -> p.id == "H2", get_products(case)))
    Blend = first(filter(p -> p.id == "Blend", get_products(case)))
    η = 0.9

    @test JuMP.termination_status(m) ∈ [MOI.OPTIMAL, MOI.ALMOST_OPTIMAL]
    @test value(m[:flow_out][deblend, t, H2]) ≈ η * 10.0 atol = 1e-4
    @test value(m[:cap_use][deblend, t]) ≈ 10.0 atol = 1e-4
    blend_in = value(m[:flow_in][deblend, t, Blend])
    blend_out = value(m[:link_in][l_blend, t, Blend])
    h2_out = value(m[:flow_out][deblend, t, H2])
    @test blend_in ≈ blend_out + h2_out / η atol = 1e-4
    @test value(m[:flow_component][l_blend, t, H2]) ≈ 0.0 atol = 1e-4
    @test blend_out ≈ 90.0 atol = 1e-4
end

@testitem "DeblendNode - extraction fraction limit" setup = [EMGNSetup] begin
    using .EMGNSetup
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using EnergyModelsInvestments
    using HiGHS
    using JuMP
    using MathOptInterface
    using PiecewiseAffineApprox
    using SCIP
    using Test
    using TimeStruct
    const EMB = EnergyModelsBase
    const EMGN = EnergyModelsGasNetworks
    const MOI = MathOptInterface
    include("deblend_helpers.jl")

    case, model, nodes, links =
        make_deblend_case(psa_efficiency = 1.0, max_extract_fraction = 0.5)
    m = create_model(case, model)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)

    𝒯 = get_time_struct(case)
    t = first(collect(𝒯))
    deblend = nodes[4]
    l_blend = links[4]
    H2 = first(filter(p -> p.id == "H2", get_products(case)))
    Blend = first(filter(p -> p.id == "Blend", get_products(case)))
    α = 0.5

    @test JuMP.termination_status(m) ∈ [MOI.OPTIMAL, MOI.ALMOST_OPTIMAL]
    @test value(m[:flow_out][deblend, t, H2]) ≈ α * 10.0 atol = 1e-4
    @test value(m[:cap_use][deblend, t]) ≈ α * 10.0 atol = 1e-4
    @test value(m[:flow_component][l_blend, t, H2]) ≈ (1 - α) * 10.0 atol = 1e-4
    @test value(m[:link_in][l_blend, t, Blend]) ≈ 10.0 + 90.0 - α * 10.0 atol = 1e-4
end

@testitem "DeblendNode - combined efficiency and fraction" setup = [EMGNSetup] begin
    using .EMGNSetup
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using EnergyModelsInvestments
    using HiGHS
    using JuMP
    using MathOptInterface
    using PiecewiseAffineApprox
    using SCIP
    using Test
    using TimeStruct
    const EMB = EnergyModelsBase
    const EMGN = EnergyModelsGasNetworks
    const MOI = MathOptInterface
    include("deblend_helpers.jl")

    case, model, nodes, links =
        make_deblend_case(psa_efficiency = 0.9, max_extract_fraction = 0.5)
    m = create_model(case, model)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)

    𝒯 = get_time_struct(case)
    t = first(collect(𝒯))
    deblend = nodes[4]
    l_blend = links[4]
    H2 = first(filter(p -> p.id == "H2", get_products(case)))
    Blend = first(filter(p -> p.id == "Blend", get_products(case)))
    η = 0.9
    α = 0.5

    @test JuMP.termination_status(m) ∈ [MOI.OPTIMAL, MOI.ALMOST_OPTIMAL]
    @test value(m[:flow_out][deblend, t, H2]) ≈ η * α * 10.0 atol = 1e-4
    @test value(m[:cap_use][deblend, t]) ≈ α * 10.0 atol = 1e-4
    @test value(m[:flow_component][l_blend, t, H2]) ≈ (1 - α) * 10.0 atol = 1e-4
    blend_in = value(m[:flow_in][deblend, t, Blend])
    blend_out = value(m[:link_in][l_blend, t, Blend])
    h2_out = value(m[:flow_out][deblend, t, H2])
    @test blend_in ≈ blend_out + h2_out / η atol = 1e-4
end
