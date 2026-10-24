# Shared helpers for blend topology test items (included inside each @testitem)

function topology_model(CO2)
    return OperationalModel(
        Dict(CO2 => FixedProfile(0.0)), Dict(CO2 => FixedProfile(0.0)), CO2)
end

function topology_case(nodes, links, products)
    T = TwoLevel(1, 1, SimpleTimes(1, 1); op_per_strat = 1)
    return Case(T, products, [nodes, links], [[get_nodes, get_links]])
end

function topology_resources(; reversed = false, pressure = false)
    constructor = pressure ? ResourcePressure : ResourceCarrier
    H2 = constructor("H2", 0.0)
    CH4 = constructor("CH4", 0.0)
    sub = reversed ? [CH4, H2] : [H2, CH4]
    Blend = ResourcePooling("Blend", sub)
    CO2 = ResourceEmit("CO2", 1.0)
    return H2, CH4, Blend, CO2
end

function blend_bounds(Blend, H2, CH4; min_h2 = 0.0, max_h2 = 1.0)
    return RefBlendData(
        Blend,
        Dict(H2 => max_h2, CH4 => 1.0),
        Dict(H2 => min_h2, CH4 => 0.0),
    )
end
