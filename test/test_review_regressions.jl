# Regression tests for the code-review findings on the v0.3.0 development branch.

@testitem "Review - FlowPressureCompressor raises pressure on blend" setup = [EMGNSetup] begin
    using .EMGNSetup
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using JuMP
    using MathOptInterface
    using Test
    using TimeStruct
    const EMB = EnergyModelsBase
    const MOI = MathOptInterface

    H2 = ResourcePressure("H2", 1.0)
    CH4 = ResourcePressure("CH4", 1.0)
    Blend = ResourcePooling("Blend", [H2, CH4])
    Power = ResourceCarrier("Power", 0.0)
    CO2 = ResourceEmit("CO2", 1.0)
    products = [CO2, Blend, H2, CH4, Power]
    T = TwoLevel(1, 1, SimpleTimes(1, 1); op_per_strat = 1)

    P_SRC = 30.0
    P_SINK = 50.0
    nodes = [
        RefSource("src_h2", FixedProfile(1), FixedProfile(0), FixedProfile(0),
            Dict(H2 => 1), [FixPressureData(FixedProfile(P_SRC))]),
        RefSource("src_ch4", FixedProfile(9), FixedProfile(0), FixedProfile(0),
            Dict(CH4 => 1), [FixPressureData(FixedProfile(P_SRC))]),
        RefSource("src_pwr", FixedProfile(1000), FixedProfile(0.001), FixedProfile(0),
            Dict(Power => 1)),
        BlendingNode("mix", FixedProfile(1e6), FixedProfile(0), FixedProfile(0),
            Dict(H2 => 1, CH4 => 1), Dict(Blend => 1), EMB.ExtensionData[]),
        FlowPressureCompressor("comp", FixedProfile(100), FixedProfile(0),
            FixedProfile(0), Dict(Blend => 1, Power => 1), Dict(Blend => 1),
            FixedProfile(100), FixedProfile(0.5), FixedProfile(0.01),
            EMB.ExtensionData[]),
        RefSink("sink", FixedProfile(10),
            Dict(:surplus => FixedProfile(0), :deficit => FixedProfile(1e4)),
            Dict(Blend => 1), [MinPressureData(FixedProfile(P_SINK))]),
    ]
    links = [
        CapDirect("h2_mix", nodes[1], nodes[4], Linear(), FixedProfile(100)),
        CapDirect("ch4_mix", nodes[2], nodes[4], Linear(), FixedProfile(100)),
        CapDirect("mix_comp", nodes[4], nodes[5], Linear(), FixedProfile(100)),
        Direct("pwr_comp", nodes[3], nodes[5], Linear()),
        CapDirect("comp_sink", nodes[5], nodes[6], Linear(), FixedProfile(100)),
    ]
    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model =
        OperationalModel(Dict(CO2 => FixedProfile(0)), Dict(CO2 => FixedProfile(0)), CO2)
    EMGNSetup.setup_pwa!()
    m = create_model(case, model)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)

    t = first(T)
    @test termination_status(m) == MOI.OPTIMAL
    @test value(m[:flow_in][nodes[6], t, Blend]) ≈ 10 atol = 1e-4
    @test value(m[:potential_Δ][nodes[5], t]) ≥ P_SINK - P_SRC - 1e-4
end

