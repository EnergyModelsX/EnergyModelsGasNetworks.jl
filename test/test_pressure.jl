using EnergyModelsBase, EnergyModelsPooling
using TimeStruct

using JuMP
using Xpress

using Test

const EMB = EnergyModelsBase
const EMP = EnergyModelsPooling

function calculate_rhs_taylor(link_p_in, link_p_out, l)
    pressure_data = first(filter(data -> data isa PressureLinkData, l.data))
    weymouth_ct = EMP.get_weymouth(pressure_data)
    POut, PIn = EMP.potential_data(pressure_data)

    # Determine the (p_in, p_out) points for the Taylor approximation
    pressures_points = [(PIn, p) for p in range(PIn, POut, length=150)[2:end]]

    # Create Taylor constraint for each point
    RHS_values = []
    for (p_in, p_out) ∈ pressures_points
        
        val_rhs = sqrt(weymouth_ct) * (
                            (p_in/(sqrt(p_in^2 - p_out^2))) * link_p_in -
                            (p_out/(sqrt(p_in^2 - p_out^2))) * link_p_out
                            )
        push!(RHS_values, val_rhs)

    end
    return RHS_values
end

function generate_case()
    # Define reasources
    NG = ResourcePotential("NG", 1.0)
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
        Dict( CO2 => StrategicProfile([0])),
        Dict( CO2 => FixedProfile(0)),
        CO2)

    # Nodes
    nodes = [
        RefSource(1, FixedProfile(200), FixedProfile(15), FixedProfile(0), Dict(NG => 1), [MaxPressureData(FixedProfile(200))]),
        RefSource(2, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(NG => 1), [MaxPressureData(FixedProfile(200))]),
        RefSource(3, FixedProfile(200), FixedProfile(5), FixedProfile(0), Dict(NG => 1), [MaxPressureData(FixedProfile(200))]),
        Compressor(4, FixedProfile(1e6), FixedProfile(0), FixedProfile(0), Dict(NG => 1), Dict(NG => 1), FixedProfile(20), FixedProfile(25), [MaxPressureData(FixedProfile(180))]),
        # GenAvailability(4, [NG]),
        RefSink(5, FixedProfile(0), Dict(:surplus => FixedProfile(-100), :deficit=> FixedProfile(1e6)), Dict(NG => 1), [MaxPressureData(FixedProfile(180)), MinPressureData(FixedProfile(1e-6))])
    ]
    links = [
        CapDirect(14, nodes[1], nodes[4], Linear(), FixedProfile(200), [PressureLinkData(0.24, 200, 0), MinPressureData(FixedProfile(1e-6))]),
        CapDirect(24, nodes[2], nodes[4], Linear(), FixedProfile(200), [PressureLinkData(0.24, 200, 0), MinPressureData(FixedProfile(1e-6))]),
        CapDirect(34, nodes[3], nodes[4], Linear(), FixedProfile(200), [PressureLinkData(0.24, 200, 0), MinPressureData(FixedProfile(1e-6))]),
        CapDirect(45, nodes[4], nodes[5], Linear(), FixedProfile(700), [PressureLinkData(0.24, 200, 0), MinPressureData(FixedProfile(1e-6))]),
    ]

    case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
    model = OperationalModel(
        Dict(CO2 => FixedProfile(0)),
        Dict(CO2 => FixedProfile(0)),
        CO2,
    )
    return case, model
end

case, model = generate_case()
m = EMP.create_model(case, model, nothing; check_timeprofiles=true)
set_optimizer(m, Xpress.Optimizer)
optimize!(m)

# Extract data from the case
𝒩 = get_nodes(case)
ℒ = get_links(case)
𝒫 = get_products(case)
𝒯 = get_time_struct(case)

# Test `create_model` builds a JuMP model without errors for typical input Cases
@testset "Model creation" begin
    @test try
        EMP.create_model(case, model, nothing; check_timeprofiles=true)
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

        @test sum(nt[1] == 𝒩[1] for nt in eachindex(m[:potential_out])) == length(𝒯)
        @test sum(nt[1] == 𝒩[2] for nt in eachindex(m[:potential_out])) == length(𝒯)
        @test sum(nt[1] == 𝒩[3] for nt in eachindex(m[:potential_out])) == length(𝒯)
    end

    @testset "Link variables" begin
        @test haskey(m, :link_potential_in)
        @test haskey(m, :link_potential_out)
        @test haskey(m, :has_flow)
    
        @test sum(nt[1] == ℒ[1] for nt in eachindex(m[:link_potential_out])) == length(𝒯)
        @test sum(nt[1] == ℒ[2] for nt in eachindex(m[:link_potential_out])) == length(𝒯)
    end
