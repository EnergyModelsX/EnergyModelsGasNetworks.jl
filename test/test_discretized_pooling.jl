@testitem "DiscretizedPoolingNode - structure" setup = [EMGNSetup] begin
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
    include("discretized_pooling_helpers.jl")

    case, modeltype = generate_case_discretized_pooling(n_points = 5)
    m = create_model(case, modeltype)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)

    𝒩 = get_nodes(case)
    ℒ = get_links(case)
    𝒫 = get_products(case)
    𝒯 = get_time_struct(case)
    H2 = first(filter(p -> p.id == "H2", 𝒫))
    CH4 = first(filter(p -> p.id == "CH4", 𝒫))
    pooling = 𝒩[3]

    @test termination_status(m) == MOI.OPTIMAL
    @test pooling ∈ axes(m[:proportion_out], 1)
    for t ∈ 𝒯
        @test value(m[:proportion_out][pooling, t, H2]) +
              value(m[:proportion_out][pooling, t, CH4]) ≈ 1.0 atol = 1e-4
    end
    @test JuMP.num_nonlinear_constraints(m) == 0
end

@testitem "DiscretizedPoolingNode - flow_component consistency" setup = [EMGNSetup] begin
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
    include("discretized_pooling_helpers.jl")

    case, modeltype = generate_case_discretized_pooling(n_points = 9, capacity = 600.0)
    m = create_model(case, modeltype)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)

    𝒩 = get_nodes(case)
    ℒ = get_links(case)
    𝒫 = get_products(case)
    𝒯 = get_time_struct(case)
    H2 = first(filter(p -> p.id == "H2", 𝒫))
    Gas = first(filter(p -> p.id == "Gas", 𝒫))
    pooling = 𝒩[3]

    @test termination_status(m) == MOI.OPTIMAL
    for l ∈ [ℒ[3], ℒ[4]], t ∈ 𝒯
        prop_H2 = value(m[:proportion_out][pooling, t, H2])
        flow = value(m[:link_in][l, t, Gas])
        fc_H2 = value(m[:flow_component][l, t, H2])
        @test fc_H2 ≈ prop_H2 * flow atol = 0.02 * max(flow, 1.0)
    end
end

@testitem "DiscretizedPoolingNode - DiscretizationData read" setup = [EMGNSetup] begin
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
    include("discretized_pooling_helpers.jl")

    case, modeltype = generate_case_discretized_pooling(n_points = 3)
    m = create_model(case, modeltype)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)
    @test termination_status(m) == MOI.OPTIMAL
end

@testitem "DiscretizedPoolingNode - default n_points" setup = [EMGNSetup] begin
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

    H2 = ResourceCarrier("H2", 1.0)
    CH4 = ResourceCarrier("CH4", 1.0)
    Gas = ResourcePooling("Gas", [H2, CH4])
    CO2 = ResourceEmit("CO2", 1.0)
    T = TwoLevel(1, 1, SimpleTimes(1, 1); op_per_strat = 1)

    pooling = DiscretizedPoolingNode("pooling", FixedProfile(1e6), FixedProfile(0),
        FixedProfile(0), Dict(H2 => 1.0, CH4 => 1.0), Dict(Gas => 1.0))
    nodes = [
        RefSource(
            "src_h2",
            FixedProfile(100),
            FixedProfile(0),
            FixedProfile(0),
            Dict(H2 => 1.0),
        ),
        RefSource(
            "src_ch4",
            FixedProfile(100),
            FixedProfile(0),
            FixedProfile(0),
            Dict(CH4 => 1.0),
        ),
        pooling,
        RefSink("sink1", FixedProfile(100),
            Dict(:surplus => FixedProfile(-50.0), :deficit => FixedProfile(1e4)),
            Dict(Gas => 1.0)),
        RefSink("sink2", FixedProfile(100),
            Dict(:surplus => FixedProfile(-50.0), :deficit => FixedProfile(1e4)),
            Dict(Gas => 1.0)),
    ]
    links = [
        CapDirect("h2_pool", nodes[1], nodes[3], Linear(), FixedProfile(100)),
        CapDirect("ch4_pool", nodes[2], nodes[3], Linear(), FixedProfile(100)),
        CapDirect("pool_sink1", nodes[3], nodes[4], Linear(), FixedProfile(200)),
        CapDirect("pool_sink2", nodes[3], nodes[5], Linear(), FixedProfile(200)),
    ]
    products = [CO2, Gas, H2, CH4]
    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    modeltype = OperationalModel(
        Dict(CO2 => FixedProfile(0.0)),
        Dict(CO2 => FixedProfile(0.0)),
        CO2,
    )
    m = create_model(case, modeltype)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)
    @test termination_status(m) == MOI.OPTIMAL
