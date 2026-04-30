# Regression tests for pressure propagation through PoolingNode junctions.
#
# Tests Fix A in `constraints_balance_pressure` for PoolingNode:
#
#   Fix A: The `ResourcePooling{ResourcePressure}` (Blend) dispatch was empty — Weymouth
#          pipe delivery pressure never constrained the junction's output pressure.
#
# Test topology (two-segment Blend pipeline with PoolingNode junction):
#
#   src_h2  (200 bar) ──Direct──► entry_node (fixed 150 bar) ──Weymouth──► junction ──Weymouth──► sink
#   src_ch4 (200 bar) ──Direct──► entry_node
#
# entry_node output is fixed at P_entry = 150 bar (FixPressureData).
# All gas must flow through the Weymouth entry→junction pipe (no bypass).
# Without Fix A: potential_out[junction, Blend] is unbounded from above.
# With  Fix A:   potential_out[junction, Blend] ≤ potential_in[junction, Blend] ≤ P_entry = 150 bar.

function generate_case_pressure_propagation()
    # Resources
    H2    = ResourcePressure("H2",   1.0)
    CH4   = ResourcePressure("CH4",  1.0)
    Blend = ResourcePooling("Blend", [H2, CH4])
    CO2   = ResourceEmit("CO2", 1.0)
    products = [CO2, Blend, H2, CH4]

    # Single operational period
    T = TwoLevel(1, 1, TimeStruct.SimpleTimes(1, 1); op_per_strat = 1)

    # Pressure levels [bar]
    P_supply = 200.0  # H2/CH4 source pressure
    P_entry  = 150.0  # Entry node output fixed at 150 bar
    P_sink   = 80.0   # Minimum pressure required at the sink

    nodes = [
        # H2 supply
        RefSource(
            "src_h2",
            FixedProfile(1000), FixedProfile(10), FixedProfile(0),
            Dict(H2 => 1),
            [FixPressureData(FixedProfile(P_supply))]),                        # 1

        # CH4 supply
        RefSource(
            "src_ch4",
            FixedProfile(1000), FixedProfile(5), FixedProfile(0),
            Dict(CH4 => 1),
            [FixPressureData(FixedProfile(P_supply))]),                        # 2

        # Entry PoolingNode: blends H2+CH4 into Blend; output fixed at P_entry = 150 bar.
        PoolingNode(
            "entry",
            FixedProfile(1e6), FixedProfile(0), FixedProfile(0),
            Dict(H2 => 1, CH4 => 1), Dict(Blend => 1),
            [FixPressureData(FixedProfile(P_entry))]),                         # 3

        # Junction PoolingNode: receives only Blend from entry (via Weymouth).
        # With Fix A: output pressure ≤ Blend delivery (≤ P_entry = 150 bar).
        PoolingNode(
            "junction",
            FixedProfile(1e6), FixedProfile(0), FixedProfile(0),
            Dict(Blend => 1), Dict(Blend => 1),
            [
                MaxPressureData(FixedProfile(P_supply)),
                RefBlendData{ResourcePressure{Float64}}(
                    Blend,
                    Dict(H2 => 1.0, CH4 => 1.0),
                    Dict(H2 => 0.0, CH4 => 0.0),
                ),
            ]),                                                                 # 4

        # Sink: requires Blend at ≥ P_sink (80 bar) with mandatory demand.
        RefSink(
            "sink",
            FixedProfile(10),
            Dict(:surplus => FixedProfile(0), :deficit => FixedProfile(1e6)),
            Dict(Blend => 1),
            [MinPressureData(FixedProfile(P_sink))]),                          # 5
    ]

    links = [
        # Sources feed the entry PoolingNode
        Direct("h2_to_entry",  nodes[1], nodes[3], Linear()),                 # 1
        Direct("ch4_to_entry", nodes[2], nodes[3], Linear()),                 # 2

        # Blend pipe: entry (fixed 150 bar) → junction (Weymouth pressure drop)
        CapDirect("blend_pipe", nodes[3], nodes[4], Linear(), FixedProfile(1000),
            [PressureLinkData(0.24, P_entry, P_sink),
             MinPressureData(FixedProfile(1e-6)),
             BlendLinkData(
                 Blend,
                 Dict{ResourcePressure{Float64},Float64}(H2 => 2.016),
                 1.0, 0.0,
                 Dict{ResourcePressure{Float64},Float64}(CH4 => 16.04),
             )]),                                                               # 3

        # Outgoing Blend pipe: junction → sink
        CapDirect("junction_to_sink", nodes[4], nodes[5], Linear(), FixedProfile(1000),
            [PressureLinkData(0.24, P_entry, P_sink),
             MinPressureData(FixedProfile(P_sink)),
             BlendLinkData(
                 Blend,
                 Dict{ResourcePressure{Float64},Float64}(H2 => 2.016),
                 1.0, 0.0,
                 Dict{ResourcePressure{Float64},Float64}(CH4 => 16.04),
             )]),                                                               # 4
    ]

    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model = OperationalModel(
        Dict(CO2 => FixedProfile(0)),
        Dict(CO2 => FixedProfile(0)),
        CO2,
    )

    set_optimizer_pwa!(mip_optimizer)
    m = create_model(case, model; check_timeprofiles = true)
    set_optimizer(m, optimizer)
    optimize!(m)

    return case, model, m
