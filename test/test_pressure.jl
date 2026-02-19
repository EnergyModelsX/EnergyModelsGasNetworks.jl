function generate_case_pressure()
    # Define reasources
    NG = ResourcePressure("NG", 1.0)
    CO2 = ResourceEmit("CO2", 1.0)
    Power = ResourceCarrier("Power", 1.0)
    products = [CO2, NG, Power]

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
        RefSource(
            "source_1",
            FixedProfile(200),
            FixedProfile(15),
            FixedProfile(0),
            Dict(NG => 1),
            [FixPressureData(FixedProfile(130))],
        ),
        RefSource(
            "source_2",
            FixedProfile(200),
            FixedProfile(10),
            FixedProfile(0),
            Dict(NG => 1),
            [FixPressureData(FixedProfile(130))],
        ),
        RefSource(
            "source_3",
            FixedProfile(200),
            FixedProfile(5),
            FixedProfile(0),
            Dict(NG => 1),
            [FixPressureData(FixedProfile(130))],
        ),
        SimpleCompressor(
            "compressor_1", # 4
            FixedProfile(1e6),
            FixedProfile(0),
            FixedProfile(0),
            Dict(NG => 1, Power => 0.1),
            Dict(NG => 1),
            FixedProfile(60),
            [MaxPressureData(FixedProfile(190))],
        ),
        SimpleCompressor(
            "compressor_2", # 5
            FixedProfile(1e6),
            FixedProfile(0),
            FixedProfile(0),
            Dict(NG => 1, Power => 0.1),
            Dict(NG => 1),
            FixedProfile(60),
            [MaxPressureData(FixedProfile(190))],
        ),
        SimpleCompressor(
            "compressor_3", # 6
            FixedProfile(1e6),
            FixedProfile(0),
            FixedProfile(0),
            Dict(NG => 1, Power => 0.1),
            Dict(NG => 1),
            FixedProfile(60),
            [MaxPressureData(FixedProfile(190))],
        ),
        RefSource(
            "power_source",
            FixedProfile(200),
            FixedProfile(2),
            FixedProfile(0),
            Dict(Power => 1),
            [FixPressureData(FixedProfile(0))],
        ),
        RefSink(
            "sink_1",
            FixedProfile(20),
            Dict(:surplus => FixedProfile(1e6), :deficit => FixedProfile(1e6)),
            Dict(NG => 1),
            [MaxPressureData(FixedProfile(180)), MinPressureData(FixedProfile(160))],
        ),
    ]
    links = [
        Direct(
            "source_comp_1",
            nodes[1],
            nodes[4],
            Linear(),
        ),
        Direct(
            "source_comp_2",
            nodes[2],
            nodes[5],
            Linear(),
        ),
        Direct(
            "source_comp_2",
            nodes[3],
            nodes[6],
            Linear(),
        ),
        CapDirect(
            "comp_1_sink",
            nodes[4],
            nodes[8],
            Linear(),
            FixedProfile(200),
            [PressureLinkData(0.24, 200, 0), MinPressureData(FixedProfile(1e-6))],
        ),
        CapDirect(
            "comp_2_sink",
            nodes[5],
            nodes[8],
            Linear(),
            FixedProfile(200),
            [PressureLinkData(0.24, 200, 0), MinPressureData(FixedProfile(1e-6))],
        ),
        CapDirect(
            "comp_3_sink",
            nodes[6],
            nodes[8],
            Linear(),
            FixedProfile(200),
            [PressureLinkData(0.24, 200, 0), MinPressureData(FixedProfile(1e-6))],
        ),
        Direct(
            "power_comp_1",
            nodes[7],
            nodes[4],
            Linear(),
        ),
        Direct(
            "power_comp_2",
            nodes[7],
            nodes[5],
            Linear(),
        ),
        Direct(
            "power_comp_3",
            nodes[7],
            nodes[6],
            Linear(),
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

case, model = generate_case_pressure()
m = EMB.create_model(case, model; check_timeprofiles = true)
set_optimizer(m, mip_optimizer)
optimize!(m)

# Extract data from the case
𝒩 = get_nodes(case)
ℒ = get_links(case)
𝒫 = get_products(case)
𝒯 = get_time_struct(case)

# Test `create_model` builds a JuMP model without errors for typical input Cases
@testset "Model creation" begin
    @test try
        EMB.create_model(case, model; check_timeprofiles = true)
        true
    catch
        false
    end
end

# Test that the pressure variables of Nodes and Links have been created
@testset "Variables Definition" begin
    @testset "Node variables" begin
        @test haskey(m, :potential_in)
        @test haskey(m, :potential_out)

        @test sum(nt[1] == 𝒩[1] for nt ∈ eachindex(m[:potential_out])) == length(𝒯)
        @test sum(nt[1] == 𝒩[2] for nt ∈ eachindex(m[:potential_out])) == length(𝒯)
        @test sum(nt[1] == 𝒩[3] for nt ∈ eachindex(m[:potential_out])) == length(𝒯)
    end

    @testset "Link variables" begin
        @test haskey(m, :link_potential_in)
        @test haskey(m, :link_potential_out)
        @test haskey(m, :has_flow)

        @test sum(nt[1] == ℒ[1] for nt ∈ eachindex(m[:link_potential_out])) == length(𝒯)
        @test sum(nt[1] == ℒ[2] for nt ∈ eachindex(m[:link_potential_out])) == length(𝒯)
    end
end

# Test constraints correctly defined
@testset "Constraints Definition" begin
    @testset "Nodes Internal Balance Pressure" begin
        𝒩ˢʳ = filter(n -> n isa RefSource, 𝒩)
        @test all(
            v -> v == 0,
            [
                value(m[:potential_in][nt]) for
                nt ∈ eachindex(m[:potential_in]) if nt[1] in 𝒩ˢʳ
            ],
        )

        𝒩ˢ = filter(n -> n isa RefSink, 𝒩)
        @test all(
            v -> v == 0,
            [
                value(m[:potential_out][nt]) for
                nt ∈ eachindex(m[:potential_out]) if nt[1] in 𝒩ˢ
            ],
        )

        𝒩ᵃ = filter(n -> n isa Availability, 𝒩)
        in_val = [
            value(m[:potential_in][nt]) for
            nt ∈ eachindex(m[:potential_in]) if nt[1] in 𝒩ᵃ
        ]
        out_val = [
            value(m[:potential_out][nt]) for
            nt ∈ eachindex(m[:potential_out]) if nt[1] in 𝒩ᵃ
        ]
        @test in_val == out_val

        NG = first(filter(p -> p.id == "NG", 𝒫))
        𝒩ᶜ = filter(n -> n isa SimpleCompressor, 𝒩)
        in_val = [
            value(m[:potential_in][nt]) for
            nt ∈ eachindex(m[:potential_in]) if (nt[1] in 𝒩ᶜ) & (nt[3] == NG)
        ]
        out_val = [
            value(m[:potential_out][nt]) for
            nt ∈ eachindex(m[:potential_out]) if (nt[1] in 𝒩ᶜ) & (nt[3] == NG)
        ]
        @test all(in_val .<= out_val)
    end
end

# Test that the RHS values of the Taylor approximation are correctly calculated
@testset "RHS Taylor Approximation Calculation" begin
    for l ∈ ℒ
        if isa(l, CapDirect)
            link_p_in = first(value.(m[:link_potential_in][l, :, :]))
            link_p_out = first(value.(m[:link_potential_out][l, :, :]))
            RHS_values = calculate_rhs_taylor(link_p_in, link_p_out, l)

            flow = first(value.(m[:link_in][l, :, :]))
            @test isapprox(minimum(RHS_values), flow; atol = 1e-6)
        end
    end
end

@testset "Results" begin
    NG = first(filter(p -> p.id == "NG", 𝒫))
    Power = first(filter(p -> p.id == "Power", 𝒫))

    @test value.(m[:flow_out][𝒩[1], first(collect(𝒯)), NG]) == 0.0
    @test value.(m[:flow_out][𝒩[2], first(collect(𝒯)), NG]) == 0.0
    @test value.(m[:flow_out][𝒩[3], first(collect(𝒯)), NG]) == 20.0
    @test isapprox(value.(m[:flow_out][𝒩[end-1], first(collect(𝒯)), Power]),
        value.(m[:potential_Δ][𝒩[6], first(collect(𝒯))]) * EMB.inputs(𝒩[6], Power);
        atol = 1e-2) # Check the flow of power corresponds to the linear relationship

    @test value.(m[:link_in][ℒ[1], first(collect(𝒯)), NG]) == 0.0
    @test isapprox(value.(m[:link_in][ℒ[2], first(collect(𝒯)), NG]), 0.0; atol = 1e-2)
    @test isapprox(value.(m[:link_in][ℒ[3], first(collect(𝒯)), NG]), 20; atol = 1e-2)
    @test isapprox(value.(m[:link_in][ℒ[4], first(collect(𝒯)), NG]), 0.0; atol = 1e-2)
    @test isapprox(value.(m[:link_in][ℒ[5], first(collect(𝒯)), NG]), 0.0; atol = 1e-2)
    @test isapprox(value.(m[:link_in][ℒ[6], first(collect(𝒯)), NG]), 20.0; atol = 1e-2)
    @test isapprox(value.(m[:link_in][ℒ[9], first(collect(𝒯)), Power]), 3.51; atol = 1e-1)

    @test value.(m[:potential_in][𝒩[6], first(collect(𝒯)), NG]) == 130
    @test isapprox(
        value.(m[:potential_out][𝒩[6], first(collect(𝒯)), NG]),
        165.12;
        atol = 1e-1,
    )
    @test isapprox(value.(m[:potential_Δ][𝒩[6], first(collect(𝒯))]),
        (
            value.(m[:potential_out][𝒩[6], first(collect(𝒯)), NG]) -
            value.(m[:potential_in][𝒩[6], first(collect(𝒯)), NG])
        ); atol = 1e-2)
end

function generate_case2()
    # Define reasources
    NG = ResourcePressure("NG", 1.0)
    CO2 = ResourceEmit("CO2", 1.0)
    products = [CO2, NG]

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
        RefSource(
            1,
            FixedProfile(200),
            FixedProfile(15),
            FixedProfile(0),
            Dict(NG => 1),
            [MaxPressureData(FixedProfile(200))],
        ),
        RefSource(
            2,
            FixedProfile(200),
            FixedProfile(10),
            FixedProfile(0),
            Dict(NG => 1),
            [MaxPressureData(FixedProfile(200))],
        ),
        RefSource(
            3,
            FixedProfile(200),
            FixedProfile(5),
            FixedProfile(0),
            Dict(NG => 1),
            [MaxPressureData(FixedProfile(200))],
        ),
        # GenAvailability(4, FixedProfile(1e6), FixedProfile(0), FixedProfile(0), Dict(NG => 1), Dict(NG => 1), FixedProfile(20), FixedProfile(25)),
        GenAvailability(4, [NG]),
        RefSink(
            5,
            FixedProfile(100),
            Dict(:surplus => FixedProfile(-100), :deficit => FixedProfile(1e6)),
            Dict(NG => 1),
            [MaxPressureData(FixedProfile(180)), MinPressureData(FixedProfile(1e-6))],
        ),
    ]
    links = [
        CapDirect(
            14,
            nodes[1],
            nodes[4],
            Linear(),
            FixedProfile(200),
            [
                PressureLinkData(0.24, 180, 0),
                MaxPressureData(FixedProfile(180)),
                MinPressureData(FixedProfile(1e-6)),
            ],
        ),
        CapDirect(
            24,
            nodes[2],
            nodes[4],
            Linear(),
            FixedProfile(200),
            [
                PressureLinkData(0.24, 180, 0),
                MaxPressureData(FixedProfile(180)),
                MinPressureData(FixedProfile(1e-6)),
            ],
        ),
        CapDirect(
            34,
            nodes[3],
            nodes[4],
            Linear(),
            FixedProfile(200),
            [
                PressureLinkData(0.24, 180, 0),
                MaxPressureData(FixedProfile(180)),
                MinPressureData(FixedProfile(1e-6)),
            ],
        ),
        CapDirect(
            45,
            nodes[4],
            nodes[5],
            Linear(),
            FixedProfile(700),
            [
                PressureLinkData(0.24, 180, 0),
                MaxPressureData(FixedProfile(180)),
                MinPressureData(FixedProfile(1e-6)),
            ],
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

case, model = generate_case2()
m = EMB.create_model(case, model; check_timeprofiles = true)
set_optimizer(m, mip_optimizer)
optimize!(m)

# Extract data from the case
𝒩 = get_nodes(case)
ℒ = get_links(case)
𝒫 = get_products(case)
𝒯 = get_time_struct(case)

@testset "Model creation" begin
    @test try
        EMB.create_model(case, model; check_timeprofiles = true)
        true
    catch
        false
    end
end

# Test that the pressure variables of Nodes and Links have been created
@testset "Variables Definition" begin
    @testset "Node variables" begin
        @test haskey(m, :potential_in)
        @test haskey(m, :potential_out)

        @test sum(nt[1] == 𝒩[1] for nt ∈ eachindex(m[:potential_out])) == length(𝒯)
        @test sum(nt[1] == 𝒩[2] for nt ∈ eachindex(m[:potential_out])) == length(𝒯)
        @test sum(nt[1] == 𝒩[3] for nt ∈ eachindex(m[:potential_out])) == length(𝒯)
    end

    @testset "Link variables" begin
        @test haskey(m, :link_potential_in)
        @test haskey(m, :link_potential_out)
        @test haskey(m, :has_flow)

        @test sum(nt[1] == ℒ[1] for nt ∈ eachindex(m[:link_potential_out])) == length(𝒯)
        @test sum(nt[1] == ℒ[2] for nt ∈ eachindex(m[:link_potential_out])) == length(𝒯)
    end
end

# Test constraints correctly defined
@testset "Constraints Definition" begin
    @testset "Nodes Internal Balance Pressure" begin
        𝒩ˢʳ = filter(n -> n isa RefSource, 𝒩)
        @test all(
            v -> v == 0,
            [
                value(m[:potential_in][nt]) for
                nt ∈ eachindex(m[:potential_in]) if nt[1] in 𝒩ˢʳ
            ],
        )

        𝒩ˢ = filter(n -> n isa RefSink, 𝒩)
        @test all(
            v -> v == 0,
            [
                value(m[:potential_out][nt]) for
                nt ∈ eachindex(m[:potential_out]) if nt[1] in 𝒩ˢ
            ],
        )

        𝒩ᵃ = filter(n -> n isa Availability, 𝒩)
        in_val = [
            value(m[:potential_in][nt]) for
            nt ∈ eachindex(m[:potential_in]) if nt[1] in 𝒩ᵃ
        ]
        out_val = [
            value(m[:potential_out][nt]) for
            nt ∈ eachindex(m[:potential_out]) if nt[1] in 𝒩ᵃ
        ]
        @test in_val == out_val

        𝒩ᶜ = filter(n -> n isa SimpleCompressor, 𝒩)
        in_val = [
            value(m[:potential_in][nt]) for
            nt ∈ eachindex(m[:potential_in]) if nt[1] in 𝒩ᶜ
        ]
        out_val = [
            value(m[:potential_out][nt]) for
            nt ∈ eachindex(m[:potential_out]) if nt[1] in 𝒩ᶜ
        ]
        @test all(in_val .<= out_val)
    end
end

# Test that the RHS values of the Taylor approximation are correctly calculated
@testset "RHS Taylor Approximation Calculation" begin
    for l ∈ ℒ[2:end] # The first link does not pass tests as it is bounded by the capacity in link n_4-n_5 
        link_p_in = first(value.(m[:link_potential_in][l, :, :]))
        link_p_out = first(value.(m[:link_potential_out][l, :, :]))
        RHS_values = calculate_rhs_taylor(link_p_in, link_p_out, l)

        flow = first(value.(m[:link_in][l, :, :]))
        @test isapprox(minimum(RHS_values), flow; atol = 1e-6)
    end
end
