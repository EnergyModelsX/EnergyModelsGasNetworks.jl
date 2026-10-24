@testitem "Blend topology - ResourcePooling storage rejected" setup = [EMGNSetup] begin
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
    include("blend_topology_helpers.jl")

    H2, CH4, Blend, CO2 = topology_resources()
    storage = RefStorage{CyclicStrategic}("blend_storage",
        StorCapOpexVar(FixedProfile(10.0), FixedProfile(0.0)),
        StorCap(FixedProfile(10.0)), Blend, Dict(Blend => 1.0), Dict(Blend => 1.0))
    nodes = [
        RefSource("source", FixedProfile(10.0), FixedProfile(0.0), FixedProfile(0.0),
            Dict(Blend => 1.0)),
        storage,
        RefSink("sink", FixedProfile(1.0),
            Dict(:surplus => FixedProfile(0.0), :deficit => FixedProfile(1e3)),
            Dict(Blend => 1.0)),
    ]
    links = [
        Direct("source_storage", nodes[1], nodes[2], Linear()),
        Direct("storage_sink", nodes[2], nodes[3], Linear()),
    ]
    case = topology_case(nodes, links, [CO2, Blend, H2, CH4])
    @test_throws ArgumentError create_model(case, topology_model(CO2))
end

@testitem "Blend topology - pressure provenance rejected" setup = [EMGNSetup] begin
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
    include("blend_topology_helpers.jl")

    for node_type ∈ (BlendingNode, DeblendNode)
        H2, CH4, Blend, CO2 = topology_resources(; pressure = true)
        origin = if node_type == BlendingNode
            BlendingNode("origin", FixedProfile(100.0), FixedProfile(0.0),
                FixedProfile(0.0),
                Dict(H2 => 1.0, CH4 => 1.0), Dict(Blend => 1.0))
        else
            DeblendNode("origin", FixedProfile(100.0), FixedProfile(0.0),
                FixedProfile(0.0),
                Dict(Blend => 1.0), Dict(Blend => 1.0, H2 => 1.0),
                [DeblendData(0.5, 1.0)])
        end
        sink = RefSink("sink", FixedProfile(1.0),
            Dict(:surplus => FixedProfile(0.0), :deficit => FixedProfile(1e3)),
            Dict(Blend => 1.0))
        link = CapDirect("pwa", origin, sink, Linear(), FixedProfile(100.0),
            [PressureLinkData(0.24, 100.0, 40.0),
                BlendLinkData(Blend, Dict(H2 => 2.016), 1.0, 0.0, Dict(CH4 => 16.04))])
        @test_throws ArgumentError EMGN.validate_blend_topology(
            [origin, sink],
            [link],
            [Blend],
        )

        transit = TransitNode("transit", FixedProfile(100.0), FixedProfile(0.0),
            FixedProfile(0.0), Dict(Blend => 1.0), Dict(Blend => 1.0))
        upstream = Direct("origin_transit", origin, transit, Linear())
        indirect = CapDirect("indirect_pwa", transit, sink, Linear(), FixedProfile(100.0),
            EMB.link_data(link))
        @test_throws ArgumentError EMGN.validate_blend_topology(
            [origin, transit, sink], [upstream, indirect], [Blend])
    end
end