@testitem "Review - TransitNode split without has_flow is rejected" setup = [EMGNSetup] begin
    using .EMGNSetup
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using JuMP
    using Test
    using TimeStruct
    const EMB = EnergyModelsBase

    H2 = ResourceCarrier("H2", 1.0)
    CH4 = ResourceCarrier("CH4", 1.0)
    Blend = ResourcePooling("Blend", [H2, CH4])
    CO2 = ResourceEmit("CO2", 1.0)
    products = [CO2, Blend, H2, CH4]
    T = TwoLevel(1, 1, SimpleTimes(1, 1); op_per_strat = 1)

    sink(id) = RefSink(id, FixedProfile(5),
        Dict(:surplus => FixedProfile(0), :deficit => FixedProfile(1e4)),
        Dict(Blend => 1))
    nodes = [
        RefSource("src_h2", FixedProfile(10), FixedProfile(0), FixedProfile(0),
            Dict(H2 => 1)),
        RefSource("src_ch4", FixedProfile(10), FixedProfile(0), FixedProfile(0),
            Dict(CH4 => 1)),
        PoolingNode("pool", FixedProfile(1e6), FixedProfile(0), FixedProfile(0),
            Dict(H2 => 1, CH4 => 1), Dict(Blend => 1), EMB.ExtensionData[]),
        TransitNode("transit", FixedProfile(1e6), FixedProfile(0), FixedProfile(0),
            Dict(Blend => 1), Dict(Blend => 1), EMB.ExtensionData[]),
        sink("sink1"),
        sink("sink2"),
    ]
    links = [
        Direct("h2_pool", nodes[1], nodes[3], Linear()),
        Direct("ch4_pool", nodes[2], nodes[3], Linear()),
        Direct("pool_transit", nodes[3], nodes[4], Linear()),
        Direct("transit_sink1", nodes[4], nodes[5], Linear()),
        Direct("transit_sink2", nodes[4], nodes[6], Linear()),
    ]
    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model =
        OperationalModel(Dict(CO2 => FixedProfile(0)), Dict(CO2 => FixedProfile(0)), CO2)
    @test_throws ArgumentError create_model(case, model)
end

@testitem "Review - TransitNode split sends blend down one link per period" setup =
    [EMGNSetup] begin
    using .EMGNSetup
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using JuMP
    using MathOptInterface
    using Test
    using TimeStruct
    const EMB = EnergyModelsBase
    const MOI = MathOptInterface

    H2 = ResourcePressure("H2", 1.0)
    CH4 = ResourcePressure("CH4", 1.0)
    Blend = ResourcePooling("Blend", [H2, CH4])
    CO2 = ResourceEmit("CO2", 1.0)
    products = [CO2, Blend, H2, CH4]
    T = TwoLevel(1, 1, SimpleTimes(2, 1); op_per_strat = 2)

    # Both sinks pay for gas, so the optimum would serve both if the transit node could split
    sink(id) = RefSink(id, FixedProfile(5),
        Dict(:surplus => FixedProfile(1), :deficit => FixedProfile(100)),
        Dict(Blend => 1))
    nodes = [
        RefSource("src_h2", FixedProfile(10), FixedProfile(0), FixedProfile(0),
            Dict(H2 => 1), [FixPressureData(FixedProfile(50))]),
        RefSource("src_ch4", FixedProfile(10), FixedProfile(0), FixedProfile(0),
            Dict(CH4 => 1), [FixPressureData(FixedProfile(50))]),
        PoolingNode("pool", FixedProfile(1e3), FixedProfile(0), FixedProfile(0),
            Dict(H2 => 1, CH4 => 1), Dict(Blend => 1), EMB.ExtensionData[]),
        TransitNode("transit", FixedProfile(1e3), FixedProfile(0), FixedProfile(0),
            Dict(Blend => 1), Dict(Blend => 1), EMB.ExtensionData[]),
        sink("sink1"),
        sink("sink2"),
    ]
    links = [
        CapDirect("h2_pool", nodes[1], nodes[3], Linear(), FixedProfile(100)),
        CapDirect("ch4_pool", nodes[2], nodes[3], Linear(), FixedProfile(100)),
        CapDirect("pool_transit", nodes[3], nodes[4], Linear(), FixedProfile(100)),
        CapDirect("transit_sink1", nodes[4], nodes[5], Linear(), FixedProfile(100)),
        CapDirect("transit_sink2", nodes[4], nodes[6], Linear(), FixedProfile(100)),
    ]
    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model =
        OperationalModel(Dict(CO2 => FixedProfile(0)), Dict(CO2 => FixedProfile(0)), CO2)
    EMGNSetup.setup_pwa!()
    m = create_model(case, model)
    set_optimizer(m, EMGNSetup.scip_optimizer())
    optimize!(m)

    @test termination_status(m) == MOI.OPTIMAL
    for t ∈ T
        flows = [value(m[:link_in][l, t, Blend]) for l ∈ links[4:5]]
        @test count(>(1e-6), flows) == 1
        @test sum(flows) ≈ 5 atol = 1e-4
    end
end

