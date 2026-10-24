@testitem "Unit conversion - single resource flow-pressure" setup = [EMGNSetup] begin
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

    function calculate_rhs_taylor(link_p_in, link_p_out, l)
        pressure_data = first(filter(data -> data isa PressureLinkData, l.data))
        weymouth_ct = EMGN.get_weymouth(pressure_data)
        POut, PIn = EMGN.potential_data(pressure_data)
        pressures_points = [(PIn, p) for p ∈ range(PIn, POut; length = 150)[2:end]]
        RHS_values = []
        for (p_in, p_out) ∈ pressures_points
            val_rhs =
                sqrt(weymouth_ct) * (
                    (p_in / (sqrt(p_in^2 - p_out^2))) * link_p_in -
                    (p_out / (sqrt(p_in^2 - p_out^2))) * link_p_out
                )
            push!(RHS_values, val_rhs)
        end
        return RHS_values
    end

    function generate_case_single_resource()
        NG = ResourcePressure("NG", 1.0)
        CO2 = ResourceEmit("CO2", 1.0)
        Energy = ResourceCarrier("Energy", 1.0)
        products = [CO2, NG, Energy]

        T = TwoLevel(1, 1, TimeStruct.SimpleTimes(1, 1); op_per_strat = 1)

        nodes = [
            RefSource("source_1", FixedProfile(200), FixedProfile(0), FixedProfile(0),
                Dict(NG => 1), [FixPressureData(FixedProfile(130))]),
            RefConversion("conversion", Dict(NG => 1), Dict(Energy => 1),
                [FlowToEnergyData(10.3)]),
            RefSink("sink_1", FixedProfile(0),
                Dict(:surplus => FixedProfile(-1000), :deficit => FixedProfile(1e6)),
                Dict(Energy => 1)),
        ]
        links = [
            CapDirect("source_to_conversion", nodes[1], nodes[2], Linear(),
                FixedProfile(200),
                [PressureLinkData(0.24, 200, 0), MinPressureData(FixedProfile(120))]),
            Direct("conversion_to_sink", nodes[2], nodes[3], Linear()),
        ]

        case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
        model = OperationalModel(Dict(CO2 => FixedProfile(0)),
            Dict(CO2 => FixedProfile(0)), CO2)
        return case, model
    end

    case, model = generate_case_single_resource()
    m = EMB.create_model(case, model; check_timeprofiles = true)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)

    𝒩 = get_nodes(case)
    ℒ = get_links(case)
    𝒫 = get_products(case)
    𝒯 = get_time_struct(case)

    @testset "Flow-Pressure Results" begin
        t = first(𝒯)
        NG = first(filter(p -> p.id == "NG", 𝒫))
        potential_in = value(m[:link_potential_in][ℒ[1], t, NG])
        potential_out = value(m[:link_potential_out][ℒ[1], t, NG])
        @test potential_in == 130
        @test potential_out == 120
        rhs = minimum(calculate_rhs_taylor(potential_in, potential_out, ℒ[1]))
        link_in = value(m[:link_in][ℒ[1], t, NG])
        @test isapprox(rhs, link_in; atol = 1e-2)
    end

    @testset "Unit Conversion Results" begin
        t = first(𝒯)
        NG = first(filter(p -> p.id == "NG", 𝒫))
        Energy = first(filter(p -> p.id == "Energy", 𝒫))
        n_conversion = first(filter(n -> n.id == "conversion", 𝒩))
        flow_in = value(m[:flow_in][n_conversion, t, NG])
        @test isapprox(flow_in, 24.5; atol = 1e-2)
        flow_out_energy = value(m[:flow_out][n_conversion, t, Energy])
        @test isapprox(flow_out_energy, 24.5 * 10.3; atol = 1e-2)
        n_sink = first(filter(n -> n.id == "sink_1", 𝒩))
        flow_in_sink = value(m[:flow_in][n_sink, t, Energy])
        @test isapprox(flow_in_sink, flow_out_energy; atol = 1e-2)
    end