@testitem "Blend topology - aggregate quality component-flow merges" setup = [EMGNSetup] begin
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
    include("blend_topology_helpers.jl")

    H2, CH4, Blend, CO2 = topology_resources()
    source_specs = [("h2_low", H2, 20.0), ("ch4_low", CH4, 80.0),
        ("h2_high", H2, 80.0), ("ch4_high", CH4, 20.0)]
    sources = [
        RefSource(id, FixedProfile(cap), FixedProfile(0.0), FixedProfile(0.0),
            Dict(resource => 1.0)) for (id, resource, cap) ∈ source_specs
    ]
    blends = [
        BlendingNode("blend_$i", FixedProfile(100.0), FixedProfile(0.0),
            FixedProfile(0.0), Dict(H2 => 1.0, CH4 => 1.0), Dict(Blend => 1.0)) for
        i ∈ 1:2
    ]
    merge = TransitNode("merge", FixedProfile(200.0), FixedProfile(0.0), FixedProfile(0.0),
        Dict(Blend => 1.0), Dict(Blend => 1.0),
        [blend_bounds(Blend, H2, CH4; min_h2 = 0.5, max_h2 = 0.5)])
    sink = RefSink("sink", FixedProfile(200.0),
        Dict(:surplus => FixedProfile(0.0), :deficit => FixedProfile(1e3)),
        Dict(Blend => 1.0))
    nodes = [sources..., blends..., merge, sink]
    links = [
        Direct("h2_low_blend", sources[1], blends[1], Linear()),
        Direct("ch4_low_blend", sources[2], blends[1], Linear()),
        Direct("h2_high_blend", sources[3], blends[2], Linear()),
        Direct("ch4_high_blend", sources[4], blends[2], Linear()),
        Direct("low_merge", blends[1], merge, Linear()),
        Direct("high_merge", blends[2], merge, Linear()),
        Direct("merge_sink", merge, sink, Linear()),
    ]
    case = topology_case(nodes, links, [CO2, Blend, H2, CH4])
    m = create_model(case, topology_model(CO2))
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)
    t = first(get_time_struct(case))

    @test termination_status(m) == MOI.OPTIMAL
    @test value(m[:flow_component][links[5], t, H2]) ≈ 20.0 atol = 1e-6
    @test value(m[:flow_component][links[6], t, H2]) ≈ 80.0 atol = 1e-6
    @test value(m[:flow_component][links[7], t, H2]) ≈ 100.0 atol = 1e-6
    @test value(m[:link_in][links[7], t, Blend]) ≈ 200.0 atol = 1e-6
end

@testitem "Blend topology - DeblendNode single-output transit path" setup = [EMGNSetup] begin
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
    include("blend_topology_helpers.jl")

    H2, CH4, Blend, CO2 = topology_resources()
    sources = [
        RefSource(
            "h2",
            FixedProfile(10.0),
            FixedProfile(0.0),
            FixedProfile(0.0),
            Dict(H2 => 1.0),
        ),
        RefSource(
            "ch4",
            FixedProfile(90.0),
            FixedProfile(0.0),
            FixedProfile(0.0),
            Dict(CH4 => 1.0),
        ),
    ]
    blend =
        BlendingNode("blend", FixedProfile(100.0), FixedProfile(0.0), FixedProfile(0.0),
            Dict(H2 => 1.0, CH4 => 1.0), Dict(Blend => 1.0))
    deblend =
        DeblendNode("deblend", FixedProfile(10.0), FixedProfile(0.0), FixedProfile(0.0),
            Dict(Blend => 1.0), Dict(Blend => 1.0, H2 => 1.0), [DeblendData(0.5, 1.0)])
    transit =
        TransitNode("transit", FixedProfile(100.0), FixedProfile(0.0), FixedProfile(0.0),
            Dict(Blend => 1.0), Dict(Blend => 1.0))
    blend_sink = RefSink("blend_sink", FixedProfile(95.0),
        Dict(:surplus => FixedProfile(0.0), :deficit => FixedProfile(1e3)),
        Dict(Blend => 1.0))
    h2_sink = RefSink("h2_sink", FixedProfile(5.0),
        Dict(:surplus => FixedProfile(0.0), :deficit => FixedProfile(1e3)),
        Dict(H2 => 1.0))
    nodes = [sources..., blend, deblend, transit, blend_sink, h2_sink]
    links = [
        Direct("h2_blend", sources[1], blend, Linear()),
        Direct("ch4_blend", sources[2], blend, Linear()),
        Direct("blend_deblend", blend, deblend, Linear()),
        Direct("deblend_transit", deblend, transit, Linear()),
        Direct("transit_sink", transit, blend_sink, Linear()),
        Direct("deblend_h2", deblend, h2_sink, Linear()),
    ]
    case = topology_case(nodes, links, [CO2, Blend, H2, CH4])
    m = create_model(case, topology_model(CO2))
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)
    t = first(get_time_struct(case))

    @test termination_status(m) == MOI.OPTIMAL
    @test value(m[:flow_component][links[5], t, H2]) ≈ 5.0 atol = 1e-6
    @test value(m[:link_in][links[5], t, Blend]) ≈ 95.0 atol = 1e-6