end

@testitem "DiscretizedPoolingNode - BigM standard K5" setup = [EMGNSetup] begin
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
    include("discretized_pooling_helpers.jl")

    case, modeltype =
        generate_case_discretized_pooling(n_points = 5, capacity = 600.0, method = :bigm)
    m = create_model(case, modeltype)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)

    𝒩 = get_nodes(case)
    ℒ = get_links(case)
    𝒫 = get_products(case)
    𝒯 = get_time_struct(case)
    H2 = first(filter(p -> p.id == "H2", 𝒫))
    CH4 = first(filter(p -> p.id == "CH4", 𝒫))
    Gas = first(filter(p -> p.id == "Gas", 𝒫))
    pooling = 𝒩[3]

    @test termination_status(m) == MOI.OPTIMAL
    for t ∈ 𝒯
        @test value(m[:proportion_out][pooling, t, H2]) +
              value(m[:proportion_out][pooling, t, CH4]) ≈ 1.0 atol = 1e-6
    end
    @test JuMP.num_nonlinear_constraints(m) == 0
    for l ∈ [ℒ[3], ℒ[4]], t ∈ 𝒯
        prop = value(m[:proportion_out][pooling, t, H2])
        flow = value(m[:link_in][l, t, Gas])
        fc = value(m[:flow_component][l, t, H2])
        @test fc ≈ prop * flow atol = 1e-4 * max(flow, 1.0)
    end
end

@testitem "DiscretizedPoolingNode - BigM standard K10" setup = [EMGNSetup] begin
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
    include("discretized_pooling_helpers.jl")

    case, modeltype =
        generate_case_discretized_pooling(n_points = 10, capacity = 600.0, method = :bigm)
    m = create_model(case, modeltype)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)

    𝒩 = get_nodes(case)
    𝒫 = get_products(case)
    𝒯 = get_time_struct(case)
    H2 = first(filter(p -> p.id == "H2", 𝒫))
    CH4 = first(filter(p -> p.id == "CH4", 𝒫))
    pooling = 𝒩[3]

    @test termination_status(m) == MOI.OPTIMAL
    for t ∈ 𝒯
        @test value(m[:proportion_out][pooling, t, H2]) +
              value(m[:proportion_out][pooling, t, CH4]) ≈ 1.0 atol = 1e-6
    end
    @test JuMP.num_nonlinear_constraints(m) == 0
end

@testitem "DiscretizedPoolingNode - BigM log K5" setup = [EMGNSetup] begin
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
    include("discretized_pooling_helpers.jl")

    case, modeltype = generate_case_discretized_pooling(
        n_points = 5,
        capacity = 600.0,
        method = :bigm_log,
    )
    m = create_model(case, modeltype)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)

    𝒩 = get_nodes(case)
    ℒ = get_links(case)
    𝒫 = get_products(case)
    𝒯 = get_time_struct(case)
    H2 = first(filter(p -> p.id == "H2", 𝒫))
    CH4 = first(filter(p -> p.id == "CH4", 𝒫))
    Gas = first(filter(p -> p.id == "Gas", 𝒫))
    pooling = 𝒩[3]

    @test termination_status(m) == MOI.OPTIMAL
    for t ∈ 𝒯
        @test value(m[:proportion_out][pooling, t, H2]) +
              value(m[:proportion_out][pooling, t, CH4]) ≈ 1.0 atol = 1e-6
    end
    @test JuMP.num_nonlinear_constraints(m) == 0
    for l ∈ [ℒ[3], ℒ[4]], t ∈ 𝒯
        prop = value(m[:proportion_out][pooling, t, H2])
        flow = value(m[:link_in][l, t, Gas])
        fc = value(m[:flow_component][l, t, H2])
        @test fc ≈ prop * flow atol = 1e-4 * max(flow, 1.0)
    end
