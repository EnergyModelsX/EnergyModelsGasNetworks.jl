@testitem "Blending pressure - zero H2 case" setup = [EMGNSetup] begin
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

    function test_approx(weymouth, pressure_points, link_potential_in, link_potential_out)
        rhs = Float64[]
        for (p_in, p_out) ∈ pressure_points
            value =
                sqrt(weymouth) * (
                    (p_in / (sqrt(p_in^2 - p_out^2))) * link_potential_in -
                    (p_out / (sqrt(p_in^2 - p_out^2))) * link_potential_out
                )
            push!(rhs, value)
        end
        return minimum(rhs)
    end

    # Exact Weymouth flow on the blend pipe ℒ[4] at the solved pressures, using the same
    # inputs as `get_pwa`. Results depend on the (random) PWA fit, so flows are checked
    # against physics and balances instead of fixed values.
    function exact_blend_flow(m, l, t, Blend, H2, prop)
        bd = first(filter(d -> d isa BlendLinkData, l.data))
        W = round(
            EMGN.normalised_weymouth(bd, 0.24, bd.track_molar_fraction[H2]),
            digits = 4,
        )
        pin = value(m[:link_potential_in][l, t, Blend])
        pout = value(m[:link_potential_out][l, t, Blend])
        return EMGN.calculate_flow_to_approximate(W, pin, pout, prop, 16.04, 2.016)
    end

    function generate_case_blending_pressure(;
        max_h2 = 0.05, min_h2 = 0.0, cost_s3 = 5, cost_h2 = 10)
        H2 = ResourcePressure("H2", 1.0)
        CH4 = ResourcePressure("CH4", 1.0)
        Blend = ResourcePooling("Blend", [H2, CH4])
        CO2 = ResourceEmit("CO2", 1.0)
        Power = ResourceCarrier("Power", 1.0)
        products = [CO2, Blend, H2, CH4, Power]

        op_duration = 1
        op_number = 1
        operational_periods = TimeStruct.SimpleTimes(op_number, op_duration)
        op_per_strat = op_duration * op_number
        T = TwoLevel(1, 1, operational_periods; op_per_strat)

        nodes = [
            RefSource("supply_h2", FixedProfile(2000), FixedProfile(cost_h2),
                FixedProfile(0), Dict(H2 => 1), [MaxPressureData(FixedProfile(0))]),
            RefSource("supply_ch4_1", FixedProfile(5000), FixedProfile(10),
                FixedProfile(0), Dict(CH4 => 1), [MaxPressureData(FixedProfile(0))]),
            RefSource("supply_ch4_2", FixedProfile(2000), FixedProfile(cost_s3),
                FixedProfile(0), Dict(CH4 => 1), [MaxPressureData(FixedProfile(0))]),
            PoolingNode("pooling_node", FixedProfile(1e6), FixedProfile(0),
                FixedProfile(0),
                Dict(CH4 => 1, H2 => 1), Dict(Blend => 1),
                [MaxPressureData(FixedProfile(180))]),
            RefSink("sink", FixedProfile(0),
                Dict(:surplus => FixedProfile(-120), :deficit => FixedProfile(1e6)),
                Dict(Blend => 1),
                [
                    RefBlendData{ResourcePressure{Float64}}(Blend,
                        Dict(H2 => max_h2, CH4 => 1.0), Dict(H2 => min_h2, CH4 => 0.0)),
                    MinPressureData(FixedProfile(130))]),
            RefSource("supply_power", FixedProfile(1000), FixedProfile(0.5),
                FixedProfile(0), Dict(Power => 1)),
            SimpleCompressor("compressor_1", FixedProfile(1e6), FixedProfile(0),
                FixedProfile(0), Dict(H2 => 1, Power => 1.2), Dict(H2 => 1),
                FixedProfile(180), [MaxPressureData(FixedProfile(180))]),
            SimpleCompressor("compressor_2", FixedProfile(1e6), FixedProfile(0),
                FixedProfile(0), Dict(CH4 => 1, Power => 1.2), Dict(CH4 => 1),
                FixedProfile(180), [MaxPressureData(FixedProfile(180))]),
            SimpleCompressor("compressor_3", FixedProfile(1e6), FixedProfile(0),
                FixedProfile(0), Dict(CH4 => 1, Power => 1.2), Dict(CH4 => 1),
                FixedProfile(180), [MaxPressureData(FixedProfile(180))]),
        ]

        links = [
            CapDirect("", nodes[7], nodes[4], Linear(), FixedProfile(200),
                [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6))],
            ),
            CapDirect(24, nodes[8], nodes[4], Linear(), FixedProfile(200),
                [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6))],
            ),
            CapDirect(34, nodes[9], nodes[4], Linear(), FixedProfile(200),
                [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6))],
            ),
            CapDirect(45, nodes[4], nodes[5], Linear(), FixedProfile(1200),
                [PressureLinkData(0.24, 180, 130), MinPressureData(FixedProfile(130)),
                    BlendLinkData(Blend,
                        Dict{ResourcePressure{Float64},Float64}(H2 => 2.016),
                        0.1, 0.0,
                        Dict{ResourcePressure{Float64},Float64}(CH4 => 16.04))]),
            Direct("source_compressor_1", nodes[1], nodes[7], Linear()),
            Direct("source_compressor_2", nodes[2], nodes[8], Linear()),
            Direct("source_compressor_3", nodes[3], nodes[9], Linear()),
            Direct("power_compressor_1", nodes[6], nodes[7], Linear()),
            Direct("power_compressor_2", nodes[6], nodes[8], Linear()),
            Direct("power_compressor_3", nodes[6], nodes[9], Linear()),
        ]

        case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
        model = OperationalModel(Dict(CO2 => FixedProfile(0)),
            Dict(CO2 => FixedProfile(0)), CO2)

        EMGNSetup.setup_pwa!(; step = 10)   # checks the PWA accuracy
        m = create_model(case, model; check_timeprofiles = true)
        set_optimizer(m, EMGNSetup.scip_optimizer())
        optimize!(m)
        return case, model, m
    end

    case, model, m = generate_case_blending_pressure(; max_h2 = 0.0, min_h2 = 0.00)

    𝒩 = get_nodes(case)
    ℒ = get_links(case)
    𝒫 = get_products(case)
    𝒯 = get_time_struct(case)

    H2 = first(filter(p -> p.id == "H2", 𝒫))
    CH4 = first(filter(p -> p.id == "CH4", 𝒫))
    Blend = first(filter(p -> p.id == "Blend", 𝒫))

    @testset "Basic case - results" begin
        t = first(collect(𝒯))
        f_h2 = value(m[:link_in][ℒ[1], t, H2])
        f_ch4_1 = value(m[:link_in][ℒ[2], t, CH4])
        f_ch4_2 = value(m[:link_in][ℒ[3], t, CH4])
        f_blend = value(m[:link_in][ℒ[4], t, Blend])
        @test f_h2 ≈ 0.0 atol = 1e-4
        # Both CH4 paths have identical Weymouth data, so the optimum splits evenly
        @test f_ch4_1 ≈ f_ch4_2 atol = 1e-1
        @test f_blend ≈ f_h2 + f_ch4_1 + f_ch4_2 atol = 1e-3
        @test f_blend > 50
        # The PWA is an outer approximation: it may overestimate, but must not cut flow
        f_exact = exact_blend_flow(m, ℒ[4], t, Blend, H2, 0.0)
        @test 0.9 * f_exact ≤ f_blend ≤ 1.25 * f_exact
        @test value(m[:proportion_out][𝒩[4], first(collect(𝒯)), H2]) ≈ 0.0 atol = 1e-3
        @test value(m[:proportion_out][𝒩[4], first(collect(𝒯)), CH4]) ≈ 1.0 atol = 1e-3
    end

    @testset "Basic case - approximation" begin
        pressure_data = first(filter(data -> data isa PressureLinkData, ℒ[4].data))
        blend_data = first(filter(data -> data isa BlendLinkData, ℒ[4].data))
        pwa = EMGN.get_pwa(pressure_data, blend_data, EMGNSetup.mip_optimizer())

        pin = value(m[:link_potential_in][ℒ[4], first(collect(𝒯)), Blend])
        pout = value(m[:link_potential_out][ℒ[4], first(collect(𝒯)), Blend])
        prop = 0

        @test isapprox(PiecewiseAffineApprox.evaluate(pwa, (pin, pout, prop)),
            value(m[:link_in][ℒ[4], first(collect(𝒯)), Blend]); atol = 1e-1)

        rhs = test_approx(0.24,
            [(200, pout) for pout ∈ range(200, 130, length = 150)[2:end]],
            value(m[:link_potential_in][ℒ[3], first(collect(𝒯)), CH4]),
            value(m[:link_potential_out][ℒ[3], first(collect(𝒯)), CH4]))
        @test isapprox(rhs, value(m[:link_in][ℒ[3], first(collect(𝒯)), CH4]); atol = 1e-1)

        @test value(m[:link_in][ℒ[1], first(collect(𝒯)), H2]) ≈ 0.0 atol = 1e-4
        t = first(collect(𝒯))
        @test value(m[:proportion_out][𝒩[4], t, H2]) ≈ 0.0 atol = 1e-3
        @test value(m[:flow_component][ℒ[4], t, H2]) ≈
              value(m[:proportion_out][𝒩[4], t, H2]) * value(m[:link_in][ℒ[4], t, Blend]) atol =
            1e-2
    end