end

@testitem "Blend topology - indirect mixed split provenance rejected" setup = [EMGNSetup] begin
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
    include("blend_topology_helpers.jl")

    H2, CH4, Blend, CO2 = topology_resources()
    source_h2 = RefSource("h2", FixedProfile(100.0), FixedProfile(0.0), FixedProfile(0.0),
        Dict(H2 => 1.0))
    source_ch4 =
        RefSource("ch4", FixedProfile(100.0), FixedProfile(0.0), FixedProfile(0.0),
            Dict(CH4 => 1.0))
    component = BlendingNode("component", FixedProfile(200.0), FixedProfile(0.0),
        FixedProfile(0.0), Dict(H2 => 1.0, CH4 => 1.0), Dict(Blend => 1.0))
    transit =
        TransitNode("transit", FixedProfile(200.0), FixedProfile(0.0), FixedProfile(0.0),
            Dict(Blend => 1.0), Dict(Blend => 1.0))
    sinks = [
        RefSink("sink_$i", FixedProfile(1.0),
            Dict(:surplus => FixedProfile(0.0), :deficit => FixedProfile(1e3)),
            Dict(Blend => 1.0)) for i ∈ 1:2
    ]
    nodes = [source_h2, source_ch4, component, transit, sinks...]
    links = [
        Direct("h2_component", source_h2, component, Linear()),
        Direct("ch4_component", source_ch4, component, Linear()),
        Direct("component_transit", component, transit, Linear()),
        Direct("transit_sink_1", transit, sinks[1], Linear()),
        Direct("transit_sink_2", transit, sinks[2], Linear()),
    ]
    case = topology_case(nodes, links, [CO2, Blend, H2, CH4])
    @test_throws ArgumentError create_model(case, topology_model(CO2))

    pool = PoolingNode("pool", FixedProfile(200.0), FixedProfile(0.0), FixedProfile(0.0),
        Dict(H2 => 1.0, CH4 => 1.0), Dict(Blend => 1.0))
    merge = TransitNode("merge", FixedProfile(400.0), FixedProfile(0.0), FixedProfile(0.0),
        Dict(Blend => 1.0), Dict(Blend => 1.0))
    mixed_nodes = [source_h2, source_ch4, component, pool, merge, sinks...]
    mixed_links = [
        Direct("h2_component", source_h2, component, Linear()),
        Direct("ch4_component", source_ch4, component, Linear()),
        Direct("h2_pool", source_h2, pool, Linear()),
        Direct("ch4_pool", source_ch4, pool, Linear()),
        Direct("component_merge", component, merge, Linear()),
        Direct("pool_merge", pool, merge, Linear()),
        Direct("merge_sink_1", merge, sinks[1], Linear()),
        Direct("merge_sink_2", merge, sinks[2], Linear()),
    ]
    @test_throws ArgumentError EMGN.validate_blend_topology(
        mixed_nodes,
        mixed_links,
        [Blend],
    )
end

