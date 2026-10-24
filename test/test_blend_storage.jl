@testitem "Blend storage - data constructor and accessors" setup = [EMGNSetup] begin
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
    include("blend_storage_helpers.jl")
    EMGNSetup.setup_pwa!()

    H2, CH4, Blend, CO2 = BS_RES

    # No physical default: the mode must be given unless a profile is
    @test_throws UndefKeywordError BlendStorageData(Blend)
    @test_throws ArgumentError BlendStorageData(Blend; mode = :exact)
    @test_throws ArgumentError BlendStorageData(Blend; mode = :prescribed)
    @test_throws ArgumentError BlendStorageData(Blend; mode = :relaxed,
        discharge_composition = Dict(H2 => 0.1, CH4 => 0.9))

    for mode ∈ (:relaxed, :fully_mixed)
        data = BlendStorageData(Blend; mode)
        @test get_storage_mode(data) == mode
        @test isnothing(data.discharge_composition)
    end

    data = BlendStorageData(Blend, Dict(H2 => 0.1, CH4 => OperationalProfile([0.9, 0.8])))
    @test get_storage_mode(data) == :prescribed
    @test discharge_composition(data, H2) == FixedProfile(0.1)
    T = SimpleTimes(2, 1)
    @test discharge_composition(data, CH4, last(collect(T))) == 0.8

    case, model, nodes, links = make_blend_storage_case(; storage_data = [data])
    @test get_blendstoragedata(nodes[4]) === data
    @test isnothing(get_blendstoragedata(nodes[3]))
end

@testitem "Blend storage - relaxed component balance" setup = [EMGNSetup] begin
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
    include("blend_storage_helpers.jl")
    EMGNSetup.setup_pwa!()

    H2, CH4, Blend, CO2 = BS_RES
    case, model, nodes, links = make_blend_storage_case(; mode = :relaxed)
    m = solve_blend_storage(case, model)
    @test termination_status(m) == MOI.OPTIMAL

    𝒯 = get_time_struct(case)
    t_sum, t_win = collect(𝒯)
    stor, sink = nodes[4], nodes[5]
    Δ = m[:stor_level_component_Δ_op]

    # Summer charge is discharged in winter, component by component
    @test value(m[:flow_in][sink, t_win, Blend]) ≈ 100.0 atol = 1e-5
    @test value(Δ[stor, t_sum, H2]) ≈ 10.0 atol = 1e-5
    @test value(Δ[stor, t_sum, CH4]) ≈ 90.0 atol = 1e-5
    @test value(Δ[stor, t_win, H2]) ≈ -10.0 atol = 1e-5
    @test value(Δ[stor, t_win, CH4]) ≈ -90.0 atol = 1e-5
    @test check_component_levels(m, stor, 𝒯, [H2, CH4])

    # Relaxed storages do not get a shared composition
    @test stor ∉ axes(m[:proportion_out], 1)
end

@testitem "Blend storage - discharged H2 is bounded by stored H2" setup = [EMGNSetup] begin
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
    include("blend_storage_helpers.jl")
    EMGNSetup.setup_pwa!()

    H2, CH4, Blend, CO2 = BS_RES
    𝒯 = nothing

    # The sink needs at least 50 % H2. Only 10 units of H2 are available, so at most 20
    # units can be delivered. Without component inventories, the composition of the
    # discharged gas was free and all 100 units could be delivered.
    for (mode, opt) ∈ ((:relaxed, EMGNSetup.mip_optimizer()),
        (:fully_mixed, EMGNSetup.scip_optimizer()))
        case, model, nodes, links = make_blend_storage_case(; mode, min_h2 = 0.5)
        m = solve_blend_storage(case, model; optimizer = opt)
        @test termination_status(m) == MOI.OPTIMAL
        𝒯 = get_time_struct(case)
        stor, sink = nodes[4], nodes[5]
        t_win = last(collect(𝒯))
        @test value(m[:flow_in][sink, t_win, Blend]) ≈ 20.0 atol = 1e-4
        @test bs_total(m, [links[4]], 𝒯, H2) ≤ bs_total(m, [links[3]], 𝒯, H2) + 1e-5
        @test check_component_levels(m, stor, 𝒯, [H2, CH4])
    end
end