@testitem "Review - bidirectional TransitNode pair stays feasible" setup = [EMGNSetup] begin
    using .EMGNSetup
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using JuMP
    using MathOptInterface
    using Test
    using TimeStruct
    const EMB = EnergyModelsBase
    const MOI = MathOptInterface

    H2 = ResourcePressure("H2", 1.0)
    CH4 = ResourcePressure("CH4", 1.0)
    Blend = ResourcePooling("Blend", [H2, CH4])
    CO2 = ResourceEmit("CO2", 1.0)
    products = [CO2, Blend, H2, CH4]
    T = TwoLevel(1, 1, SimpleTimes(1, 1); op_per_strat = 1)

    transit(id) = TransitNode(id, FixedProfile(1e3), FixedProfile(0), FixedProfile(0),
        Dict(Blend => 1), Dict(Blend => 1), EMB.ExtensionData[])
    nodes = [
        RefSource("src_h2", FixedProfile(1), FixedProfile(0), FixedProfile(0),
            Dict(H2 => 1), [FixPressureData(FixedProfile(50))]),
        RefSource("src_ch4", FixedProfile(9), FixedProfile(0), FixedProfile(0),
            Dict(CH4 => 1), [FixPressureData(FixedProfile(50))]),
        PoolingNode("pool", FixedProfile(1e3), FixedProfile(0), FixedProfile(0),
            Dict(H2 => 1, CH4 => 1), Dict(Blend => 1), EMB.ExtensionData[]),
        transit("a"),
        transit("b"),
        RefSink("sink", FixedProfile(10),
            Dict(:surplus => FixedProfile(0), :deficit => FixedProfile(100)),
            Dict(Blend => 1)),
    ]
    # `b` has two outgoing blend links (b→a and b→sink); only b→sink should carry flow
    links = [
        CapDirect("h2_pool", nodes[1], nodes[3], Linear(), FixedProfile(100)),
        CapDirect("ch4_pool", nodes[2], nodes[3], Linear(), FixedProfile(100)),
        CapDirect("pool_a", nodes[3], nodes[4], Linear(), FixedProfile(100)),
        CapDirect("a_b", nodes[4], nodes[5], Linear(), FixedProfile(100)),
        CapDirect("b_a", nodes[5], nodes[4], Linear(), FixedProfile(100)),
        CapDirect("b_sink", nodes[5], nodes[6], Linear(), FixedProfile(100)),
    ]
    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model =
        OperationalModel(Dict(CO2 => FixedProfile(0)), Dict(CO2 => FixedProfile(0)), CO2)
    EMGNSetup.setup_pwa!()
    m = create_model(case, model)
    set_optimizer(m, EMGNSetup.scip_optimizer())
    optimize!(m)

    t = first(T)
    @test termination_status(m) == MOI.OPTIMAL
    @test value(m[:flow_in][nodes[6], t, Blend]) ≈ 10 atol = 1e-4
    @test value(m[:link_in][links[5], t, Blend]) ≈ 0 atol = 1e-6
    # `b` feeds no BlendLinkData link, so it tracks no share; its outflow has the pool mix
    @test nodes[5] ∉ axes(m[:proportion_out], 1)
    @test value(m[:flow_component][links[6], t, H2]) ≈
          0.1 * value(m[:link_in][links[6], t, Blend]) atol = 1e-4
end

@testitem "Review - UnitConversion LHV dict must cover the blend" setup = [EMGNSetup] begin
    using .EMGNSetup
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using JuMP
    using Test
    using TimeStruct
    const EMB = EnergyModelsBase

    H2 = ResourceCarrier("H2", 1.0)
    CH4 = ResourceCarrier("CH4", 1.0)
    Blend = ResourcePooling("Blend", [H2, CH4])
    Energy = ResourceCarrier("Energy", 1.0)
    CO2 = ResourceEmit("CO2", 1.0)
    products = [CO2, Blend, H2, CH4, Energy]
    T = TwoLevel(1, 1, SimpleTimes(1, 1); op_per_strat = 1)

    nodes = [
        RefSource("src_h2", FixedProfile(10), FixedProfile(0), FixedProfile(0),
            Dict(H2 => 1)),
        RefSource("src_ch4", FixedProfile(10), FixedProfile(0), FixedProfile(0),
            Dict(CH4 => 1)),
        BlendingNode("mix", FixedProfile(1e6), FixedProfile(0), FixedProfile(0),
            Dict(H2 => 1, CH4 => 1), Dict(Blend => 1), EMB.ExtensionData[]),
        RefConversion("conv", Dict(Blend => 1), Dict(Energy => 1),
            EMB.ExtensionData[FlowToEnergyData(Dict(CH4 => 10.0))]),
        RefSink("sink", FixedProfile(0),
            Dict(:surplus => FixedProfile(-1), :deficit => FixedProfile(1e4)),
            Dict(Energy => 1)),
    ]
    links = [
        Direct("h2_mix", nodes[1], nodes[3], Linear()),
        Direct("ch4_mix", nodes[2], nodes[3], Linear()),
        Direct("mix_conv", nodes[3], nodes[4], Linear()),
        Direct("conv_sink", nodes[4], nodes[5], Linear()),
    ]
    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model =
        OperationalModel(Dict(CO2 => FixedProfile(0)), Dict(CO2 => FixedProfile(0)), CO2)
    @test_throws Exception create_model(case, model)
    @test_throws ErrorException create_model(case, model; check_any_data = false)
