@testmodule DPNPressureCase begin
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using TimeStruct

    """
        dpn_pressure_case(; method = :bigm, n_points = 5, h2_cost = 0.0)

    Two sources at 100 bar feed a `DiscretizedPoolingNode` that splits the blend over two
    Weymouth pipes to sinks requiring at least 60 bar and at most 10 % H₂. The pipes have
    `PressureLinkData` but no `BlendLinkData`, so they use the pure-component Taylor cuts.
    A negative `h2_cost` rewards blending H₂.
    """
    function dpn_pressure_case(; method = :bigm, n_points = 5, h2_cost = 0.0)
        H2 = ResourcePressure("H2", 0.0)
        CH4 = ResourcePressure("CH4", 0.0)
        Blend = ResourcePooling("Blend", [H2, CH4])
        CO2 = ResourceEmit("CO2", 1.0)
        T = TwoLevel(1, 1, SimpleTimes(1, 1); op_per_strat = 1)
        quality(max_h2) = RefBlendData{ResourcePressure{Float64}}(Blend,
            Dict(H2 => max_h2, CH4 => 1.0), Dict(H2 => 0.0, CH4 => 0.0))
        src_h2 = RefSource("src_h2", FixedProfile(10), FixedProfile(h2_cost),
            FixedProfile(0), Dict(H2 => 1), [FixPressureData(FixedProfile(100))])
        src_ch4 = RefSource("src_ch4", FixedProfile(100), FixedProfile(0), FixedProfile(0),
            Dict(CH4 => 1), [FixPressureData(FixedProfile(100))])
        pool = DiscretizedPoolingNode("pool", FixedProfile(200), FixedProfile(0),
            FixedProfile(0), Dict(H2 => 1, CH4 => 1), Dict(Blend => 1),
            [DiscretizationData(n_points, method, 0.2), MaxPressureData(FixedProfile(100))])
        sinks = [
            RefSink("sink_$i", FixedProfile(0),
                Dict(:surplus => FixedProfile(-10), :deficit => FixedProfile(10)),
                Dict(Blend => 1), [quality(0.1), MinPressureData(FixedProfile(60))])
            for i ∈ 1:2
        ]
        pipe(id, to) = CapDirect(id, pool, to, Linear(), FixedProfile(30),
            [PressureLinkData(0.24, 100.0, 60.0)])
        links = EnergyModelsBase.Link[
            Direct("h2_pool", src_h2, pool), Direct("ch4_pool", src_ch4, pool),
            pipe("pipe_1", sinks[1]), pipe("pipe_2", sinks[2]),
        ]
        case = Case(T, [CO2, Blend, H2, CH4], [[src_h2, src_ch4, pool, sinks...], links],
            [[get_nodes, get_links]])
        model = OperationalModel(Dict(CO2 => FixedProfile(0)),
            Dict(CO2 => FixedProfile(0)), CO2)
        return case, model, (; H2, CH4, Blend, pool, sinks, pipes = links[3:4])
    end
end

@testitem "DiscretizedPoolingNode - pressure coupling and shared composition" setup =
    [EMGNSetup, DPNPressureCase] begin
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using JuMP
    using MathOptInterface
    const MOI = MathOptInterface

    @testset "$method" for method ∈ (:bigm, :pwl)
        case, model, r = DPNPressureCase.dpn_pressure_case(; method, h2_cost = -1.0)
        m = create_model(case, model)
        set_optimizer(m, EMGNSetup.mip_optimizer())
        optimize!(m)
        @test termination_status(m) == MOI.OPTIMAL
        # 2 × 30 delivered at 10/unit, plus 2 × 3 H₂ at a reward of 1/unit
        @test objective_value(m) ≈ 606 rtol = 1e-6

        t = first(get_time_struct(case))
        p_pool = value(m[:potential_out][r.pool, t, r.Blend])
        @test p_pool ≤ 100 + 1e-6
        prop = value(m[:proportion_out][r.pool, t, r.H2])
        @test prop ≈ 0.1 atol = 1e-6   # a grid level (step 0.05) at the quality limit
        for l ∈ r.pipes
            flow = value(m[:link_in][l, t, r.Blend])
            @test flow ≈ 30 atol = 1e-6
            # Both outlets share the pool composition
            @test value(m[:flow_component][l, t, r.H2]) ≈ prop * flow atol = 1e-6
            # The pipe inlet is at the pool pressure, the outlet at the sink minimum
            p_in = value(m[:link_potential_in][l, t, r.Blend])
            p_out = value(m[:link_potential_out][l, t, r.Blend])
            @test p_in ≈ p_pool atol = 1e-6
            @test p_out ≥ 60 - 1e-6
            # Pure-component Taylor cuts: the flow never exceeds the exact Weymouth flow
            @test flow ≤ sqrt(0.24 * (p_in^2 - p_out^2)) + 1e-4
        end
    end
end

@testitem "DiscretizedPoolingNode - quality limit between grid levels" setup =
    [EMGNSetup, DPNPressureCase] begin
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using JuMP
    using MathOptInterface
    const MOI = MathOptInterface

    # n_points = 4 gives the levels 0, 0.0667, 0.1333, 0.2. The 10 % limit lies between
    # two levels, so the pool must settle on 0.0667.
    case, model, r = DPNPressureCase.dpn_pressure_case(; n_points = 4, h2_cost = -1.0)
    m = create_model(case, model)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)
    @test termination_status(m) == MOI.OPTIMAL
    t = first(get_time_struct(case))
    @test value(m[:proportion_out][r.pool, t, r.H2]) ≈ 0.2 / 3 atol = 1e-6
    for l ∈ r.pipes
        @test value(m[:flow_component][l, t, r.H2]) ≈ 2.0 atol = 1e-6
    end
end

@testitem "Blend pipe without BlendLinkData needs no PWA optimizer" setup =
    [DPNPressureCase] begin
    using EnergyModelsBase
    using EnergyModelsGasNetworks
    using JuMP
    const EMGN = EnergyModelsGasNetworks

    # The Taylor fallback does not fit a PWA, so model creation must not require the PWA
    # optimizer (it used to fail with "optimizer not set" unless an earlier model had set it).
    previous = EMGN._OPT[]
    EMGN._OPT[] = nothing
    try
        case, model, r = DPNPressureCase.dpn_pressure_case()
        m = create_model(case, model)
        @test m isa JuMP.Model
        @test num_constraints(m; count_variable_in_set_constraints = false) > 0
    finally
        EMGN._OPT[] = previous
    end
end