end

# Test constraints correctly defined
@testset "Constraints Definition" begin
    @testset "Nodes Internal Balance Pressure" begin
        𝒩ˢʳ = filter(n -> n isa RefSource, 𝒩)
        @test all(v -> v == 0, [value(m[:potential_in][nt]) for nt in eachindex(m[:potential_in]) if nt[1] in 𝒩ˢʳ])
        
        𝒩ˢ = filter(n -> n isa RefSink, 𝒩)
        @test all(v -> v == 0, [value(m[:potential_out][nt]) for nt in eachindex(m[:potential_out]) if nt[1] in 𝒩ˢ])
        
        𝒩ᵃ = filter(n -> n isa Availability, 𝒩)
        in_val = [value(m[:potential_in][nt]) for nt in eachindex(m[:potential_in]) if nt[1] in 𝒩ᵃ]
        out_val = [value(m[:potential_out][nt]) for nt in eachindex(m[:potential_out]) if nt[1] in 𝒩ᵃ]
        @test in_val == out_val

        𝒩ᶜ = filter(n -> n isa Compressor, 𝒩)
        in_val = [value(m[:potential_in][nt]) for nt in eachindex(m[:potential_in]) if nt[1] in 𝒩ᶜ]
        out_val = [value(m[:potential_out][nt]) for nt in eachindex(m[:potential_out]) if nt[1] in 𝒩ᶜ]
        @test all(in_val .<= out_val)

    end
end

# Test that the RHS values of the Taylor approximation are correctly calculated
@testset "RHS Taylor Approximation Calculation" begin
    for l ∈ ℒ
        link_p_in = first(value.(m[:link_potential_in][l, :, :]))
        link_p_out = first(value.(m[:link_potential_out][l, :, :]))
        RHS_values = calculate_rhs_taylor(link_p_in, link_p_out, l)

        flow = first(value.(m[:link_in][l, :, :]))
        @test isapprox(minimum(RHS_values), flow; atol=1e-6)
    end
end

# Test that the Compressor cost is correctly calculated using :potential_Δ and not :cap_use
@testset "Compressor Cost" begin
    n = first(filter(n -> n isa Compressor, 𝒩))
    opex_cost = first(value.(m[:opex_var][n, :]))

    𝒯ⁱⁿᵛ = strategic_periods(𝒯)
    for t_inv ∈ 𝒯ⁱⁿᵛ
        @test isapprox(opex_cost, sum(value.(m[:potential_Δ][n, t]) * EMB.opex_var(n, t) * EMB.scale_op_sp(t_inv, t) for t in t_inv), atol=1e-6)
    end
end

@testset "Results" begin
    NG = first(filter(p -> p.id == "NG", 𝒫))
    @test value.(m[:link_in][ℒ[1], first(collect(𝒯)), NG]) == 0.0
    @test isapprox(value.(m[:link_in][ℒ[2], first(collect(𝒯)), NG]), 29.393; atol=1e-2)
    @test isapprox(value.(m[:link_in][ℒ[3], first(collect(𝒯)), NG]), 58.788; atol=1e-2)
    @test isapprox(value.(m[:link_in][ℒ[4], first(collect(𝒯)), NG]), 88.181; atol=1e-2)

    @test value.(m[:potential_out][𝒩[1], first(collect(𝒯)), NG]) == 0.0
    @test value.(m[:potential_out][𝒩[3], first(collect(𝒯)), NG]) == 200.0

    @test value.(m[:potential_out][𝒩[4], first(collect(𝒯)), NG]) == 180.0
    @test value.(m[:potential_in][𝒩[5], first(collect(𝒯)), NG]) == 0.0
end