@testitem "Blend topology - proportion-capable splits and cycles accepted" setup =
    [EMGNSetup] begin
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
    include("blend_topology_helpers.jl")

    H2, CH4, Blend, CO2 = topology_resources()
    sources = [
        RefSource(string(p.id), FixedProfile(100.0), FixedProfile(0.0),
            FixedProfile(0.0), Dict(p => 1.0)) for p ∈ (H2, CH4)
    ]
    pool = PoolingNode("pool", FixedProfile(200.0), FixedProfile(0.0), FixedProfile(0.0),
        Dict(H2 => 1.0, CH4 => 1.0), Dict(Blend => 1.0))
    transit_a = TransitNode("a", FixedProfile(200.0), FixedProfile(0.0), FixedProfile(0.0),
        Dict(Blend => 1.0), Dict(Blend => 1.0))
    transit_b = TransitNode("b", FixedProfile(200.0), FixedProfile(0.0), FixedProfile(0.0),
        Dict(Blend => 1.0), Dict(Blend => 1.0))
    sinks = [
        RefSink("sink_$i", FixedProfile(1.0),
            Dict(:surplus => FixedProfile(0.0), :deficit => FixedProfile(1e3)),
            Dict(Blend => 1.0)) for i ∈ 1:2
    ]
    nodes = [sources..., pool, transit_a, transit_b, sinks...]
    links = [
        Direct("h2_pool", sources[1], pool, Linear()),
        Direct("ch4_pool", sources[2], pool, Linear()),
        Direct("pool_a", pool, transit_a, Linear()),
        Direct("a_b", transit_a, transit_b, Linear()),
        Direct("b_a", transit_b, transit_a, Linear()),
        Direct("a_sink", transit_a, sinks[1], Linear()),
        Direct("b_sink", transit_b, sinks[2], Linear()),
    ]
    # Passthrough splits need `has_flow` on all outgoing links (one outflow per period)
    @test_throws ArgumentError EMGN.validate_blend_topology(nodes, links, [Blend])
    provenance = EMGN.validate_blend_topology(nodes, links, [Blend];
        switched_links = Set(links))
    @test provenance[Blend][pool] == EMGN._PROPORTION_CAPABLE
    @test provenance[Blend][transit_a] == EMGN._PROPORTION_CAPABLE
    @test provenance[Blend][transit_b] == EMGN._PROPORTION_CAPABLE

    pwa_link = CapDirect("pool_pwa", pool, sinks[1], Linear(), FixedProfile(200.0),
        [BlendLinkData(Blend, Dict(H2 => 2.016), 1.0, 0.0, Dict(CH4 => 16.04))])
    @test_nowarn EMGN.validate_blend_topology(
        [sources..., pool, sinks[1]], [links[1], links[2], pwa_link], [Blend])
end

@testitem "Blend topology - single-output component-flow paths" setup = [EMGNSetup] begin
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
    include("blend_topology_helpers.jl")

    H2, CH4, Blend, CO2 = topology_resources()
    sources = [
        RefSource(
            "h2",
            FixedProfile(20.0),
            FixedProfile(0.0),
            FixedProfile(0.0),
            Dict(H2 => 1.0),
        ),
        RefSource(
            "ch4",
            FixedProfile(80.0),
            FixedProfile(0.0),
            FixedProfile(0.0),
            Dict(CH4 => 1.0),
        ),
    ]
    blend =
        BlendingNode("blend", FixedProfile(100.0), FixedProfile(0.0), FixedProfile(0.0),
            Dict(H2 => 1.0, CH4 => 1.0), Dict(Blend => 1.0))
    transit =
        TransitNode("transit", FixedProfile(100.0), FixedProfile(0.0), FixedProfile(0.0),
            Dict(Blend => 1.0), Dict(Blend => 1.0),
            [blend_bounds(Blend, H2, CH4; min_h2 = 0.2, max_h2 = 0.2)])
    sink = RefSink("sink", FixedProfile(100.0),
        Dict(:surplus => FixedProfile(0.0), :deficit => FixedProfile(1e3)),
        Dict(Blend => 1.0))
    nodes = [sources..., blend, transit, sink]
    links = [
        Direct("h2_blend", sources[1], blend, Linear()),
        Direct("ch4_blend", sources[2], blend, Linear()),
        Direct("blend_transit", blend, transit, Linear()),
        Direct("transit_sink", transit, sink, Linear()),
    ]
    case = topology_case(nodes, links, [CO2, Blend, H2, CH4])
    m = create_model(case, topology_model(CO2))
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)
    t = first(get_time_struct(case))
    @test termination_status(m) == MOI.OPTIMAL
    @test value(m[:flow_component][links[4], t, H2]) ≈ 20.0 atol = 1e-6
    @test value(m[:link_in][links[4], t, Blend]) ≈ 100.0 atol = 1e-6