@testitem "Blend storage - CH4-only charge gives no H2 on discharge" setup = [EMGNSetup] begin
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
    include("blend_storage_helpers.jl")
    EMGNSetup.setup_pwa!()

    H2, CH4, Blend, CO2 = BS_RES

    # Regression for a storage that stored blend without component balance and reported
    # an H₂ share of 1 in the discharged gas.
    data_sets = (
        [BlendStorageData(Blend; mode = :relaxed)],
        [BlendStorageData(Blend; mode = :fully_mixed)],
        [BlendStorageData(Blend, Dict(H2 => 0.0, CH4 => 1.0))],
    )
    for data ∈ data_sets
        opt =
            get_storage_mode(only(data)) == :fully_mixed ?
            EMGNSetup.scip_optimizer() : EMGNSetup.mip_optimizer()
        case, model, nodes, links = make_blend_storage_case(;
            storage_data = data, h2 = FixedProfile(0.0), h2_cost = -10.0)
        m = solve_blend_storage(case, model; optimizer = opt)
        @test termination_status(m) == MOI.OPTIMAL
        𝒯 = get_time_struct(case)
        t_win = last(collect(𝒯))
        @test value(m[:flow_component][links[4], t_win, H2]) ≈ 0.0 atol = 1e-6
        @test value(m[:flow_component][links[4], t_win, CH4]) ≈ 90.0 atol = 1e-5
    end

    # A sink that needs H₂ gets nothing
    case, model, nodes, links = make_blend_storage_case(;
        mode = :relaxed, h2 = FixedProfile(0.0), min_h2 = 0.1)
    m = solve_blend_storage(case, model)
    @test termination_status(m) == MOI.OPTIMAL
    @test value(m[:flow_in][nodes[5], last(collect(get_time_struct(case))), Blend]) ≈ 0.0 atol =
        1e-6
end

@testitem "Blend storage - prescribed discharge composition" setup = [EMGNSetup] begin
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
    include("blend_storage_helpers.jl")
    EMGNSetup.setup_pwa!()

    H2, CH4, Blend, CO2 = BS_RES

    # 30 % H₂ in the discharge and 10 units of H₂: at most 33.3 units can be delivered,
    # and the cyclic storage only charges the CH₄ it can discharge.
    data = BlendStorageData(Blend, Dict(H2 => 0.3, CH4 => 0.7))
    case, model, nodes, links = make_blend_storage_case(; storage_data = [data])
    m = solve_blend_storage(case, model)
    @test termination_status(m) == MOI.OPTIMAL
    𝒯 = get_time_struct(case)
    t_sum, t_win = collect(𝒯)
    stor, sink = nodes[4], nodes[5]
    @test value(m[:flow_in][sink, t_win, Blend]) ≈ 100 / 3 atol = 1e-4
    @test value(m[:flow_component][links[4], t_win, H2]) ≈ 10.0 atol = 1e-4
    @test value(m[:flow_component][links[3], t_sum, CH4]) ≈ 70 / 3 atol = 1e-4
    @test all(value(m[:proportion_out][stor, t, H2]) ≈ 0.3 for t ∈ 𝒯)
    @test check_component_levels(m, stor, 𝒯, [H2, CH4])

    # A time-varying profile in a discharge over two periods
    data = BlendStorageData(Blend,
        Dict(H2 => OperationalProfile([0.0, 0.0, 0.2]),
            CH4 => OperationalProfile([1.0, 1.0, 0.8])))
    case, model, nodes, links = make_blend_storage_case(; storage_data = [data],
        h2 = OperationalProfile([10.0, 0.0, 0.0]),
        ch4 = OperationalProfile([90.0, 0.0, 0.0]),
        demand = OperationalProfile([0.0, 50.0, 50.0]),
        T = TwoLevel(1, 1, SimpleTimes(3, 1); op_per_strat = 3))
    m = solve_blend_storage(case, model)
    @test termination_status(m) == MOI.OPTIMAL
    𝒯 = get_time_struct(case)
    _, t2, t3 = collect(𝒯)
    @test value(m[:flow_component][links[4], t2, H2]) ≈ 0.0 atol = 1e-6
    @test value(m[:flow_component][links[4], t3, H2]) ≈ 10.0 atol = 1e-5
    @test value(m[:flow_in][nodes[5], t3, Blend]) ≈ 50.0 atol = 1e-5
end

