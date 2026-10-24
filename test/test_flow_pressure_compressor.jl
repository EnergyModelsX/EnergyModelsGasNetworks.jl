@testitem "FlowPressureCompressor - operational" setup = [EMGNSetup] begin
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

    const P_SRC_OPER = 30.0
    const P_MIN_SINK = 20.0
    const Q_SOURCE = 10.0
    const W_PIPE = 1 / 60
    const W_P_IN = 80.0
    const W_P_OUT = 20.0
    const MAX_ΔP = 150.0
    const FLOW_W = 0.5
    const PRES_W = 0.01
    const EXP_Δp = 50.0
    const EXP_POWER = FLOW_W * Q_SOURCE + PRES_W * EXP_Δp

    function make_fpc_case(; investable::Bool = false, p_source = P_SRC_OPER)
        H2 = ResourcePressure("H2", 0.0)
        Power = ResourceCarrier("Power", 0.0)
        CO2 = ResourceEmit("CO2", 1.0)
        products = [H2, Power, CO2]
        T = TwoLevel(1, 1, SimpleTimes(1, 1); op_per_strat = 1)
        cap_comp = investable ? 0.0 : Q_SOURCE
        comp_data =
            investable ?
            [
                SingleInvData(FixedProfile(0.1), FixedProfile(Q_SOURCE * 2),
                    ContinuousInvestment(FixedProfile(0.0), FixedProfile(Q_SOURCE * 2)),
                    UnlimitedLife()),
            ] : ExtensionData[]
        nodes = [
            RefSource("h2_src", FixedProfile(Q_SOURCE), FixedProfile(0),
                FixedProfile(0),
                Dict(H2 => 1), [FixPressureData(FixedProfile(p_source))]),
            RefSource("pwr_src", FixedProfile(1000), FixedProfile(0.001),
                FixedProfile(0),
                Dict(Power => 1), [FixPressureData(FixedProfile(0.0))]),
            FlowPressureCompressor("comp", FixedProfile(cap_comp), FixedProfile(0),
                FixedProfile(0), Dict(H2 => 1, Power => 1), Dict(H2 => 1),
                FixedProfile(MAX_ΔP), FixedProfile(FLOW_W), FixedProfile(PRES_W),
                comp_data),
            RefSink("h2_sink", FixedProfile(0),
                Dict(:surplus => FixedProfile(-1000.0), :deficit => FixedProfile(1000.0)),
                Dict(H2 => 1), [MinPressureData(FixedProfile(P_MIN_SINK))]),
        ]
        links = [
            Direct("h2_to_comp", nodes[1], nodes[3], Linear()),
            Direct("pwr_to_comp", nodes[2], nodes[3], Linear()),
            CapDirect("comp_to_sink", nodes[3], nodes[4], Linear(),
                FixedProfile(Q_SOURCE * 2),
                [PressureLinkData(W_PIPE, W_P_IN, W_P_OUT),
                    MinPressureData(FixedProfile(P_MIN_SINK))]),
        ]
        co2_null = Dict(CO2 => FixedProfile(1e6))
        co2_price = Dict(CO2 => FixedProfile(0.0))
        model =
            investable ?
            InvestmentModel(co2_null, co2_price, CO2, 0.05) :
            OperationalModel(co2_null, co2_price, CO2)
        case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
        return case, model, nodes, links
    end

    case, model, nodes, links = make_fpc_case(; investable = false)
    m = create_model(case, model)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)

    @test termination_status(m) == MOI.OPTIMAL

    𝒯 = case.T
    comp = nodes[3]
    pipe = links[3]
    H2 = first(p for p ∈ case.products if p isa ResourcePressure)
    Power = first(p for p ∈ case.products if p isa ResourceCarrier)
    t = first(𝒯)

    q_val = value(m[:cap_use][comp, t])
    Δp_val = value(m[:potential_Δ][comp, t])
    pwr_val = value(m[:flow_in][comp, t, Power])

    @test isapprox(q_val, Q_SOURCE; atol = 1e-4)
    @test isapprox(Δp_val, EXP_Δp; atol = 1e-3)
    @test isapprox(pwr_val, EXP_POWER; atol = 1e-3)
    @test pwr_val ≥ FLOW_W * q_val + PRES_W * Δp_val - 1e-6

    p_in_val = value(m[:potential_in][comp, t, H2])
    p_out_val = value(m[:potential_out][comp, t, H2])
    @test isapprox(p_in_val, P_SRC_OPER; atol = 1e-4)
    @test isapprox(p_out_val, P_SRC_OPER + EXP_Δp; atol = 1e-3)
    @test isapprox(p_out_val, p_in_val + Δp_val; atol = 1e-6)
    @test isapprox(value(m[:link_in][pipe, t, H2]), Q_SOURCE; atol = 1e-4)
