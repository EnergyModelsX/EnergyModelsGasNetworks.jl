@testitem "Direct link - blend with pressure" setup = [EMGNSetup] begin
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

    function generate_case_direct(; max_h2 = 0.05, min_h2 = 0.0)
        H2 = ResourcePressure("H2", 1.0)
        CH4 = ResourcePressure("CH4", 1.0)
        Blend = ResourcePooling("Blend", [H2, CH4])
        CO2 = ResourceEmit("CO2", 1.0)
        products = [CO2, Blend, H2, CH4]
        T = TwoLevel(1, 1, TimeStruct.SimpleTimes(1, 1); op_per_strat = 1)

        nodes = [
            RefSource(1, FixedProfile(500), FixedProfile(10), FixedProfile(0),
                Dict(H2 => 1), [MaxPressureData(FixedProfile(180))]),
            RefSource(2, FixedProfile(500), FixedProfile(10), FixedProfile(0),
                Dict(CH4 => 1), [MaxPressureData(FixedProfile(180))]),
            PoolingNode(3, FixedProfile(1e6), FixedProfile(0), FixedProfile(0),
                Dict(CH4 => 1, H2 => 1), Dict(Blend => 1),
                [MaxPressureData(FixedProfile(180))]),
            RefSink(4, FixedProfile(0),
                Dict(:surplus => FixedProfile(-120), :deficit => FixedProfile(1e6)),
                Dict(Blend => 1),
                [
                    RefBlendData{ResourcePressure{Float64}}(Blend,
                        Dict(H2 => max_h2, CH4 => 1.0), Dict(H2 => min_h2, CH4 => 0.0)),
                    MinPressureData(FixedProfile(130))]),
            RefSink(5, FixedProfile(0),
                Dict(:surplus => FixedProfile(-120), :deficit => FixedProfile(1e6)),
                Dict(Blend => 1),
                [
                    RefBlendData{ResourcePressure{Float64}}(Blend,
                        Dict(H2 => max_h2, CH4 => 1.0), Dict(H2 => min_h2, CH4 => 0.0)),
                    MinPressureData(FixedProfile(100))]),
        ]

        links = [
            Direct(14, nodes[1], nodes[3], Linear()),
            Direct(24, nodes[2], nodes[3], Linear()),
            CapDirect(34, nodes[3], nodes[4], Linear(), FixedProfile(200),
                [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6)),
                    BlendLinkData{ResourcePressure{Float64}}(Blend,
                        Dict(H2 => 2.02), Dict(H2 => 0.0), 0.2, 0.0, Dict(CH4 => 16.04),
                    )]),
            CapDirect(35, nodes[3], nodes[5], Linear(), FixedProfile(200),
                [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6)),
                    BlendLinkData{ResourcePressure{Float64}}(Blend,
                        Dict(H2 => 2.02), Dict(H2 => 0.0), 0.2, 0.0, Dict(CH4 => 16.04),
                    )]),
        ]

        case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
        model = OperationalModel(Dict(CO2 => FixedProfile(0)),
            Dict(CO2 => FixedProfile(0)), CO2)
        EMGNSetup.setup_pwa!()
        m = create_model(case, model; check_timeprofiles = true)
        set_optimizer(m, EMGNSetup.scip_optimizer())
        optimize!(m)
        return case, model, m
    end

    case, model, m = generate_case_direct(; max_h2 = 1.0, min_h2 = 0.00)
    𝒩 = get_nodes(case)
    ℒ = get_links(case)
    𝒫 = get_products(case)
    𝒯 = get_time_struct(case)
    H2 = first(filter(p -> p.id == "H2", 𝒫))
    CH4 = first(filter(p -> p.id == "CH4", 𝒫))
    Blend = first(filter(p -> p.id == "Blend", 𝒫))

    @testset "Results" begin
        @test JuMP.termination_status(m) in [MOI.OPTIMAL, MOI.OTHER_LIMIT]
        @test value(m[:link_in][ℒ[1], first(collect(𝒯)), H2]) ≈ 201.6 atol = 20
        @test value(m[:link_in][ℒ[3], first(collect(𝒯)), Blend]) ≈ 90.6 atol = 20
        @test value(m[:link_in][ℒ[4], first(collect(𝒯)), Blend]) ≈ 111.011 atol = 20
        @test value(m[:link_potential_in][ℒ[1], first(collect(𝒯)), H2]) ≈ 180.0 rtol = 0.02
        @test value(m[:link_potential_out][ℒ[1], first(collect(𝒯)), H2]) ≈ 180.0 rtol = 0.02
        @test value(m[:link_potential_in][ℒ[3], first(collect(𝒯)), Blend]) ≈ 180.0 rtol =
            0.02
        @test value(m[:link_potential_out][ℒ[3], first(collect(𝒯)), Blend]) ≈ 130.0 rtol =
            0.02
        @test value(m[:link_potential_in][ℒ[4], first(collect(𝒯)), Blend]) ≈ 180.0 rtol =
            0.02
        @test value(m[:link_potential_out][ℒ[4], first(collect(𝒯)), Blend]) ≈ 100.0 rtol =
            0.02
    end
end
