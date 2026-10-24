@testmodule ZeroDropCase begin
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using TimeStruct

    """
        zero_drop_case(; antiparallel = false)

    `src` (100 bar) ─ZeroDrop→ `hub` ─Weymouth pipe→ `sink` (≥ 60 bar, demand 20).
    With `antiparallel = true`, `hub` is also connected to `hub2` by two opposite
    `ZeroDrop` links.
    """
    function zero_drop_case(; antiparallel = false)
        NG = ResourcePressure("NG", 0.0)
        CO2 = ResourceEmit("CO2", 1.0)
        T = TwoLevel(1, 1, SimpleTimes(2, 1); op_per_strat = 2)
        src = RefSource("src", FixedProfile(50), FixedProfile(1), FixedProfile(0),
            Dict(NG => 1), [FixPressureData(FixedProfile(100))])
        hub = RefNetworkNode("hub", FixedProfile(100), FixedProfile(0), FixedProfile(0),
            Dict(NG => 1), Dict(NG => 1), ExtensionData[])
        sink = RefSink("sink", FixedProfile(20),
            Dict(:surplus => FixedProfile(0), :deficit => FixedProfile(1e3)),
            Dict(NG => 1), [MinPressureData(FixedProfile(60))])
        nodes = EnergyModelsBase.Node[src, hub, sink]
        links = EnergyModelsBase.Link[
            ZeroDrop("src_hub", src, hub),
            CapDirect("hub_sink", hub, sink, Linear(), FixedProfile(100),
                [PressureLinkData(0.24, 100.0, 60.0)]),
        ]
        if antiparallel
            hub2 = RefNetworkNode("hub2", FixedProfile(100), FixedProfile(0),
                FixedProfile(0), Dict(NG => 1), Dict(NG => 1), ExtensionData[])
            push!(nodes, hub2)
            append!(links, [ZeroDrop("fwd", hub, hub2), ZeroDrop("rev", hub2, hub)])
        end
        case = Case(T, [NG, CO2], [nodes, links], [[get_nodes, get_links]])
        model = OperationalModel(Dict(CO2 => FixedProfile(0)),
            Dict(CO2 => FixedProfile(0)), CO2)
        return case, model, NG
    end
end

@testitem "ZeroDrop - constructor and display" setup = [ZeroDropCase] begin
    using EnergyModelsBase

    case, _, NG = ZeroDropCase.zero_drop_case()
    z = first(get_links(case))
    @test z isa ZeroDrop
    @test z.formulation isa Linear
    @test string(z) == "l_src_hub"
    @test NG ∈ EnergyModelsBase.link_res(z)
end

@testitem "ZeroDrop - equal pressures and flow balance while flowing" setup =
    [EMGNSetup, ZeroDropCase] begin
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using JuMP
    using MathOptInterface
    const MOI = MathOptInterface

    case, model, NG = ZeroDropCase.zero_drop_case()
    m = create_model(case, model)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)
    @test termination_status(m) == MOI.OPTIMAL

    z, pipe = get_links(case)
    sink = get_nodes(case)[3]
    for t ∈ get_time_struct(case)
        @test value(m[:link_in][z, t, NG]) ≈ 20
        @test value(m[:link_out][z, t, NG]) ≈ value(m[:link_in][z, t, NG])
        @test value(m[:has_flow][z, t]) ≈ 1
        # No pressure drop: the hub sees the source pressure
        @test value(m[:link_potential_in][z, t, NG]) ≈ 100
        @test value(m[:link_potential_out][z, t, NG]) ≈ 100
        @test value(m[:sink_deficit][sink, t]) ≈ 0 atol = 1e-6
        # The Weymouth pipe still limits the flow downstream
        p_in = value(m[:link_potential_in][pipe, t, NG])
        p_out = value(m[:link_potential_out][pipe, t, NG])
        @test value(m[:link_in][pipe, t, NG]) ≤ sqrt(0.24 * (p_in^2 - p_out^2)) + 1e-4
    end
end

@testitem "ZeroDrop - switched off link carries no flow" setup = [EMGNSetup, ZeroDropCase] begin
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using JuMP
    using MathOptInterface
    const MOI = MathOptInterface

    case, model, NG = ZeroDropCase.zero_drop_case()
    m = create_model(case, model)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    z = first(get_links(case))
    sink = get_nodes(case)[3]
    for t ∈ get_time_struct(case)
        fix(m[:has_flow][z, t], 0; force = true)
    end
    optimize!(m)
    # The big-M relaxation keeps the model feasible: no flow, unmet demand
    @test termination_status(m) == MOI.OPTIMAL
    for t ∈ get_time_struct(case)
        @test value(m[:link_in][z, t, NG]) ≈ 0 atol = 1e-6
        @test value(m[:sink_deficit][sink, t]) ≈ 20
    end
end

@testitem "ZeroDrop - anti-parallel pair carries flow in one direction" setup =
    [EMGNSetup, ZeroDropCase] begin
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using JuMP
    using MathOptInterface
    const MOI = MathOptInterface

    case, model, _ = ZeroDropCase.zero_drop_case(; antiparallel = true)
    m = create_model(case, model)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    fwd, rev = get_links(case)[3:4]
    t = first(get_time_struct(case))

    fix(m[:has_flow][fwd, t], 1; force = true)
    fix(m[:has_flow][rev, t], 1; force = true)
    optimize!(m)
    @test termination_status(m) == MOI.INFEASIBLE

    unfix(m[:has_flow][rev, t])
    optimize!(m)
    @test termination_status(m) == MOI.OPTIMAL
    @test value(m[:has_flow][rev, t]) ≈ 0 atol = 1e-6
end