@testitem "Blend storage - fully mixed composition" setup = [EMGNSetup] begin
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
    include("blend_storage_helpers.jl")
    EMGNSetup.setup_pwa!()

    H2, CH4, Blend, CO2 = BS_RES

    # CH₄ is charged in the first period, the H₂-rich gas in the second, and the gas is
    # discharged in the third and fourth period. With full mixing, the discharged gas has the
    # composition of the stored gas.
    case, model, nodes, links = make_blend_storage_case(; mode = :fully_mixed,
        h2 = OperationalProfile([0.0, 10.0, 0.0, 0.0]),
        ch4 = OperationalProfile([50.0, 40.0, 0.0, 0.0]),
        demand = OperationalProfile([0.0, 0.0, 50.0, 50.0]),
        h2_cost = -10.0,
        T = TwoLevel(1, 1, SimpleTimes(4, 1); op_per_strat = 4))
    m = solve_blend_storage(case, model; optimizer = EMGNSetup.scip_optimizer())
    @test termination_status(m) == MOI.OPTIMAL
    𝒯 = get_time_struct(case)
    stor = nodes[4]
    prop = m[:proportion_out]
    lvl = m[:stor_level_component]
    for t ∈ 𝒯, p ∈ (H2, CH4)
        level = value(m[:stor_level][stor, t])
        level > 1e-4 || continue
        @test value(prop[stor, t, p]) ≈ value(lvl[stor, t, p]) / level atol = 1e-5
    end
    for t ∈ collect(𝒯)[3:4]
        flow = value(m[:link_in][links[4], t, Blend])
        @test value(m[:flow_component][links[4], t, H2]) ≈
              value(prop[stor, t, H2]) * flow atol = 1e-5
    end
    @test check_component_levels(m, stor, 𝒯, [H2, CH4])
    @test bs_total(m, [links[4]], 𝒯, H2) ≈ 10.0 atol = 1e-4
end

@testitem "Blend storage - time structures and storage behaviours" setup = [EMGNSetup] begin
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
    include("blend_storage_helpers.jl")
    EMGNSetup.setup_pwa!()

    H2, CH4, Blend, CO2 = BS_RES

    # Representative periods: summer charges, winter discharges. Only CyclicStrategic can
    # move gas between representative periods.
    T_rp = TwoLevel(1, 1,
        RepresentativePeriods(2, 4, [0.5, 0.5], [SimpleTimes(2, 1), SimpleTimes(2, 1)]))
    rp_profiles = (
        h2 = RepresentativeProfile([FixedProfile(10.0), FixedProfile(0.0)]),
        ch4 = RepresentativeProfile([FixedProfile(90.0), FixedProfile(0.0)]),
        demand = RepresentativeProfile([FixedProfile(0.0), FixedProfile(100.0)]),
    )
    T_sc = TwoLevel(1, 1,
        OperationalScenarios(2, [SimpleTimes(2, 1), SimpleTimes(2, 1)], [0.5, 0.5]))
    T_sp = TwoLevel(2, 1, SimpleTimes(2, 1); op_per_strat = 2)

    cases = [
        # (behaviour, T, profiles, delivered gas over all periods)
        (CyclicStrategic, T_rp, rp_profiles, 200.0),
        (CyclicRepresentative, T_rp, rp_profiles, 0.0),
        (CyclicStrategic, T_sc, (;), 200.0),
        (CyclicRepresentative, T_sc, (;), 200.0),
        (CyclicStrategic, T_sp, (;), 200.0),
    ]
    for (behaviour, T, profiles, delivered) ∈ cases,
        data ∈ ([BlendStorageData(Blend; mode = :relaxed)],
            [BlendStorageData(Blend, Dict(H2 => 0.1, CH4 => 0.9))])

        case, model, nodes, links =
            make_blend_storage_case(; storage_data = data, behaviour, T, profiles...)
        m = solve_blend_storage(case, model)
        @test termination_status(m) == MOI.OPTIMAL
        𝒯 = get_time_struct(case)
        stor = nodes[4]
        @test check_component_levels(m, stor, 𝒯, [H2, CH4])
        out = sum(value(m[:link_in][links[4], t, Blend]) for t ∈ 𝒯)
        @test out ≈ delivered atol = 1e-4
        # Cyclic storage: each component is discharged as it is charged
        for p ∈ (H2, CH4)
            @test bs_total(m, [links[4]], 𝒯, p) ≈ bs_total(m, [links[3]], 𝒯, p) atol = 1e-4
        end
    end
end