end

@testitem "Blend topology - composition is only tracked where needed" setup = [EMGNSetup] begin
    using .EMGNSetup
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using JuMP
    using MathOptInterface
    using Test
    using TimeStruct
    const EMB = EnergyModelsBase
    const EMGN = EnergyModelsGasNetworks
    const MOI = MathOptInterface
    include("blend_topology_helpers.jl")

    H2, CH4, Blend, CO2 = topology_resources()
    source(p, cap) = RefSource(string(p.id), FixedProfile(cap), FixedProfile(0.0),
        FixedProfile(0.0), Dict(p => 1.0))
    pool(id) = PoolingNode(id, FixedProfile(100.0), FixedProfile(0.0), FixedProfile(0.0),
        Dict(H2 => 1.0, CH4 => 1.0), Dict(Blend => 1.0))
    src_h2, src_ch4 = source(H2, 5.0), source(CH4, 5.0)
    pool_h2, pool_ch4 = pool("pool_h2"), pool("pool_ch4")
    merge = TransitNode("merge", FixedProfile(100.0), FixedProfile(0.0), FixedProfile(0.0),
        Dict(Blend => 1.0), Dict(Blend => 1.0))
    sink = RefSink("sink", FixedProfile(10.0),
        Dict(:surplus => FixedProfile(0.0), :deficit => FixedProfile(1e3)),
        Dict(Blend => 1.0), [blend_bounds(Blend, H2, CH4; max_h2 = 0.5)])
    nodes = [src_h2, src_ch4, pool_h2, pool_ch4, merge, sink]
    links = [
        Direct("h2_pool", src_h2, pool_h2, Linear()),
        Direct("ch4_pool", src_ch4, pool_ch4, Linear()),
        Direct("pool_h2_merge", pool_h2, merge, Linear()),
        Direct("pool_ch4_merge", pool_ch4, merge, Linear()),
        Direct("merge_sink", merge, sink, Linear()),
    ]

    # Only the pooling nodes track a share; the merge and the sink use component flows
    plan = EMGN.blend_share_plan(nodes, links, [Blend])
    @test Set(plan.share_nodes) == Set([pool_h2, pool_ch4])
    @test isempty(plan.copy_nodes[Blend])
    @test isempty(plan.pwa_reader)

    # A pure H₂ stream and a pure CH₄ stream mix at the merge. When the merge copied the
    # share of each upstream node, both could not flow at the same time.
    case = topology_case(nodes, links, [CO2, Blend, H2, CH4])
    m = create_model(case, topology_model(CO2))
    @test Set(axes(m[:proportion_out], 1)) == Set([pool_h2, pool_ch4])
    set_optimizer(m, EMGNSetup.scip_optimizer())
    optimize!(m)
    t = first(get_time_struct(case))
    @test termination_status(m) == MOI.OPTIMAL
    @test value(m[:flow_in][sink, t, Blend]) ≈ 10.0 atol = 1e-5
    @test value(m[:flow_component][links[5], t, H2]) ≈ 5.0 atol = 1e-5
end