end

@testitem "Unit conversion - pooling resource" setup = [EMGNSetup] begin
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

    function generate_case_pooling_resource()
        NG = ResourceCarrier("NG", 1.0)
        H2 = ResourceCarrier("H2", 1.0)
        Blend = ResourcePooling("Blend", [NG, H2])
        Energy = ResourceCarrier("Energy", 1.0)
        CO2 = ResourceEmit("CO2", 1.0)
        products = [CO2, NG, H2, Blend, Energy]

        T = TwoLevel(1, 1, TimeStruct.SimpleTimes(1, 1); op_per_strat = 1)

        nodes = [
            RefSource("source_ng", FixedProfile(200), FixedProfile(10), FixedProfile(0),
                Dict(NG => 1)),
            RefSource("source_h2", FixedProfile(200), FixedProfile(0), FixedProfile(0),
                Dict(H2 => 1)),
            PoolingNode("pooling", FixedProfile(1e6), FixedProfile(0), FixedProfile(0),
                Dict(NG => 1, H2 => 1), Dict(Blend => 1),
                [
                    RefBlendData(
                        Blend,
                        Dict(H2 => 0.1, NG => 1.0),
                        Dict(H2 => 0.0, NG => 0.0),
                    ),
                ]),
            RefConversion("conversion", Dict(Blend => 1), Dict(Energy => 1),
                [FlowToEnergyData(Dict(NG => 10.3, H2 => 3.5))]),
            RefSink("sink", FixedProfile(0),
                Dict(:surplus => FixedProfile(-100), :deficit => FixedProfile(1e6)),
                Dict(Energy => 1)),
        ]
        links = [
            Direct("ng_to_pooling", nodes[1], nodes[3], Linear()),
            Direct("h2_to_pooling", nodes[2], nodes[3], Linear()),
            Direct("pooling_to_conversion", nodes[3], nodes[4], Linear()),
            Direct("conversion_to_sink", nodes[4], nodes[5], Linear()),
        ]

        case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
        model = OperationalModel(Dict(CO2 => FixedProfile(0)),
            Dict(CO2 => FixedProfile(0)), CO2)
        return case, model
    end

    case, model = generate_case_pooling_resource()
    m = EMB.create_model(case, model; check_timeprofiles = true)
    set_optimizer(m, EMGNSetup.scip_optimizer())
    optimize!(m)

    𝒩 = get_nodes(case)
    ℒ = get_links(case)
    𝒫 = get_products(case)
    𝒯 = get_time_struct(case)

    @testset "Pooling Results" begin
        H2 = first(filter(p -> p.id == "H2", 𝒫))
        Blend = first(filter(p -> p.id == "Blend", 𝒫))
        n = first(filter(n -> n.id == "pooling", 𝒩))
        proportion_h2 = value(m[:proportion_out][n, first(𝒯), H2])
        @test isapprox(proportion_h2, 0.1; atol = 0.02)
        n_pooling = first(filter(n -> n.id == "pooling", 𝒩))
        proportion_h2 = value(m[:proportion_out][n_pooling, first(𝒯), H2])
        flow_in =
            value(m[:flow_in][first(filter(n -> n.id == "conversion", 𝒩)), first(𝒯), Blend])
        @test isapprox(proportion_h2, 0.1; atol = 0.02)
        @test isapprox(flow_in, 222.222; rtol = 0.05)
    end

    @testset "Unit Conversion Results" begin
        t = first(𝒯)
        NG = first(filter(p -> p.id == "NG", 𝒫))
        H2 = first(filter(p -> p.id == "H2", 𝒫))
        Blend = first(filter(p -> p.id == "Blend", 𝒫))
        Energy = first(filter(p -> p.id == "Energy", 𝒫))
        n_conversion = first(filter(n -> n.id == "conversion", 𝒩))
        flow_in = value(m[:flow_in][n_conversion, t, Blend])
        proportion_h2 = 0.1
        proportion_ng = 0.9
        flow_out_energy = value(m[:flow_out][n_conversion, t, Energy])
        @test isapprox(flow_out_energy,
            flow_in * (10.3 * proportion_ng + 3.5 * proportion_h2); rtol = 0.02)
        n_sink = first(filter(n -> n.id == "sink", 𝒩))
        flow_in_sink = value(m[:flow_in][n_sink, t, Energy])
        @test isapprox(flow_in_sink, 2137.78; rtol = 0.05)
    end