end

@testitem "Review - UnitConversion sums all incoming blend links" setup = [EMGNSetup] begin
    using .EMGNSetup
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using JuMP
    using MathOptInterface
    using Test
    using TimeStruct
    const EMB = EnergyModelsBase
    const MOI = MathOptInterface

    H2 = ResourceCarrier("H2", 1.0)
    CH4 = ResourceCarrier("CH4", 1.0)
    Blend = ResourcePooling("Blend", [H2, CH4])
    Energy = ResourceCarrier("Energy", 1.0)
    CO2em = ResourceCarrier("CO2em", 0.0)
    CO2 = ResourceEmit("CO2", 1.0)
    products = [CO2, Blend, H2, CH4, Energy, CO2em]
    T = TwoLevel(1, 1, SimpleTimes(1, 1); op_per_strat = 1)

    LHV = Dict(CH4 => 10.0, H2 => 3.0)
    INT = Dict(CH4 => 0.2, H2 => 0.0)
    src(id, p, cap) = RefSource(id, FixedProfile(cap), FixedProfile(0), FixedProfile(0),
        Dict(p => 1))
    nodes = [
        src("src_ch4_a", CH4, 10),
        src("src_h2_b", H2, 2),
        src("src_ch4_b", CH4, 8),
        BlendingNode("mix_a", FixedProfile(1e6), FixedProfile(0), FixedProfile(0),
            Dict(CH4 => 1), Dict(Blend => 1), EMB.ExtensionData[]),
        BlendingNode("mix_b", FixedProfile(1e6), FixedProfile(0), FixedProfile(0),
            Dict(H2 => 1, CH4 => 1), Dict(Blend => 1), EMB.ExtensionData[]),
        RefConversion("conv", Dict(Blend => 1), Dict(Energy => 1, CO2em => 1),
            EMB.ExtensionData[FlowToEnergyData(LHV), EmissionsConversionData(INT, CO2em)]),
        RefSink("sink", FixedProfile(0),
            Dict(:surplus => FixedProfile(-1), :deficit => FixedProfile(1e4)),
            Dict(Energy => 1)),
        RefSink("co2_sink", FixedProfile(0),
            Dict(:surplus => FixedProfile(0), :deficit => FixedProfile(1e4)),
            Dict(CO2em => 1)),
    ]
    links = [
        Direct("ch4a_mix", nodes[1], nodes[4], Linear()),
        Direct("h2b_mix", nodes[2], nodes[5], Linear()),
        Direct("ch4b_mix", nodes[3], nodes[5], Linear()),
        Direct("mixa_conv", nodes[4], nodes[6], Linear()),
        Direct("mixb_conv", nodes[5], nodes[6], Linear()),
        Direct("conv_sink", nodes[6], nodes[7], Linear()),
        Direct("conv_co2", nodes[6], nodes[8], Linear()),
    ]
    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model =
        OperationalModel(Dict(CO2 => FixedProfile(0)), Dict(CO2 => FixedProfile(0)), CO2)
    m = create_model(case, model)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)

    t = first(T)
    conv = nodes[6]
    @test termination_status(m) == MOI.OPTIMAL
    @test value(m[:flow_in][conv, t, Blend]) ≈ 20 atol = 1e-4
    @test value(m[:flow_out][conv, t, Energy]) ≈ 10.0 * 18 + 3.0 * 2 atol = 1e-4
    @test value(m[:flow_out][conv, t, CO2em]) ≈ 0.2 * 18 atol = 1e-4
end