@testitem "Blend topology - Weymouth pipes read the share at either end" setup =
    [EMGNSetup] begin
    using .EMGNSetup
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using JuMP
    using MathOptInterface
    using Test
    using TimeStruct
    const EMB = EnergyModelsBase
    const EMGN = EnergyModelsGasNetworks
    const MOI = MathOptInterface
    include("blend_topology_helpers.jl")

    H2, CH4, Blend, CO2 = topology_resources(; pressure = true)
    source(p, cost) = RefSource(string(p.id), FixedProfile(10.0), FixedProfile(cost),
        FixedProfile(0.0), Dict(p => 1.0), [FixPressureData(FixedProfile(100.0))])
    src_h2, src_ch4 = source(H2, 0.0), source(CH4, 1.0)
    mix = BlendingNode("mix", FixedProfile(100.0), FixedProfile(0.0), FixedProfile(0.0),
        Dict(H2 => 1.0, CH4 => 1.0), Dict(Blend => 1.0),
        [MaxPressureData(FixedProfile(100.0))])
    transit = TransitNode("transit", FixedProfile(100.0), FixedProfile(0.0),
        FixedProfile(0.0), Dict(Blend => 1.0), Dict(Blend => 1.0))
    pool = PoolingNode("pool", FixedProfile(100.0), FixedProfile(0.0), FixedProfile(0.0),
        Dict(Blend => 1.0), Dict(Blend => 1.0), [MaxPressureData(FixedProfile(100.0))])
    sinks = [
        RefSink("sink_$i", FixedProfile(5.0),
            Dict(:surplus => FixedProfile(0.0), :deficit => FixedProfile(1e3)),
            Dict(Blend => 1.0),
            [blend_bounds(Blend, H2, CH4; max_h2 = 0.2),
                MinPressureData(FixedProfile(40.0))]) for i ∈ 1:2
    ]
    pipe_data() = [PressureLinkData(0.24, 100.0, 40.0),
        BlendLinkData(Blend, Dict(H2 => 2.016), 0.2, 0.0, Dict(CH4 => 16.04))]
    cap(id, from, to, data = EMB.ExtensionData[]) =
        CapDirect(id, from, to, Linear(), FixedProfile(100.0), data)

    # mix → pipe → transit → pool → two sinks: the pipe is the only inflow of the path, so
    # the share of `pool` is the composition in the pipe
    pipe = cap("pipe", mix, transit, pipe_data())
    links = [cap("h2_mix", src_h2, mix), cap("ch4_mix", src_ch4, mix), pipe,
        cap("transit_pool", transit, pool),
        cap("pool_sink_1", pool, sinks[1]), cap("pool_sink_2", pool, sinks[2])]
    nodes = [src_h2, src_ch4, mix, transit, pool, sinks...]
    plan = EMGN.blend_share_plan(nodes, links, [Blend])
    @test plan.pwa_reader[(pipe, Blend)] === pool
    @test Set(plan.share_nodes) == Set([pool])

    EMGNSetup.setup_pwa!()
    case = topology_case(nodes, links, [CO2, Blend, H2, CH4])
    m = create_model(case, topology_model(CO2))
    @test Set(axes(m[:proportion_out], 1)) == Set([pool])
    set_optimizer(m, EMGNSetup.scip_optimizer())
    optimize!(m)
    t = first(get_time_struct(case))
    @test termination_status(m) == MOI.OPTIMAL
    flow = value(m[:link_in][pipe, t, Blend])
    @test flow ≈ 10.0 atol = 1e-4
    # The cheap H₂ fills the 20 % limit, and the share of `pool` is the one in the pipe
    @test value(m[:flow_component][pipe, t, H2]) ≈ 2.0 atol = 1e-4
    @test value(m[:proportion_out][pool, t, H2]) ≈ 0.2 atol = 1e-4

    # Another inflow at the pooling node mixes in other gas: no end provides the share
    mix_2 = BlendingNode("mix_2", FixedProfile(100.0), FixedProfile(0.0),
        FixedProfile(0.0), Dict(H2 => 1.0, CH4 => 1.0), Dict(Blend => 1.0))
    extra = [cap("ch4_mix_2", src_ch4, mix_2), cap("extra", mix_2, pool)]
    err = try
        EMGN.blend_share_plan(vcat(nodes, mix_2), vcat(links, extra), [Blend])
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("neither end", err.msg)

    # A pooling node at the inflow end is used directly
    pool_up = PoolingNode("pool_up", FixedProfile(100.0), FixedProfile(0.0),
        FixedProfile(0.0), Dict(H2 => 1.0, CH4 => 1.0), Dict(Blend => 1.0))
    pipe_up = cap("pipe_up", pool_up, transit, pipe_data())
    plan = EMGN.blend_share_plan([src_h2, src_ch4, pool_up, transit, pool, sinks...],
        [cap("h2_up", src_h2, pool_up), cap("ch4_up", src_ch4, pool_up), pipe_up,
            links[4:end]...], [Blend])
    @test plan.pwa_reader[(pipe_up, Blend)] === pool_up

    # Gas from a pooling node passing a TransitNode before the pipe: the exact downstream
    # share is preferred over copying it forward through the TransitNode
    before = TransitNode("before", FixedProfile(100.0), FixedProfile(0.0),
        FixedProfile(0.0), Dict(Blend => 1.0), Dict(Blend => 1.0))
    pipe_mid = cap("pipe_mid", before, transit, pipe_data())
    nodes_mid = [src_h2, src_ch4, pool_up, before, transit, pool, sinks...]
    links_mid = [cap("h2_up", src_h2, pool_up), cap("ch4_up", src_ch4, pool_up),
        cap("up_before", pool_up, before), pipe_mid, links[4:end]...]
    plan = EMGN.blend_share_plan(nodes_mid, links_mid, [Blend])
    @test plan.pwa_reader[(pipe_mid, Blend)] === pool
    @test isempty(plan.copy_nodes[Blend])
    # Without the downstream pooling node, the TransitNode copies the share
    links_fwd = [links_mid[1:3]..., cap("pipe_fwd", before, sinks[1], pipe_data())]
    plan = EMGN.blend_share_plan([src_h2, src_ch4, pool_up, before, sinks[1]], links_fwd,
        [Blend])
    @test plan.pwa_reader[(links_fwd[4], Blend)] === before
    @test plan.copy_nodes[Blend] == Set([before])
