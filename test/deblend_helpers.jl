# Shared helper for DeblendNode test items (included inside each @testitem)

const DB_H2_FLOW = 10.0
const DB_CH4_FLOW = 90.0
const DB_CAP = 15.0

function make_deblend_case(; max_extract_fraction = 1.0, psa_efficiency = 1.0, cap = DB_CAP)
    H2 = ResourceCarrier("H2", 0.0)
    CH4 = ResourceCarrier("CH4", 0.0)
    CO2 = ResourceEmit("CO2", 1.0)
    Blend = ResourcePooling("Blend", [H2, CH4])

    T = TwoLevel(1, 1, SimpleTimes(1, 1); op_per_strat = 1)

    nodes = [
        RefSource("src_h2", FixedProfile(DB_H2_FLOW), FixedProfile(0), FixedProfile(0),
            Dict(H2 => 1)),
        RefSource("src_ch4", FixedProfile(DB_CH4_FLOW), FixedProfile(0),
            FixedProfile(0),
            Dict(CH4 => 1)),
        BlendingNode("blend_jn", FixedProfile(200), FixedProfile(0), FixedProfile(0),
            Dict(H2 => 1.0, CH4 => 1.0), Dict(Blend => 1.0),
            [RefBlendData(Blend, Dict(H2 => 1.0, CH4 => 1.0), Dict(H2 => 0.0, CH4 => 0.0))]),
        DeblendNode("deblend", FixedProfile(cap), FixedProfile(0), FixedProfile(0),
            Dict(Blend => 1), Dict(Blend => 1, H2 => 1),
            [DeblendData(max_extract_fraction, psa_efficiency)]),
        RefSink("blend_sink", FixedProfile(0),
            Dict(:surplus => FixedProfile(-1.0), :deficit => FixedProfile(1.0)),
            Dict(Blend => 1),
            [RefBlendData(Blend, Dict(H2 => 1.0, CH4 => 1.0), Dict(H2 => 0.0, CH4 => 0.0))]),
        RefSink("h2_sink", FixedProfile(0),
            Dict(:surplus => FixedProfile(-1000.0), :deficit => FixedProfile(1000.0)),
            Dict(H2 => 1)),
    ]

    links = [
        Direct("h2_to_blend", nodes[1], nodes[3], Linear()),
        Direct("ch4_to_blend", nodes[2], nodes[3], Linear()),
        Direct("blend_to_deblend", nodes[3], nodes[4], Linear()),
        Direct("deblend_to_blend_sink", nodes[4], nodes[5], Linear()),
        Direct("deblend_to_h2_sink", nodes[4], nodes[6], Linear()),
    ]

    model = OperationalModel(Dict(CO2 => FixedProfile(0.0)),
        Dict(CO2 => FixedProfile(0.0)), CO2)
    case = Case(T, [CO2, Blend, H2, CH4], [nodes, links], [[get_nodes, get_links]])
    return case, model, nodes, links
end