@testitem "Review - scalar LHV with EmissionsConversionData" setup = [EMGNSetup] begin
    using .EMGNSetup
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using JuMP
    using MathOptInterface
    using Test
    using TimeStruct
    const EMB = EnergyModelsBase
    const MOI = MathOptInterface

    H2 = ResourceCarrier("H2", 1.0)
    CH4 = ResourceCarrier("CH4", 1.0)
    Blend = ResourcePooling("Blend", [H2, CH4])
    Energy = ResourceCarrier("Energy", 1.0)
    CO2em = ResourceCarrier("CO2em", 0.0)
    CO2 = ResourceEmit("CO2", 1.0)
    products = [CO2, Blend, H2, CH4, Energy, CO2em]
    T = TwoLevel(1, 1, SimpleTimes(1, 1); op_per_strat = 1)

    nodes = [
        RefSource("src_h2", FixedProfile(1), FixedProfile(0), FixedProfile(0),
            Dict(H2 => 1)),
        RefSource("src_ch4", FixedProfile(9), FixedProfile(0), FixedProfile(0),
            Dict(CH4 => 1)),
        BlendingNode("mix", FixedProfile(1e6), FixedProfile(0), FixedProfile(0),
            Dict(H2 => 1, CH4 => 1), Dict(Blend => 1), EMB.ExtensionData[]),
        RefConversion("conv", Dict(Blend => 1), Dict(Energy => 1, CO2em => 1),
            EMB.ExtensionData[
                FlowToEnergyData(10.0),
                EmissionsConversionData(Dict(CH4 => 0.2, H2 => 0.0), CO2em),
            ]),
        RefSink("sink", FixedProfile(0),
            Dict(:surplus => FixedProfile(-1), :deficit => FixedProfile(1e4)),
            Dict(Energy => 1)),
        RefSink("co2_sink", FixedProfile(0),
            Dict(:surplus => FixedProfile(0), :deficit => FixedProfile(1e4)),
            Dict(CO2em => 1)),
    ]
    links = [
        Direct("h2_mix", nodes[1], nodes[3], Linear()),
        Direct("ch4_mix", nodes[2], nodes[3], Linear()),
        Direct("mix_conv", nodes[3], nodes[4], Linear()),
        Direct("conv_sink", nodes[4], nodes[5], Linear()),
        Direct("conv_co2", nodes[4], nodes[6], Linear()),
    ]
    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model =
        OperationalModel(Dict(CO2 => FixedProfile(0)), Dict(CO2 => FixedProfile(0)), CO2)
    m = create_model(case, model)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)

    t = first(T)
    conv = nodes[4]
    @test termination_status(m) == MOI.OPTIMAL
    @test value(m[:flow_out][conv, t, Energy]) ≈ 10.0 * 10 atol = 1e-4
    @test value(m[:flow_out][conv, t, CO2em]) ≈ 0.2 * 9 atol = 1e-4
end

@testitem "Review - DiscretizedPoolingNode flow bound uses investment capacity" setup =
    [EMGNSetup] begin
    using .EMGNSetup
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using EnergyModelsInvestments
    using JuMP
    using MathOptInterface
    using Test
    using TimeStruct
    const EMB = EnergyModelsBase
    const MOI = MathOptInterface

    H2 = ResourceCarrier("H2", 1.0)
    CH4 = ResourceCarrier("CH4", 1.0)
    Gas = ResourcePooling("Gas", [H2, CH4])
    CO2 = ResourceEmit("CO2", 1.0)
    products = [CO2, Gas, H2, CH4]
    T = TwoLevel(1, 1, SimpleTimes(1, 1); op_per_strat = 1)

    for method ∈ (:bigm, :bigm_log, :pwl)
        inv = SingleInvData(FixedProfile(0.01), FixedProfile(100),
            ContinuousInvestment(FixedProfile(0), FixedProfile(100)), UnlimitedLife())
        nodes = [
            RefSource("src_h2", FixedProfile(10), FixedProfile(0), FixedProfile(0),
                Dict(H2 => 1)),
            RefSource("src_ch4", FixedProfile(50), FixedProfile(0), FixedProfile(0),
                Dict(CH4 => 1)),
            DiscretizedPoolingNode("pool", FixedProfile(0), FixedProfile(0),
                FixedProfile(0), Dict(H2 => 1, CH4 => 1), Dict(Gas => 1),
                Data[DiscretizationData(H2, 5, method, 0.2), inv]),
            RefSink("sink", FixedProfile(40),
                Dict(:surplus => FixedProfile(0), :deficit => FixedProfile(1e3)),
                Dict(Gas => 1)),
        ]
        links = [
            CapDirect("h2_pool", nodes[1], nodes[3], Linear(), FixedProfile(100)),
            CapDirect("ch4_pool", nodes[2], nodes[3], Linear(), FixedProfile(100)),
            CapDirect("pool_sink", nodes[3], nodes[4], Linear(), FixedProfile(100)),
        ]
        case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
        model = InvestmentModel(Dict(CO2 => FixedProfile(0)),
            Dict(CO2 => FixedProfile(0)), CO2, 0.05)
        m = create_model(case, model)
        set_optimizer(m, EMGNSetup.mip_optimizer())
        optimize!(m)

        t = first(T)
        @test termination_status(m) == MOI.OPTIMAL
        @test value(m[:flow_in][nodes[4], t, Gas]) ≈ 40 atol = 1e-3
    end