end

@testitem "Blend topology - passthrough splits need no share" setup = [EMGNSetup] begin
    using .EMGNSetup
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using Test
    using TimeStruct
    const EMB = EnergyModelsBase
    const EMGN = EnergyModelsGasNetworks
    include("blend_topology_helpers.jl")

    # A BlendingNode feeding a TransitNode with two switched outflows: only one carries
    # flow in each period, so its composition is that of the inflow
    H2, CH4, Blend, CO2 = topology_resources()
    mix = BlendingNode("mix", FixedProfile(100.0), FixedProfile(0.0), FixedProfile(0.0),
        Dict(H2 => 1.0, CH4 => 1.0), Dict(Blend => 1.0))
    transit = TransitNode("transit", FixedProfile(100.0), FixedProfile(0.0),
        FixedProfile(0.0), Dict(Blend => 1.0), Dict(Blend => 1.0))
    sinks = [
        RefSink("sink_$i", FixedProfile(1.0),
            Dict(:surplus => FixedProfile(0.0), :deficit => FixedProfile(1e3)),
            Dict(Blend => 1.0)) for i ∈ 1:2
    ]
    links = [Direct("mix_transit", mix, transit, Linear()),
        Direct("transit_1", transit, sinks[1], Linear()),
        Direct("transit_2", transit, sinks[2], Linear())]
    nodes = [mix, transit, sinks...]
    @test_throws ArgumentError EMGN.validate_blend_topology(nodes, links, [Blend])
    prov = EMGN.validate_blend_topology(nodes, links, [Blend]; switched_links = Set(links))
    @test prov[Blend][transit] == EMGN._COMPONENT_FLOW_ONLY
    @test isempty(EMGN.blend_share_plan(nodes, links, [Blend]).share_nodes)
end
