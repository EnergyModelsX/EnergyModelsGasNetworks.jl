
function generate_case()

    # Define reasources
    CH4 = ResourcePressure("CH4", 1.0)
    CO2 = ResourceEmit("CO2", 1.0)
    products = [CO2, CH4]

    # Time
    op_duration = 1
    op_number = 2
    operational_periods = TimeStruct.SimpleTimes(op_number, op_duration)
    op_per_strat = op_duration * op_number

    T = TwoLevel(1, 1, operational_periods; op_per_strat)

    # Initialise EMB model
    model = OperationalModel(
        Dict(CO2 => StrategicProfile([0])),
        Dict(CO2 => FixedProfile(0)),
        CO2)

    # Nodes
    nodes = [
        RefSource(
            "source_1",
            FixedProfile(10),
            FixedProfile(10),
            FixedProfile(0),
            Dict(CH4 => 1),
            [MaxPressureData(FixedProfile(200))],
        ),
        RefSource(
            "source_2",
            FixedProfile(10),
            FixedProfile(10),
            FixedProfile(0),
            Dict(CH4 => 1),
            [MaxPressureData(FixedProfile(180))],
        ),
        GenAvailability(
            "pooling_1",
            [CH4],
            [CH4],
        ),
        GenAvailability(
            "pooling_2",
            [CH4],
            [CH4],
        ),
        RefSink(
            "sink_1",
            OperationalProfile([5, 15]),
            Dict(:surplus => FixedProfile(1e4), :deficit => FixedProfile(1e4)),
            Dict(CH4 => 1),
            [MinPressureData(FixedProfile(130))]),
        RefSink(
            "sink_2",
            OperationalProfile([15, 5]),
            Dict(:surplus => FixedProfile(1e4), :deficit => FixedProfile(1e4)),
            Dict(CH4 => 1),
            [MinPressureData(FixedProfile(130))]),
    ]

    links = [
        CapDirect(
            "source_pooling_1",
            nodes[1],
            nodes[3],
            Linear(),
            FixedProfile(200),
            [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6))],
        ), # NOT SURE WHY I HAVE TO LIMIT THE outlet pressure in links to avoid weird behaviours
        CapDirect(
            "source_pooling_2",
            nodes[2],
            nodes[4],
            Linear(),
            FixedProfile(200),
            [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6))],
        ),
        CapDirect(
            "pooling_sink_1",
            nodes[3],
            nodes[5],
            Linear(),
            FixedProfile(200),
            [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6))],
        ),
        CapDirect(
            "pooling_sink_2",
            nodes[4],
            nodes[6],
            Linear(),
            FixedProfile(200),
            [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6))],
        ),
        CapDirect(
            "pooling1_pooling2",
            nodes[3],
            nodes[4],
            Linear(),
            FixedProfile(200),
            [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6))],
        ),
        CapDirect(
            "pooling2_pooling1",
            nodes[4],
            nodes[3],
            Linear(),
            FixedProfile(200),
            [PressureLinkData(0.24, 200, 130), MinPressureData(FixedProfile(1e-6))],
        ),
    ]

    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model = OperationalModel(
        Dict(CO2 => FixedProfile(0)),
        Dict(CO2 => FixedProfile(0)),
        CO2,
    )

    return case, model
end

# Run case
case, model = generate_case()

m = EMB.create_model(case, model; check_timeprofiles = true)
set_optimizer(m, optimizer)
optimize!(m)

# Extract data from the case
𝒩 = get_nodes(case)
ℒ = get_links(case)
𝒫 = get_products(case)
𝒯 = get_time_struct(case)

@testset "Bidirectional links" begin
    t_1 = first(𝒯)
    t_2 = last(𝒯)
    CH4 = first(filter(p -> p.id == "CH4", 𝒫))

    l_p1_p2 = first(filter(l -> l.id == "pooling1_pooling2", ℒ))
    l_p2_p1 = first(filter(l -> l.id == "pooling2_pooling1", ℒ))
    @test value.(m[:link_in][l_p1_p2, t_1, CH4]) == 5
    @test value.(m[:has_flow][l_p1_p2, t_1]) == 1.0
    @test value.(m[:has_flow][l_p2_p1, t_1]) == 0.0
    @test value.(m[:link_in][l_p1_p2, t_1, CH4]) == value.(m[:link_in][l_p2_p1, t_2, CH4])
end