end

@testitem "Review - inactive PWA link without capacity carries no flow" setup = [EMGNSetup] begin
    using .EMGNSetup
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using JuMP
    using MathOptInterface
    using Test
    using TimeStruct
    const EMB = EnergyModelsBase
    const MOI = MathOptInterface

    H2 = ResourcePressure("H2", 1.0)
    CH4 = ResourcePressure("CH4", 1.0)
    Blend = ResourcePooling("Blend", [H2, CH4])
    CO2 = ResourceEmit("CO2", 1.0)
    products = [CO2, Blend, H2, CH4]
    T = TwoLevel(1, 1, SimpleTimes(1, 1); op_per_strat = 1)

    nodes = [
        RefSource("src_h2", FixedProfile(1000), FixedProfile(1), FixedProfile(0),
            Dict(H2 => 1), [FixPressureData(FixedProfile(100))]),
        RefSource("src_ch4", FixedProfile(1000), FixedProfile(1), FixedProfile(0),
            Dict(CH4 => 1), [FixPressureData(FixedProfile(100))]),
        PoolingNode("entry", FixedProfile(1e6), FixedProfile(0), FixedProfile(0),
            Dict(H2 => 1, CH4 => 1), Dict(Blend => 1),
            [FixPressureData(FixedProfile(80)),
                RefBlendData{ResourcePressure{Float64}}(Blend,
                    Dict(H2 => 0.1, CH4 => 1.0), Dict(H2 => 0.1, CH4 => 0.0))]),
        RefSink("sink", FixedProfile(10),
            Dict(:surplus => FixedProfile(-50), :deficit => FixedProfile(1e6)),
            Dict(Blend => 1), [MinPressureData(FixedProfile(40))]),
    ]
    # A link type without any capacity, so no capacity-based `has_flow` big-M exists
    struct UncappedPipe <: EMB.Link
        id::Any
        from::EMB.Node
        to::EMB.Node
        formulation::EMB.Formulation
        data::Vector{<:EMB.ExtensionData}
    end
    EMB.capacity(l::UncappedPipe, t) = Inf
    EMB.link_data(l::UncappedPipe) = l.data

    pipe = UncappedPipe("pipe", nodes[3], nodes[4], Linear(),
        [PressureLinkData(0.24, 80, 40),
            MinPressureData(FixedProfile(1e-6)),
            BlendLinkData(Blend,
                Dict{ResourcePressure{Float64},Float64}(H2 => 2.016),
                0.2, 0.0,   # H₂ range of the PWA grid (the entry fixes 10 % H₂)
                Dict{ResourcePressure{Float64},Float64}(CH4 => 16.04))])
    links = [
        Direct("h2_entry", nodes[1], nodes[3], Linear()),
        Direct("ch4_entry", nodes[2], nodes[3], Linear()),
        pipe,
    ]
    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model =
        OperationalModel(Dict(CO2 => FixedProfile(0)), Dict(CO2 => FixedProfile(0)), CO2)
    EMGNSetup.setup_pwa!(; step = 10)   # narrow 40–80 bar range
    m = create_model(case, model)

    t = first(T)
    fix(m[:has_flow][pipe, t], 0; force = true)
    set_optimizer(m, EMGNSetup.scip_optimizer())
    optimize!(m)
    @test termination_status(m) ∈ (MOI.OPTIMAL, MOI.ALMOST_OPTIMAL)
    @test value(m[:link_in][pipe, t, Blend]) ≈ 0 atol = 1e-6