end

@testitem "FlowPressureCompressor - investment" setup = [EMGNSetup] begin
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

    const P_SRC_INVEST = 5.0
    const P_MIN_SINK = 20.0
    const Q_SOURCE = 10.0
    const W_PIPE = 1 / 60
    const W_P_IN = 80.0
    const W_P_OUT = 20.0
    const MAX_ΔP = 150.0
    const FLOW_W = 0.5
    const PRES_W = 0.01

    function make_fpc_case(; investable::Bool = false, p_source = P_SRC_INVEST)
        H2 = ResourcePressure("H2", 0.0)
        Power = ResourceCarrier("Power", 0.0)
        CO2 = ResourceEmit("CO2", 1.0)
        products = [H2, Power, CO2]
        T = TwoLevel(1, 1, SimpleTimes(1, 1); op_per_strat = 1)
        cap_comp = investable ? 0.0 : Q_SOURCE
        comp_data =
            investable ?
            [
                SingleInvData(FixedProfile(0.1), FixedProfile(Q_SOURCE * 2),
                    ContinuousInvestment(FixedProfile(0.0), FixedProfile(Q_SOURCE * 2)),
                    UnlimitedLife()),
            ] : ExtensionData[]
        nodes = [
            RefSource("h2_src", FixedProfile(Q_SOURCE), FixedProfile(0),
                FixedProfile(0),
                Dict(H2 => 1), [FixPressureData(FixedProfile(p_source))]),
            RefSource("pwr_src", FixedProfile(1000), FixedProfile(0.001),
                FixedProfile(0),
                Dict(Power => 1), [FixPressureData(FixedProfile(0.0))]),
            FlowPressureCompressor("comp", FixedProfile(cap_comp), FixedProfile(0),
                FixedProfile(0), Dict(H2 => 1, Power => 1), Dict(H2 => 1),
                FixedProfile(MAX_ΔP), FixedProfile(FLOW_W), FixedProfile(PRES_W),
                comp_data),
            RefSink("h2_sink", FixedProfile(0),
                Dict(:surplus => FixedProfile(-1000.0), :deficit => FixedProfile(1000.0)),
                Dict(H2 => 1), [MinPressureData(FixedProfile(P_MIN_SINK))]),
        ]
        links = [
            Direct("h2_to_comp", nodes[1], nodes[3], Linear()),
            Direct("pwr_to_comp", nodes[2], nodes[3], Linear()),
            CapDirect("comp_to_sink", nodes[3], nodes[4], Linear(),
                FixedProfile(Q_SOURCE * 2),
                [PressureLinkData(W_PIPE, W_P_IN, W_P_OUT),
                    MinPressureData(FixedProfile(P_MIN_SINK))]),
        ]
        co2_null = Dict(CO2 => FixedProfile(1e6))
        co2_price = Dict(CO2 => FixedProfile(0.0))
        model =
            investable ?
            InvestmentModel(co2_null, co2_price, CO2, 0.05) :
            OperationalModel(co2_null, co2_price, CO2)
        case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
        return case, model, nodes, links
    end

    case, model, nodes, _ = make_fpc_case(; investable = true, p_source = P_SRC_INVEST)
    m = create_model(case, model)
    set_optimizer(m, EMGNSetup.mip_optimizer())
    optimize!(m)

    @test termination_status(m) ∈ [MOI.OPTIMAL, MOI.LOCALLY_SOLVED]

    𝒯 = case.T
    comp = nodes[3]
    t_inv = first(strategic_periods(𝒯))
    t_op = first(𝒯)

    cap_add_val = value(m[:cap_add][comp, t_inv])
    @test cap_add_val > 0.1
    @test value(m[:cap_use][comp, t_op]) > 0.1

    H2 = first(p for p ∈ case.products if p isa ResourcePressure)
    Power = first(p for p ∈ case.products if p isa ResourceCarrier)
    q_val = value(m[:cap_use][comp, t_op])
    Δp_val = value(m[:potential_Δ][comp, t_op])
    pwr_val = value(m[:flow_in][comp, t_op, Power])
    @test pwr_val ≥ FLOW_W * q_val + PRES_W * Δp_val - 1e-6
end
