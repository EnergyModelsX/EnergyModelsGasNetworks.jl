@testitem "Pressure propagation through PoolingNode junction" setup = [EMGNSetup] begin
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

    function generate_case_pressure_propagation()
        H2 = ResourcePressure("H2", 1.0)
        CH4 = ResourcePressure("CH4", 1.0)
        Blend = ResourcePooling("Blend", [H2, CH4])
        CO2 = ResourceEmit("CO2", 1.0)
        products = [CO2, Blend, H2, CH4]
        T = TwoLevel(1, 1, TimeStruct.SimpleTimes(1, 1); op_per_strat = 1)
        P_supply = 200.0
        P_entry = 150.0
        P_sink = 80.0

        nodes = [
            RefSource("src_h2", FixedProfile(1000), FixedProfile(10), FixedProfile(0),
                Dict(H2 => 1), [FixPressureData(FixedProfile(P_supply))]),
            RefSource("src_ch4", FixedProfile(1000), FixedProfile(5), FixedProfile(0),
                Dict(CH4 => 1), [FixPressureData(FixedProfile(P_supply))]),
            PoolingNode("entry", FixedProfile(1e6), FixedProfile(0), FixedProfile(0),
                Dict(H2 => 1, CH4 => 1), Dict(Blend => 1),
                [FixPressureData(FixedProfile(P_entry))]),
            PoolingNode("junction", FixedProfile(1e6), FixedProfile(0), FixedProfile(0),
                Dict(Blend => 1), Dict(Blend => 1),
                [MaxPressureData(FixedProfile(P_supply)),
                    RefBlendData{ResourcePressure{Float64}}(Blend,
                        Dict(H2 => 0.2, CH4 => 1.0), Dict(H2 => 0.0, CH4 => 0.0))]),
            RefSink("sink", FixedProfile(10),
                Dict(:surplus => FixedProfile(0), :deficit => FixedProfile(1e6)),
                Dict(Blend => 1), [MinPressureData(FixedProfile(P_sink))]),
        ]
        links = [
            Direct("h2_to_entry", nodes[1], nodes[3], Linear()),
            Direct("ch4_to_entry", nodes[2], nodes[3], Linear()),
            CapDirect("blend_pipe", nodes[3], nodes[4], Linear(), FixedProfile(1000),
                [PressureLinkData(0.24, P_entry, P_sink),
                    MinPressureData(FixedProfile(1e-6)),
                    BlendLinkData(Blend,
                        Dict{ResourcePressure{Float64},Float64}(H2 => 2.016),
                        0.2, 0.0,   # H₂ range of the PWA grid
                        Dict{ResourcePressure{Float64},Float64}(CH4 => 16.04))]),
            CapDirect("junction_to_sink", nodes[4], nodes[5], Linear(),
                FixedProfile(1000),
                [PressureLinkData(0.24, P_entry, P_sink),
                    MinPressureData(FixedProfile(P_sink)),
                    BlendLinkData(Blend,
                        Dict{ResourcePressure{Float64},Float64}(H2 => 2.016),
                        0.2, 0.0,   # H₂ range of the PWA grid
                        Dict{ResourcePressure{Float64},Float64}(CH4 => 16.04))]),
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

    case_pp, model_pp, m_pp = generate_case_pressure_propagation()
    𝒩_pp = get_nodes(case_pp)
    𝒫_pp = get_products(case_pp)
    𝒯_pp = get_time_struct(case_pp)
    Blend_pp = first(filter(p -> p.id == "Blend", 𝒫_pp))
    t_pp = first(collect(𝒯_pp))
    junction = 𝒩_pp[4]

    P_supply = 200.0
    P_entry = 150.0
    P_sink = 80.0

    @test JuMP.termination_status(m_pp) ∈ [MOI.OPTIMAL, MOI.ALMOST_OPTIMAL, MOI.OTHER_LIMIT]
    @test value(m_pp[:potential_in][junction, t_pp, Blend_pp]) <= P_entry + 1e-3
    @test value(m_pp[:potential_out][junction, t_pp, Blend_pp]) <= P_entry + 1e-3
    @test value(m_pp[:potential_out][junction, t_pp, Blend_pp]) >= P_sink - 1.0
end
