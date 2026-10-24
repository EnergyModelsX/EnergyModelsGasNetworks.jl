@testitem "TransitNode linear proportion passthrough" setup = [EMGNSetup] begin
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

    function generate_case_transit_node()
        H2 = ResourcePressure("H2", 1.0)
        CH4 = ResourcePressure("CH4", 1.0)
        Blend = ResourcePooling("Blend", [H2, CH4])
        CO2 = ResourceEmit("CO2", 1.0)
        products = [CO2, Blend, H2, CH4]
        T = TwoLevel(1, 1, TimeStruct.SimpleTimes(1, 1); op_per_strat = 1)
        P_supply = 100.0
        P_entry = 80.0
        P_sink = 40.0

        nodes = [
            RefSource("src_h2", FixedProfile(1000), FixedProfile(1), FixedProfile(0),
                Dict(H2 => 1), [FixPressureData(FixedProfile(P_supply))]),
            RefSource("src_ch4", FixedProfile(1000), FixedProfile(1), FixedProfile(0),
                Dict(CH4 => 1), [FixPressureData(FixedProfile(P_supply))]),
            PoolingNode("entry", FixedProfile(1e6), FixedProfile(0), FixedProfile(0),
                Dict(H2 => 1, CH4 => 1), Dict(Blend => 1),
                [FixPressureData(FixedProfile(P_entry)),
                    RefBlendData{ResourcePressure{Float64}}(Blend,
                        Dict(H2 => 0.1, CH4 => 1.0), Dict(H2 => 0.1, CH4 => 0.0))]),
            TransitNode("transit", FixedProfile(1e6), FixedProfile(0), FixedProfile(0),
                Dict(Blend => 1), Dict(Blend => 1),
                [
                    MaxPressureData(FixedProfile(P_supply)),
                    MinPressureData(FixedProfile(P_sink)),
                ]),
            RefSink("sink", FixedProfile(10),
                Dict(:surplus => FixedProfile(-50), :deficit => FixedProfile(1e6)),
                Dict(Blend => 1), [MinPressureData(FixedProfile(P_sink))]),
        ]
        links = [
            Direct("h2_to_entry", nodes[1], nodes[3], Linear()),
            Direct("ch4_to_entry", nodes[2], nodes[3], Linear()),
            CapDirect("blend_entry_transit", nodes[3], nodes[4], Linear(),
                FixedProfile(1000),
                [PressureLinkData(0.24, P_entry, P_sink),
                    MinPressureData(FixedProfile(1e-6)),
                    BlendLinkData(Blend,
                        Dict{ResourcePressure{Float64},Float64}(H2 => 2.016),
                        0.2, 0.0,   # H₂ range of the PWA grid
                        Dict{ResourcePressure{Float64},Float64}(CH4 => 16.04))]),
            CapDirect("blend_transit_sink", nodes[4], nodes[5], Linear(),
                FixedProfile(1000),
                [PressureLinkData(0.24, P_entry, P_sink),
                    MinPressureData(FixedProfile(P_sink)),
                    BlendLinkData(Blend,
                        Dict{ResourcePressure{Float64},Float64}(H2 => 2.016),
                        0.2, 0.0,   # H₂ range of the PWA grid
                        Dict{ResourcePressure{Float64},Float64}(CH4 => 16.04))]),
        ]
        case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
        model = OperationalModel(
            Dict(CO2 => FixedProfile(0)),
            Dict(CO2 => FixedProfile(0)),
            CO2,
        )
        EMGNSetup.setup_pwa!(; step = 10)   # narrow 40–80 bar range
        m = create_model(case, model; check_timeprofiles = true)
        set_optimizer(m, EMGNSetup.scip_optimizer())
        optimize!(m)
        return case, model, m
    end

    case_tn, model_tn, m_tn = generate_case_transit_node()
    𝒩_tn = get_nodes(case_tn)
    𝒫_tn = get_products(case_tn)
    𝒯_tn = get_time_struct(case_tn)
    H2_tn = first(filter(p -> p.id == "H2", 𝒫_tn))
    CH4_tn = first(filter(p -> p.id == "CH4", 𝒫_tn))
    t_tn = first(collect(𝒯_tn))
    entry_tn = 𝒩_tn[3]
    transit_tn = 𝒩_tn[4]

    @test JuMP.termination_status(m_tn) ∈ [MOI.OPTIMAL, MOI.ALMOST_OPTIMAL]
    @test value(m_tn[:proportion_out][transit_tn, t_tn, H2_tn]) ≈
          value(m_tn[:proportion_out][entry_tn, t_tn, H2_tn]) atol = 1e-4
    @test value(m_tn[:proportion_out][transit_tn, t_tn, CH4_tn]) ≈
          value(m_tn[:proportion_out][entry_tn, t_tn, CH4_tn]) atol = 1e-4
    @test value(m_tn[:proportion_out][entry_tn, t_tn, H2_tn]) +
          value(m_tn[:proportion_out][entry_tn, t_tn, CH4_tn]) ≈ 1.0 atol = 1e-4
    @test value(m_tn[:proportion_out][transit_tn, t_tn, H2_tn]) +
          value(m_tn[:proportion_out][transit_tn, t_tn, CH4_tn]) ≈ 1.0 atol = 1e-4
end