end

@testitem "DiscretizedPoolingNode - BigM log K10" setup = [EMGNSetup] begin
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
    include("discretized_pooling_helpers.jl")

    case, modeltype = generate_case_discretized_pooling(
        n_points = 10,
        capacity = 600.0,
        method = :bigm_log,
    )
    m = create_model(case, modeltype)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)

    𝒩 = get_nodes(case)
    𝒫 = get_products(case)
    𝒯 = get_time_struct(case)
    H2 = first(filter(p -> p.id == "H2", 𝒫))
    CH4 = first(filter(p -> p.id == "CH4", 𝒫))
    pooling = 𝒩[3]

    @test termination_status(m) == MOI.OPTIMAL
    for t ∈ 𝒯
        @test value(m[:proportion_out][pooling, t, H2]) +
              value(m[:proportion_out][pooling, t, CH4]) ≈ 1.0 atol = 1e-6
    end
    @test JuMP.num_nonlinear_constraints(m) == 0
end

@testitem "DiscretizedPoolingNode - DiscretizationData method accessor" setup = [EMGNSetup] begin
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

    d_pwl = DiscretizationData(5)
    d_bigm = DiscretizationData(5, :bigm)
    d_bigmlog = DiscretizationData(10, :bigm_log)

    @test get_n_points(d_pwl) == 5
    @test get_method(d_pwl) == :pwl
    @test get_method(d_bigm) == :bigm
    @test get_method(d_bigmlog) == :bigm_log
    @test get_n_points(d_bigmlog) == 10
    @test_throws ArgumentError DiscretizationData(5, :invalid)
    @test_throws ArgumentError DiscretizationData(1)
end

@testitem "DiscretizedPoolingNode - tracked resource reversed order" setup = [EMGNSetup] begin
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
    include("discretized_pooling_helpers.jl")

    for method ∈ (:pwl, :bigm, :bigm_log)
        case, model, pooling, H2, CH4 =
            generate_reversed_discretized_case(; method, tracked = :explicit)
        m = create_model(case, model)
        set_optimizer(m, EMGNSetup.mip_optimizer())
        optimize!(m)
        t = first(get_time_struct(case))
        @test termination_status(m) == MOI.OPTIMAL
        @test value(m[:proportion_out][pooling, t, H2]) ≈ 0.2 atol = 1e-6
        @test value(m[:proportion_out][pooling, t, CH4]) ≈ 0.8 atol = 1e-6
    end

    case, model, pooling, H2, CH4 =
        generate_reversed_discretized_case(; method = :bigm, tracked = :legacy)
    m = create_model(case, model)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)
    t = first(get_time_struct(case))
    @test termination_status(m) == MOI.OPTIMAL
    @test value(m[:proportion_out][pooling, t, H2]) ≈ 0.2 atol = 1e-6
    @test value(m[:proportion_out][pooling, t, CH4]) ≈ 0.8 atol = 1e-6

    invalid_case, invalid_model, _, _, _ =
        generate_reversed_discretized_case(; tracked = :invalid)
    @test_throws ArgumentError create_model(invalid_case, invalid_model)

    ambiguous_case, ambiguous_model, _, _, _ =
        generate_reversed_discretized_case(; tracked = :ambiguous)
    @test_throws ArgumentError create_model(ambiguous_case, ambiguous_model)
end