end

@testitem "Review - anti-parallel gas and power links" setup = [EMGNSetup] begin
    using .EMGNSetup
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using JuMP
    using MathOptInterface
    using Test
    using TimeStruct
    const EMB = EnergyModelsBase
    const MOI = MathOptInterface

    H2 = ResourcePressure("H2", 1.0)
    Power = ResourceCarrier("Power", 0.0)
    CO2 = ResourceEmit("CO2", 1.0)
    products = [CO2, H2, Power]
    T = TwoLevel(1, 1, SimpleTimes(1, 1); op_per_strat = 1)

    nodes = [
        RefSource("src_h2", FixedProfile(10), FixedProfile(1), FixedProfile(0),
            Dict(H2 => 1), [FixPressureData(FixedProfile(50))]),
        GenAvailability("A", [H2, Power], [H2, Power]),
        RefNetworkNode("B", FixedProfile(100), FixedProfile(0), FixedProfile(0),
            Dict(H2 => 1), Dict(Power => 1)),
        RefSink("pwr_sink", FixedProfile(5),
            Dict(:surplus => FixedProfile(0), :deficit => FixedProfile(1e3)),
            Dict(Power => 1)),
    ]
    links = [
        CapDirect("src_A", nodes[1], nodes[2], Linear(), FixedProfile(100)),
        CapDirect("A_B", nodes[2], nodes[3], Linear(), FixedProfile(100)),
        CapDirect("B_A", nodes[3], nodes[2], Linear(), FixedProfile(100)),
        CapDirect("A_sink", nodes[2], nodes[4], Linear(), FixedProfile(100)),
    ]
    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model =
        OperationalModel(Dict(CO2 => FixedProfile(0)), Dict(CO2 => FixedProfile(0)), CO2)
    m = create_model(case, model)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)
    @test termination_status(m) == MOI.OPTIMAL
    @test value(m[:flow_in][nodes[4], first(T), Power]) ≈ 5 atol = 1e-4
end

@testitem "Review - PWA flow bound covers every plane" setup = [EMGNSetup] begin
    using EnergyModelsGasNetworks
    using PiecewiseAffineApprox
    using Test
    const EMGN = EnergyModelsGasNetworks

    # z ≤ -α⋅x - β. The second plane allows z ≤ 5 at zero potentials with prop = 1.
    planes = [Plane((-0.5, 0.4, 0.0), 0.0), Plane((-0.1, 0.1, -10.0), 5.0)]
    pwa = PWAFunc{Concave,3}(planes)
    M = EMGN._pwa_flow_bound(pwa)
    corners = [(a, b, c) for a ∈ (0.0, 1e4), b ∈ (0.0, 1e4), c ∈ (0.0, 1.0)]
    pwa_max = maximum(minimum(-sum(p.α .* x) - p.β for p ∈ planes) for x ∈ corners)
    @test isfinite(M)
    @test M ≥ pwa_max
    @test M ≥ 5.0
end

@testitem "Review - degenerate PWA fits are rejected" setup = [EMGNSetup] begin
    using EnergyModelsGasNetworks
    using PiecewiseAffineApprox
    using Test
    const EMGN = EnergyModelsGasNetworks

    # Exact flow z = 2 p_in - p_out on a small grid; the plane gives z ≤ 2 p_in - p_out
    points =
        [(p_in, p_out, prop) for p_in ∈ 50.0:10:80, p_out ∈ 40.0:10:50, prop ∈ (0.0, 0.1)]
    points = vec(points)
    z = [2x[1] - x[2] for x ∈ points]
    good = PWAFunc{Concave,3}([Plane((-2.0, 1.0, 0.0), 0.0)])
    zero_plane =
        PWAFunc{Concave,3}([Plane((-2.0, 1.0, 0.0), 0.0), Plane((0.0, 0.0, 0.0), 0.0)])
    @test EMGN._pwa_fit_ok(good, points, z)
    @test EMGN._pwa_underestimate(zero_plane, points, z) ≈ 1.0
    @test !EMGN._pwa_fit_ok(zero_plane, points, z)
end