@testitem "Blend storage - rejected configurations" setup = [EMGNSetup] begin
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
    include("blend_storage_helpers.jl")
    EMGNSetup.setup_pwa!()

    H2, CH4, Blend, CO2 = BS_RES

    # Blend storage without BlendStorageData
    case, model, _, _ = make_blend_storage_case(; storage_data = ExtensionData[])
    err = try
        create_model(case, model)
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("BlendStorageData", err.msg)

    # A relaxed storage has no shared composition and can not feed two links
    case, model, _, _ = make_blend_storage_case(; mode = :relaxed, n_storage_outlets = 2)
    @test_throws ArgumentError create_model(case, model)

    # A prescribed composition can be shared
    data = [BlendStorageData(Blend, Dict(H2 => 0.1, CH4 => 0.9))]
    case, model, _, _ =
        make_blend_storage_case(; storage_data = data, n_storage_outlets = 2)
    m = solve_blend_storage(case, model)
    @test termination_status(m) == MOI.OPTIMAL

    # Invalid data, caught by the checks
    bad_cases = [
        # Raw H₂ input on the storage
        (; mode = :relaxed, stor_inputs = Dict(Blend => 1, H2 => 0.1)),
        # Not a cyclic storage
        (; mode = :relaxed, behaviour = AccumulatingEmissions),
        # Composition does not sum to 1
        (; storage_data = [BlendStorageData(Blend, Dict(H2 => 0.2, CH4 => 0.9))]),
        # Composition outside [0, 1]
        (; storage_data = [BlendStorageData(Blend, Dict(H2 => -0.1, CH4 => 1.1))]),
        # Composition missing a sub-resource
        (; storage_data = [BlendStorageData(Blend, Dict(H2 => 1.0))]),
        # Two BlendStorageData
        (;
            storage_data = [BlendStorageData(Blend; mode = :relaxed),
                BlendStorageData(Blend; mode = :fully_mixed)]
        ),
    ]
    for kwargs ∈ bad_cases
        case, model, _, _ = make_blend_storage_case(; kwargs...)
        @test_throws AssertionError create_model(case, model)
    end

    # BlendStorageData for another blend than the stored one
    Other = ResourcePooling("Other", [H2, CH4])
    case, model, _, _ = make_blend_storage_case(;
        storage_data = [BlendStorageData(Other; mode = :relaxed)])
    @test_throws AssertionError create_model(case, model)
end

@testitem "Blend storage - investment in storage level" setup = [EMGNSetup] begin
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
    include("blend_storage_helpers.jl")
    EMGNSetup.setup_pwa!()

    using EnergyModelsInvestments
    H2, CH4, Blend, CO2 = BS_RES

    inv = StorageInvData(
        level = NoStartInvData(FixedProfile(1.0), FixedProfile(1000.0),
            ContinuousInvestment(FixedProfile(0.0), FixedProfile(1000.0)),
            UnlimitedLife()),
    )
    model = InvestmentModel(
        Dict(CO2 => FixedProfile(0.0)), Dict(CO2 => FixedProfile(0.0)), CO2, 0.05)
    case, model, nodes, links = make_blend_storage_case(; mode = :relaxed, model,
        level_cap = FixedProfile(0.0), stor_extra_data = [inv])
    m = solve_blend_storage(case, model)
    @test termination_status(m) == MOI.OPTIMAL
    𝒯 = get_time_struct(case)
    stor = nodes[4]
    @test value(m[:stor_level_inst][stor, first(collect(𝒯))]) ≥ 100.0 - 1e-4
    @test value(m[:flow_in][nodes[5], last(collect(𝒯)), Blend]) ≈ 100.0 atol = 1e-4
    @test check_component_levels(m, stor, 𝒯, [H2, CH4])
end

@testitem "Blend storage - topology with composition-dependent links" setup = [EMGNSetup] begin
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
    include("blend_storage_helpers.jl")
    EMGNSetup.setup_pwa!()

    H2, CH4, Blend, CO2 = BS_RES
    sink = RefSink("sink", FixedProfile(1.0),
        Dict(:surplus => FixedProfile(0.0), :deficit => FixedProfile(1e3)),
        Dict(Blend => 1.0))
    mix = BlendingNode("mix", FixedProfile(100.0), FixedProfile(0.0), FixedProfile(0.0),
        Dict(H2 => 1.0, CH4 => 1.0), Dict(Blend => 1.0))
    function storage(data)
        return RefStorage{CyclicStrategic}("stor",
            StorCapOpex(FixedProfile(100), FixedProfile(0), FixedProfile(0)),
            StorCap(FixedProfile(100)), Blend, Dict(Blend => 1), Dict(Blend => 1), data)
    end
    link_data = [PressureLinkData(0.24, 100.0, 40.0),
        BlendLinkData(Blend, Dict(H2 => 2.016), 1.0, 0.0, Dict(CH4 => 16.04))]

    for (data, ok) ∈ (
        (BlendStorageData(Blend; mode = :relaxed), false),
        (BlendStorageData(Blend; mode = :fully_mixed), true),
        (BlendStorageData(Blend, Dict(H2 => 0.1, CH4 => 0.9)), true),
    )
        stor = storage([data])
        links = [Direct("charge", mix, stor, Linear()),
            CapDirect("pwa", stor, sink, Linear(), FixedProfile(100.0), link_data)]
        if ok
            prov = EMGN.validate_blend_topology([mix, stor, sink], links, [Blend])
            @test prov[Blend][stor] == EMGN._PROPORTION_CAPABLE
        else
            @test_throws ArgumentError EMGN.validate_blend_topology(
                [mix, stor, sink], links, [Blend])
        end
    end
end
