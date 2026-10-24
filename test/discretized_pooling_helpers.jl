# Shared helpers for discretized pooling test items (included inside each @testitem)

function generate_case_discretized_pooling(;
    n_points = 5, max_h2 = 0.05, capacity = 1e6, method = :pwl)
    H2 = ResourceCarrier("H2", 1.0)
    CH4 = ResourceCarrier("CH4", 1.0)
    Gas = ResourcePooling("Gas", [H2, CH4])
    CO2 = ResourceEmit("CO2", 1.0)

    T = TwoLevel(1, 1, SimpleTimes(2, 1); op_per_strat = 2)

    pooling = DiscretizedPoolingNode("pooling", FixedProfile(capacity), FixedProfile(0),
        FixedProfile(0), Dict(H2 => 1.0, CH4 => 1.0), Dict(Gas => 1.0),
        Data[DiscretizationData(n_points, method)])

    nodes = [
        RefSource(
            "src_h2",
            FixedProfile(200),
            FixedProfile(0),
            FixedProfile(0),
            Dict(H2 => 1.0),
        ),
        RefSource(
            "src_ch4",
            FixedProfile(600),
            FixedProfile(0),
            FixedProfile(0),
            Dict(CH4 => 1.0),
        ),
        pooling,
        RefSink("sink1", FixedProfile(300),
            Dict(:surplus => FixedProfile(-50.0), :deficit => FixedProfile(1e4)),
            Dict(Gas => 1.0),
            [
                RefBlendData(
                    Gas,
                    Dict(H2 => max_h2, CH4 => 1.0),
                    Dict(H2 => 0.0, CH4 => 0.0),
                ),
            ]),
        RefSink("sink2", FixedProfile(300),
            Dict(:surplus => FixedProfile(-50.0), :deficit => FixedProfile(1e4)),
            Dict(Gas => 1.0),
            [
                RefBlendData(
                    Gas,
                    Dict(H2 => max_h2, CH4 => 1.0),
                    Dict(H2 => 0.0, CH4 => 0.0),
                ),
            ]),
    ]

    links = [
        CapDirect("h2_pool", nodes[1], nodes[3], Linear(), FixedProfile(200)),
        CapDirect("ch4_pool", nodes[2], nodes[3], Linear(), FixedProfile(600)),
        CapDirect("pool_sink1", nodes[3], nodes[4], Linear(), FixedProfile(600)),
        CapDirect("pool_sink2", nodes[3], nodes[5], Linear(), FixedProfile(600)),
    ]

    products = [CO2, Gas, H2, CH4]
    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    modeltype = OperationalModel(Dict(CO2 => FixedProfile(0.0)),
        Dict(CO2 => FixedProfile(0.0)), CO2)
    return case, modeltype
end

function generate_reversed_discretized_case(;
    method = :pwl, tracked = :explicit, max_h2 = 0.2)
    H2 = ResourceCarrier("H2", 0.0)
    CH4 = ResourceCarrier("CH4", 0.0)
    other = ResourceCarrier("other", 0.0)
    Gas = ResourcePooling("Gas", [CH4, H2])
    CO2 = ResourceEmit("CO2", 1.0)
    T = TwoLevel(1, 1, SimpleTimes(1, 1); op_per_strat = 1)

    discr = if tracked == :explicit
        DiscretizationData(H2, 6, method, max_h2)
    elseif tracked == :invalid
        DiscretizationData(other, 6, method, max_h2)
    else
        DiscretizationData(6, method, max_h2)
    end
    data = Data[discr]
    if tracked == :ambiguous
        push!(
            data,
            RefBlendData(Gas,
                Dict(H2 => max_h2, CH4 => 0.9), Dict(H2 => 0.0, CH4 => 0.0)),
        )
    end

    pooling = DiscretizedPoolingNode("pooling", FixedProfile(100.0), FixedProfile(0.0),
        FixedProfile(0.0), Dict(H2 => 1.0, CH4 => 1.0), Dict(Gas => 1.0), data)
    nodes = [
        RefSource(
            "h2",
            FixedProfile(100.0),
            FixedProfile(-1.0),
            FixedProfile(0.0),
            Dict(H2 => 1.0),
        ),
        RefSource(
            "ch4",
            FixedProfile(100.0),
            FixedProfile(0.0),
            FixedProfile(0.0),
            Dict(CH4 => 1.0),
        ),
        pooling,
        RefSink("sink", FixedProfile(100.0),
            Dict(:surplus => FixedProfile(0.0), :deficit => FixedProfile(1e4)),
            Dict(Gas => 1.0),
            [
                RefBlendData(
                    Gas,
                    Dict(H2 => max_h2, CH4 => 1.0),
                    Dict(H2 => 0.0, CH4 => 0.0),
                ),
            ]),
    ]
    links = [
        Direct("h2_pool", nodes[1], nodes[3], Linear()),
        Direct("ch4_pool", nodes[2], nodes[3], Linear()),
        CapDirect("pool_sink", nodes[3], nodes[4], Linear(), FixedProfile(100.0)),
    ]
    case = Case(T, [CO2, Gas, H2, CH4, other], [nodes, links], [[get_nodes, get_links]])
    model = OperationalModel(Dict(CO2 => FixedProfile(0.0)),
        Dict(CO2 => FixedProfile(0.0)), CO2)
    return case, model, pooling, H2, CH4
end