end

@testitem "Blending pressure - 10pct H2 case" setup = [EMGNSetup] begin
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

    function test_approx(weymouth, pressure_points, link_potential_in, link_potential_out)
        rhs = Float64[]
        for (p_in, p_out) ∈ pressure_points
            value =
                sqrt(weymouth) * (
                    (p_in / (sqrt(p_in^2 - p_out^2))) * link_potential_in -
                    (p_out / (sqrt(p_in^2 - p_out^2))) * link_potential_out
                )
            push!(rhs, value)
        end
        return minimum(rhs)
    end
    # Exact Weymouth flow on the blend pipe ℒ[4] at the solved pressures, using the same
    # inputs as `get_pwa`. Results depend on the (random) PWA fit, so flows are checked
    # against physics and balances instead of fixed values.
    function exact_blend_flow(m, l, t, Blend, H2, prop)
        bd = first(filter(d -> d isa BlendLinkData, l.data))
        W = round(
            EMGN.normalised_weymouth(bd, 0.24, bd.track_molar_fraction[H2]),
            digits = 4,
        )
        pin = value(m[:link_potential_in][l, t, Blend])
        pout = value(m[:link_potential_out][l, t, Blend])
        return EMGN.calculate_flow_to_approximate(W, pin, pout, prop, 16.04, 2.016)
    end

    function generate_case_blending_pressure(;
        max_h2 = 0.05, min_h2 = 0.0, cost_s3 = 5, cost_h2 = 10)
        H2 = ResourcePressure("H2", 1.0)
        CH4 = ResourcePressure("CH4", 1.0)
        Blend = ResourcePooling("Blend", [H2, CH4])
        CO2 = ResourceEmit("CO2", 1.0)
        Power = ResourceCarrier("Power", 1.0)
        products = [CO2, Blend, H2, CH4, Power]

        op_duration = 1
        op_number = 1
        operational_periods = TimeStruct.SimpleTimes(op_number, op_duration)
        op_per_strat = op_duration * op_number
        T = TwoLevel(1, 1, operational_periods; op_per_strat)

        nodes = [
            RefSource("supply_h2", FixedProfile(2000), FixedProfile(cost_h2),
                FixedProfile(0), Dict(H2 => 1), [MaxPressureData(FixedProfile(0))]),
            RefSource("supply_ch4_1", FixedProfile(5000), FixedProfile(10),
                FixedProfile(0), Dict(CH4 => 1), [MaxPressureData(FixedProfile(0))]),
            RefSource("supply_ch4_2", FixedProfile(2000), FixedProfile(cost_s3),
                FixedProfile(0), Dict(CH4 => 1), [MaxPressureData(FixedProfile(0))]),
            PoolingNode("pooling_node", FixedProfile(1e6), FixedProfile(0),
                FixedProfile(0),
                Dict(CH4 => 1, H2 => 1), Dict(Blend => 1),
                [MaxPressureData(FixedProfile(180))]),
            RefSink("sink", FixedProfile(0),
                Dict(:surplus => FixedProfile(-120), :deficit => FixedProfile(1e6)),
                Dict(Blend => 1),
                [
                    RefBlendData{ResourcePressure{Float64}}(Blend,
                        Dict(H2 => max_h2, CH4 => 1.0), Dict(H2 => min_h2, CH4 => 0.0)),
                    MinPressureData(FixedProfile(130))]),
            RefSource("supply_power", FixedProfile(1000), FixedProfile(0.5),
                FixedProfile(0), Dict(Power => 1)),
            SimpleCompressor("compressor_1", FixedProfile(1e6), FixedProfile(0),
                FixedProfile(0), Dict(H2 => 1, Power => 1.2), Dict(H2 => 1),
                FixedProfile(180), [MaxPressureData(FixedProfile(180))]),
            SimpleCompressor("compressor_2", FixedProfile(1e6), FixedProfile(0),
                FixedProfile(0), Dict(CH4 => 1, Power => 1.2), Dict(CH4 => 1),
                FixedProfile(180), [MaxPressureData(FixedProfile(180))]),
            SimpleCompressor("compressor_3", FixedProfile(1e6), FixedProfile(0),
                FixedProfile(0), Dict(CH4 => 1, Power => 1.2), Dict(CH4 => 1),
                FixedProfile(180), [MaxPressureData(FixedProfile(180))]),
        ]

        links = [
            CapDirect("", nodes[7], nodes[4], Linear(), FixedProfile(200),
                [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6))],
            ),
            CapDirect(24, nodes[8], nodes[4], Linear(), FixedProfile(200),
                [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6))],
            ),
            CapDirect(34, nodes[9], nodes[4], Linear(), FixedProfile(200),
                [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6))],
            ),
            CapDirect(45, nodes[4], nodes[5], Linear(), FixedProfile(1200),
                [PressureLinkData(0.24, 180, 130), MinPressureData(FixedProfile(130)),
                    BlendLinkData(Blend,
                        Dict{ResourcePressure{Float64},Float64}(H2 => 2.016),
                        0.1, 0.0,
                        Dict{ResourcePressure{Float64},Float64}(CH4 => 16.04))]),
            Direct("source_compressor_1", nodes[1], nodes[7], Linear()),
            Direct("source_compressor_2", nodes[2], nodes[8], Linear()),
            Direct("source_compressor_3", nodes[3], nodes[9], Linear()),
            Direct("power_compressor_1", nodes[6], nodes[7], Linear()),
            Direct("power_compressor_2", nodes[6], nodes[8], Linear()),
            Direct("power_compressor_3", nodes[6], nodes[9], Linear()),
        ]

        case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
        model = OperationalModel(Dict(CO2 => FixedProfile(0)),
            Dict(CO2 => FixedProfile(0)), CO2)

        EMGNSetup.setup_pwa!(; step = 10)   # checks the PWA accuracy
        m = create_model(case, model; check_timeprofiles = true)
        set_optimizer(m, EMGNSetup.scip_optimizer())
        optimize!(m)
        return case, model, m
    end

    case, model, m =
        generate_case_blending_pressure(; max_h2 = 0.1, min_h2 = 0.00, cost_s3 = 5)

    𝒩 = get_nodes(case)
    ℒ = get_links(case)
    𝒫 = get_products(case)
    𝒯 = get_time_struct(case)

    H2 = first(filter(p -> p.id == "H2", 𝒫))
    CH4 = first(filter(p -> p.id == "CH4", 𝒫))
    Blend = first(filter(p -> p.id == "Blend", 𝒫))

    @testset "0.1% H2 case - results" begin
        t = first(collect(𝒯))
        f_h2 = value(m[:link_in][ℒ[1], t, H2])
        f_ch4_1 = value(m[:link_in][ℒ[2], t, CH4])
        f_ch4_2 = value(m[:link_in][ℒ[3], t, CH4])
        f_blend = value(m[:link_in][ℒ[4], t, Blend])
        @test f_h2 ≈ 0.1 * f_blend atol = 1e-2
        # Both CH4 paths have identical Weymouth data, so the optimum splits evenly
        @test f_ch4_1 ≈ f_ch4_2 atol = 1e-1
        @test f_blend ≈ f_h2 + f_ch4_1 + f_ch4_2 atol = 1e-3
        @test f_blend > 50
        # The PWA is an outer approximation: it may overestimate, but must not cut flow
        f_exact = exact_blend_flow(m, ℒ[4], t, Blend, H2, 0.1)
        @test 0.9 * f_exact ≤ f_blend ≤ 1.25 * f_exact
        @test value(m[:proportion_out][𝒩[4], first(collect(𝒯)), H2]) ≈ 0.1 atol = 1e-3
        @test value(m[:proportion_out][𝒩[4], first(collect(𝒯)), CH4]) ≈ 0.90 atol = 1e-3
    end

    @testset "0.1% H2 case - approximation" begin
        pressure_data = first(filter(data -> data isa PressureLinkData, ℒ[4].data))
        blend_data = first(filter(data -> data isa BlendLinkData, ℒ[4].data))
        pwa = EMGN.get_pwa(pressure_data, blend_data, EMGNSetup.mip_optimizer())

        pin = value(m[:link_potential_in][ℒ[4], first(collect(𝒯)), Blend])
        pout = value(m[:link_potential_out][ℒ[4], first(collect(𝒯)), Blend])
        prop = 0.1

        @test isapprox(PiecewiseAffineApprox.evaluate(pwa, (pin, pout, prop)),
            value(m[:link_in][ℒ[4], first(collect(𝒯)), Blend]); atol = 1e-1)

        rhs = test_approx(0.24,
            [(200, pout) for pout ∈ range(200, 130, length = 150)[2:end]],
            value(m[:link_potential_in][ℒ[3], first(collect(𝒯)), CH4]),
            value(m[:link_potential_out][ℒ[3], first(collect(𝒯)), CH4]))
        @test isapprox(rhs, value(m[:link_in][ℒ[3], first(collect(𝒯)), CH4]); atol = 1e-1)

        rhs = test_approx(0.24,
            [(200, pout) for pout ∈ range(200, 130, length = 150)[2:end]],
            value(m[:link_potential_in][ℒ[1], first(collect(𝒯)), H2]),
            value(m[:link_potential_out][ℒ[1], first(collect(𝒯)), H2]))
        @test isapprox(rhs, value(m[:link_in][ℒ[1], first(collect(𝒯)), H2]); atol = 1e-1)
    end
end