end

@testitem "Unit conversion - BlendingNode to RefConversion max_h2" setup = [EMGNSetup] begin
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

    function generate_case_blending_to_conversion_max_h2()
        CH4 = ResourceCarrier("CH4", 1.0)
        H2 = ResourceCarrier("H2", 1.0)
        Blend = ResourcePooling("Blend", [CH4, H2])
        Power = ResourceCarrier("Power", 1.0)
        CO2 = ResourceEmit("CO2", 1.0)
        products = [CO2, CH4, H2, Blend, Power]

        T = TwoLevel(1, 1, TimeStruct.SimpleTimes(1, 1); op_per_strat = 1)

        nodes = [
            RefSource("src_ch4", FixedProfile(100), FixedProfile(1), FixedProfile(0),
                Dict(CH4 => 1)),
            RefSource("src_h2", FixedProfile(100), FixedProfile(0), FixedProfile(0),
                Dict(H2 => 1)),
            BlendingNode("blending", FixedProfile(1e6), FixedProfile(0),
                FixedProfile(0),
                Dict(CH4 => 1, H2 => 1), Dict(Blend => 1), EMB.ExtensionData[]),
            RefConversion("conversion", Dict(Blend => 1), Dict(Power => 1),
                EMB.ExtensionData[
                    FlowToEnergyData(Dict(CH4 => 11.63, H2 => 3.54)),
                    RefBlendData(Blend, Dict(H2 => 0.05, CH4 => 1.0),
                        Dict(H2 => 0.0, CH4 => 0.0))]),
            RefSink("sink", FixedProfile(0),
                Dict(:surplus => FixedProfile(-100), :deficit => FixedProfile(1e6)),
                Dict(Power => 1)),
        ]
        links = [
            Direct("ch4_to_blend", nodes[1], nodes[3], Linear()),
            Direct("h2_to_blend", nodes[2], nodes[3], Linear()),
            Direct("blend_to_conv", nodes[3], nodes[4], Linear()),
            Direct("conv_to_sink", nodes[4], nodes[5], Linear()),
        ]

        case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
        model = OperationalModel(Dict(CO2 => FixedProfile(0)),
            Dict(CO2 => FixedProfile(0)), CO2)
        return case, model
    end

    case_b2c, model_b2c = generate_case_blending_to_conversion_max_h2()
    m_b2c = EMB.create_model(case_b2c, model_b2c; check_timeprofiles = true)
    set_optimizer(m_b2c, EMGNSetup.scip_optimizer())
    optimize!(m_b2c)

    @testset "max_h2 constraint" begin
        𝒩_b2c = get_nodes(case_b2c)
        ℒ_b2c = get_links(case_b2c)
        𝒫_b2c = get_products(case_b2c)
        𝒯_b2c = get_time_struct(case_b2c)
        t = first(𝒯_b2c)

        H2 = first(filter(p -> p.id == "H2", 𝒫_b2c))
        Blend = first(filter(p -> p.id == "Blend", 𝒫_b2c))
        l_blend = first(filter(l -> l.id == "blend_to_conv", ℒ_b2c))

        fc_h2 = value(m_b2c[:flow_component][l_blend, t, H2])
        li_blend = value(m_b2c[:link_in][l_blend, t, Blend])

        @test termination_status(m_b2c) == MOI.OPTIMAL
        h2_fraction = li_blend > 1e-9 ? fc_h2 / li_blend : 0.0
        @test h2_fraction ≤ 0.05 + 1e-6
        @test li_blend > 1.0
    end
end
