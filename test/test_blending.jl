
function generate_case_blending(; links = nothing)
    # Define reasources
    H2 = ResourceCarrier("H2", 1.0)
    CH4 = ResourceCarrier("CH4", 1.0)
    Gas = ResourcePooling("Gas", [H2, CH4])
    CO2 = ResourceEmit("CO2", 1.0)
    products = [CO2, Gas, H2, CH4]

    # Time
    op_duration = 1
    op_number = 1
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
        RefSource(1, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(H2 => 1)),
        RefSource(2, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(CH4 => 1)),
        RefSource(3, FixedProfile(600), FixedProfile(10), FixedProfile(0), Dict(CH4 => 1)),
        PoolingNode(
            4,
            FixedProfile(1e6),
            FixedProfile(0),
            FixedProfile(0),
            Dict(CH4 => 1, H2 => 1),
            Dict(Gas => 1),
        ),
        RefSink(
            5,
            FixedProfile(500),
            Dict(:surplus => FixedProfile(-120), :deficit => FixedProfile(1e6)),
            Dict(Gas => 1),
            [RefBlendData(Gas, Dict(H2=>0.05, CH4=>1.0),
                Dict(H2=>0.0, CH4=>0.0))
            ]),
    ]

    if isnothing(links)
        links = [
            CapDirect(14, nodes[1], nodes[4], Linear(), FixedProfile(200)),
            CapDirect(24, nodes[2], nodes[4], Linear(), FixedProfile(200)),
            CapDirect(34, nodes[3], nodes[4], Linear(), FixedProfile(600)),
            CapDirect(45, nodes[4], nodes[5], Linear(), FixedProfile(1200)),
        ]
    end

    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model = OperationalModel(
        Dict(CO2 => FixedProfile(0)),
        Dict(CO2 => FixedProfile(0)),
        CO2,
    )
    return case, model
end

case, model = generate_case_blending()
m = create_model(case, model; check_timeprofiles = true)

for l ∈ get_links(case)
    @constraint(
        m,
        [t ∈ get_time_struct(case), p ∈ EMB.link_res(l)],
        m[:link_in][l, t, p] <= 1200
    )
    @constraint(
        m,
        [t ∈ get_time_struct(case), p ∈ EMB.link_res(l)],
        m[:link_out][l, t, p] <= 1200
    )
end

𝒩 = get_nodes(case)
𝒩_in = filter(EMB.has_input, 𝒩)
𝒩_out = filter(EMB.has_output, 𝒩)
for n ∈ 𝒩_in
    @constraint(
        m,
        [t ∈ get_time_struct(case), p ∈ EMB.inputs(n)],
        m[:flow_in][n, t, p] <= 1200
    )
end
for n ∈ 𝒩_out
    @constraint(
        m,
        [t ∈ get_time_struct(case), p ∈ EMB.outputs(n)],
        m[:flow_out][n, t, p] <= 1200
    )
end

set_optimizer(m, optimizer)
optimize!(m)

# Extract data from the case
𝒩 = get_nodes(case)
ℒ = get_links(case)
𝒫 = get_products(case)
𝒯 = get_time_struct(case)

H2 = first(filter(p -> p.id == "H2", 𝒫))
CH4 = first(filter(p -> p.id == "CH4", 𝒫))
Gas = first(filter(p -> p.id == "Gas", 𝒫))
@testset "Results" begin
    @test value.(m[:link_in][ℒ[1], first(collect(𝒯)), H2]) ≈ 42.105 atol=1e-2
    @test value.(m[:link_in][ℒ[2], first(collect(𝒯)), CH4]) ≈ 200 atol=1e-2
    @test value.(m[:link_in][ℒ[3], first(collect(𝒯)), CH4]) ≈ 600 atol=1e-2
    @test value.(m[:link_in][ℒ[1], first(collect(𝒯)), H2]) +
          value.(m[:link_in][ℒ[2], first(collect(𝒯)), CH4]) +
          value.(m[:link_in][ℒ[3], first(collect(𝒯)), CH4]) ≈
          value.(m[:link_out][ℒ[4], first(collect(𝒯)), Gas])

    @test value.(m[:proportion_source][𝒩[5], 𝒩[1], first(collect(𝒯))]) ≈ 0.05
    @test value.(m[:proportion_track][𝒩[3], first(collect(𝒯)), H2]) ≈ 0.0
    @test value.(m[:proportion_track][𝒩[4], first(collect(𝒯)), H2]) ≈ 0.05
    @test value.(m[:proportion_track][𝒩[5], first(collect(𝒯)), H2]) ≈ 0.05

    @test value.(m[:proportion_source][𝒩[5], 𝒩[3], first(collect(𝒯))]) ≈
          600/(600+42.105+200) atol=1e-2
    @test value.(m[:proportion_source][𝒩[5], 𝒩[2], first(collect(𝒯))]) ≈
          200/(600+42.105+200) atol=1e-2
    @test value.(m[:proportion_track][𝒩[5], first(collect(𝒯)), CH4]) ≈ 0.95
end