end

case_pp, model_pp, m_pp = generate_case_pressure_propagation()

𝒩_pp = get_nodes(case_pp)
𝒫_pp = get_products(case_pp)
𝒯_pp = get_time_struct(case_pp)

H2_pp    = first(filter(p -> p.id == "H2",    𝒫_pp))
CH4_pp   = first(filter(p -> p.id == "CH4",   𝒫_pp))
Blend_pp = first(filter(p -> p.id == "Blend", 𝒫_pp))
t_pp     = first(collect(𝒯_pp))
junction = 𝒩_pp[4]  # the "junction" PoolingNode

@testset "Pressure propagation through PoolingNode junction" begin
    # Regression for constraints_balance_pressure (Fix A + Fix B):
    # H2/CH4 trackers arrive at supply pressure (200 bar) via Ra=0 links.
    # Blend arrives from the entry node (fixed at 150 bar) via a Weymouth pipe.
    # The junction output must be bounded by the Blend delivery (≤ P_entry),
    # NOT by the H2/CH4 supply pressure (P_supply = 200 bar).

    P_supply = 200.0
    P_entry  = 150.0
    P_sink   = 80.0

    # Solver must find a feasible solution (demand of 10 forces actual gas flow)
    @test JuMP.termination_status(m_pp) ∈ [MOI.OPTIMAL, MOI.ALMOST_OPTIMAL, MOI.OTHER_LIMIT]

    # Blend arrives at junction via Weymouth pipe from entry (fixed at P_entry = 150 bar).
    # Physical delivery pressure is ≤ P_entry; it is strictly less than the supply pressure.
    @test value(m_pp[:potential_in][junction, t_pp, Blend_pp]) <= P_entry + 1e-3

    # KEY REGRESSION: junction output must be bounded by the Blend delivery pressure (≤ P_entry),
    # not by the H2/CH4 supply pressure (P_supply = 200 bar).
    # Without Fix A (empty body): output unbounded by Blend delivery → optimizer pushes to 200.
    # Without Fix B (== instead of >=): H2 == constraint forces output = 200.
    @test value(m_pp[:potential_out][junction, t_pp, Blend_pp]) <= P_entry + 1e-3

    # Sanity: junction output must be at least as high as the sink's minimum pressure
    # (since the outgoing pipe inlet = junction outlet, and pipe delivers ≥ P_sink to the sink)
    @test value(m_pp[:potential_out][junction, t_pp, Blend_pp]) >= P_sink - 1.0
end