function generate_case2()
    # Define reasources
    NG = ResourcePotential("NG", 1.0)
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
        Dict( CO2 => StrategicProfile([0])),
        Dict( CO2 => FixedProfile(0)),
        CO2)

    # Nodes
    nodes = [
        RefSource(1, FixedProfile(200), FixedProfile(15), FixedProfile(0), Dict(NG => 1), [MaxPressureData(FixedProfile(200))]),
        RefSource(2, FixedProfile(200), FixedProfile(10), FixedProfile(0), Dict(NG => 1), [MaxPressureData(FixedProfile(200))]),
        RefSource(3, FixedProfile(200), FixedProfile(5), FixedProfile(0), Dict(NG => 1), [MaxPressureData(FixedProfile(200))]),
        # GenAvailability(4, FixedProfile(1e6), FixedProfile(0), FixedProfile(0), Dict(NG => 1), Dict(NG => 1), FixedProfile(20), FixedProfile(25)),
        GenAvailability(4, [NG]),
        RefSink(5, FixedProfile(100), Dict(:surplus => FixedProfile(-100), :deficit=> FixedProfile(1e6)), Dict(NG => 1), [MaxPressureData(FixedProfile(180)), MinPressureData(FixedProfile(1e-6))])
    ]
    links = [
        CapDirect(14, nodes[1], nodes[4], Linear(), FixedProfile(200), [PressureLinkData(0.24, 180, 0), MaxPressureData(FixedProfile(180)), MinPressureData(FixedProfile(1e-6))]),
        CapDirect(24, nodes[2], nodes[4], Linear(), FixedProfile(200), [PressureLinkData(0.24, 180, 0), MaxPressureData(FixedProfile(180)), MinPressureData(FixedProfile(1e-6))]),
        CapDirect(34, nodes[3], nodes[4], Linear(), FixedProfile(200), [PressureLinkData(0.24, 180, 0), MaxPressureData(FixedProfile(180)), MinPressureData(FixedProfile(1e-6))]),
        CapDirect(45, nodes[4], nodes[5], Linear(), FixedProfile(700), [PressureLinkData(0.24, 180, 0), MaxPressureData(FixedProfile(180)), MinPressureData(FixedProfile(1e-6))]),
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
m = EMP.create_model(case, model, nothing; check_timeprofiles=true)
set_optimizer(m, Xpress.Optimizer)
optimize!(m)

# Extract data from the case
𝒩 = get_nodes(case)
ℒ = get_links(case)
𝒫 = get_products(case)
𝒯 = get_time_struct(case)

@testset "Model creation" begin
    @test try
        EMP.create_model(case, model, nothing; check_timeprofiles=true)
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

        @test sum(nt[1] == 𝒩[1] for nt in eachindex(m[:potential_out])) == length(𝒯)
        @test sum(nt[1] == 𝒩[2] for nt in eachindex(m[:potential_out])) == length(𝒯)
        @test sum(nt[1] == 𝒩[3] for nt in eachindex(m[:potential_out])) == length(𝒯)
    end

    @testset "Link variables" begin
        @test haskey(m, :link_potential_in)
        @test haskey(m, :link_potential_out)
        @test haskey(m, :has_flow)
    
        @test sum(nt[1] == ℒ[1] for nt in eachindex(m[:link_potential_out])) == length(𝒯)
        @test sum(nt[1] == ℒ[2] for nt in eachindex(m[:link_potential_out])) == length(𝒯)
    end
end

# Test constraints correctly defined
@testset "Constraints Definition" begin
    @testset "Nodes Internal Balance Pressure" begin
        𝒩ˢʳ = filter(n -> n isa RefSource, 𝒩)
        @test all(v -> v == 0, [value(m[:potential_in][nt]) for nt in eachindex(m[:potential_in]) if nt[1] in 𝒩ˢʳ])
        
        𝒩ˢ = filter(n -> n isa RefSink, 𝒩)
        @test all(v -> v == 0, [value(m[:potential_out][nt]) for nt in eachindex(m[:potential_out]) if nt[1] in 𝒩ˢ])
        
        𝒩ᵃ = filter(n -> n isa Availability, 𝒩)
        in_val = [value(m[:potential_in][nt]) for nt in eachindex(m[:potential_in]) if nt[1] in 𝒩ᵃ]
        out_val = [value(m[:potential_out][nt]) for nt in eachindex(m[:potential_out]) if nt[1] in 𝒩ᵃ]
        @test in_val == out_val

        𝒩ᶜ = filter(n -> n isa Compressor, 𝒩)
        in_val = [value(m[:potential_in][nt]) for nt in eachindex(m[:potential_in]) if nt[1] in 𝒩ᶜ]
        out_val = [value(m[:potential_out][nt]) for nt in eachindex(m[:potential_out]) if nt[1] in 𝒩ᶜ]
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
        @test isapprox(minimum(RHS_values), flow; atol=1e-6)
    end
end