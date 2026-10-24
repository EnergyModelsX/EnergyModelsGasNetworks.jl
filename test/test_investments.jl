@testitem "Investments - CapDirect links" setup = [EMGNSetup] begin
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

    function get_all_constraints(model)
        cs = ConstraintRef[]
        for (F, S) ∈ JuMP.list_of_constraint_types(model)
            append!(cs, JuMP.all_constraints(model, F, S))
        end
        return cs
    end
    function constraint_contains_var(cref, var)
        obj = JuMP.constraint_object(cref)
        f = obj.func
        vars = [v for (_, v) ∈ JuMP.linear_terms(f)]
        return var in vars
    end

    function generate_case_investments()
        H2 = ResourcePressure("H2", 0.0)
        CH4 = ResourcePressure("CH4", 0.0)
        Blend = ResourcePooling("Blend", [H2, CH4])
        CO2 = ResourceEmit("CO2", 1.0)
        products = [H2, CH4, Blend, CO2]

        oper_period = TimeStruct.SimpleTimes(1, 1)
        T = TimeStruct.TwoLevel(2, [10, 10], [oper_period, oper_period], 8760.0)

        nodes = [
            RefSource(
                "1",
                FixedProfile(10),
                FixedProfile(0),
                FixedProfile(0),
                Dict(H2 => 1),
            ),
            RefSource(
                "2",
                FixedProfile(30),
                FixedProfile(0),
                FixedProfile(0),
                Dict(CH4 => 1),
            ),
            RefSource(
                "3",
                FixedProfile(20),
                FixedProfile(0),
                FixedProfile(0),
                Dict(CH4 => 1),
            ),
            PoolingNode("4", FixedProfile(100), FixedProfile(0), FixedProfile(0),
                Dict(H2 => 1, CH4 => 1), Dict(Blend => 1),
                [
                    RefBlendData{ResourcePressure{Float64}}(Blend,
                        Dict(H2 => 1, CH4 => 1), Dict(H2 => 0.01, CH4 => 0.0)),
                ]),
            RefSink("5", FixedProfile(1),
                Dict(:surplus => FixedProfile(-240), :deficit => FixedProfile(500)),
                Dict(Blend => 1, CH4 => 1),
                [
                    RefBlendData{ResourcePressure{Float64}}(Blend,
                        Dict(H2 => 0.15, CH4 => 1.0), Dict(H2 => 0.01, CH4 => 0.0)),
                ]),
            RefSink("6", FixedProfile(1),
                Dict(:surplus => FixedProfile(-120), :deficit => FixedProfile(500)),
                Dict(Blend => 1, CH4 => 1),
                [
                    RefBlendData{ResourcePressure{Float64}}(Blend,
                        Dict(H2 => 0.1, CH4 => 1.0), Dict(H2 => 0.01, CH4 => 0.0)),
                ]),
        ]

        investment_data = SingleInvData(FixedProfile(0.0), StrategicProfile([75, 75]),
            BinaryInvestment(StrategicProfile([75.0, 75.0])), UnlimitedLife())

        pipelines = [
            CapDirect("1-4", nodes[1], nodes[4], Linear(), FixedProfile(0),
                [MinPressureData(FixedProfile(1e-6)),
                    MaxPressureData(FixedProfile(250)),
                    PressureLinkData(0.24, 200.0, 130.0), investment_data]),
            CapDirect("2-4", nodes[2], nodes[4], Linear(), FixedProfile(75),
                [MinPressureData(FixedProfile(1e-6)),
                    MaxPressureData(FixedProfile(250)),
                    PressureLinkData(0.24, 200.0, 130.0)]),
            CapDirect("3-5", nodes[3], nodes[5], Linear(), FixedProfile(75),
                [MinPressureData(FixedProfile(1e-6)),
                    MaxPressureData(FixedProfile(250)),
                    PressureLinkData(0.24, 200.0, 60.0)]),
            CapDirect("3-6", nodes[3], nodes[6], Linear(), FixedProfile(75),
                [MinPressureData(FixedProfile(1e-6)),
                    MaxPressureData(FixedProfile(250)),
                    PressureLinkData(0.24, 200.0, 60.0)]),
            CapDirect("4-5", nodes[4], nodes[5], Linear(), FixedProfile(75),
                [MinPressureData(FixedProfile(0)), MaxPressureData(FixedProfile(250)),
                    PressureLinkData(0.24, 130.0, 60.0),
                    BlendLinkData(Blend,
                        Dict{ResourcePressure{Float64},Float64}(H2 => 2.016),
                        Dict{ResourcePressure{Float64},Any}(H2 => 0.0),
                        0.2, 0,
                        Dict{ResourcePressure{Float64},Float64}(CH4 => 16.4))]),
            CapDirect("4-6", nodes[4], nodes[6], Linear(), FixedProfile(75),
                [MinPressureData(FixedProfile(0)), MaxPressureData(FixedProfile(250)),
                    PressureLinkData(0.24, 130.0, 60.0),
                    BlendLinkData(Blend,
                        Dict{ResourcePressure{Float64},Float64}(H2 => 2.016),
                        Dict{ResourcePressure{Float64},Any}(H2 => 0.0),
                        0.2, 0,
                        Dict{ResourcePressure{Float64},Float64}(CH4 => 16.4))]),
        ]

        case = Case(T, products, [nodes, pipelines], [[get_nodes, get_links]])
        model = EnergyModelsBase.InvestmentModel(
            Dict(CO2 => FixedProfile(0.0)), Dict(CO2 => FixedProfile(0.0)), CO2, 0.05)
        return case, model
    end

    EMGNSetup.setup_pwa!()
    case, model = generate_case_investments()
    m = create_model(case, model; check_timeprofiles = true)

    new_variables = [
        "link_cap_current[l_1-4,sp1]", "link_cap_inst[l_1-4,sp1-t1]",
        "link_cap_capex[l_1-4,sp1]", "link_cap_invest_b[l_1-4,sp1]",
        "link_cap_add[l_1-4,sp1]", "link_cap_rem[l_1-4,sp1]",
    ]
    for v_name ∈ new_variables
        v = variable_by_name(m, v_name)
        @test !isnothing(v)
    end

    cs = get_all_constraints(m)
    for v_name ∈ new_variables
        v = variable_by_name(m, v_name)
        found = false
        for cref ∈ cs
            if constraint_contains_var(cref, v)
                found = true
                break
            end
        end
        @test found == true
    end
end

@testitem "Investments - pressure-link capacity" setup = [EMGNSetup] begin
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

    function generate_pressure_link_investment_case(initial_capacity)
        NG = ResourcePressure("NG", 0.0)
        CO2 = ResourceEmit("CO2", 1.0)
        T = TwoLevel(1, 1, SimpleTimes(1, 1); op_per_strat = 1)

        source =
            RefSource("source", FixedProfile(30.0), FixedProfile(0.0), FixedProfile(0.0),
                Dict(NG => 1.0), [FixPressureData(FixedProfile(200.0))])
        sink = RefSink("sink", FixedProfile(20.0),
            Dict(:surplus => FixedProfile(1e6), :deficit => FixedProfile(1e6)),
            Dict(NG => 1.0), [FixPressureData(FixedProfile(100.0))])
        investment_data = SingleInvData(FixedProfile(0.0), FixedProfile(30.0),
            ContinuousInvestment(FixedProfile(0.0), FixedProfile(30.0)), UnlimitedLife(),
        )
        link = CapDirect("investable", source, sink, Linear(),
            FixedProfile(initial_capacity),
            [PressureLinkData(1.0, 200.0, 100.0), investment_data])

        case = Case(T, [NG, CO2], [[source, sink], [link]], [[get_nodes, get_links]])
        model = InvestmentModel(Dict(CO2 => FixedProfile(0.0)),
            Dict(CO2 => FixedProfile(0.0)), CO2, 0.05)
        return case, model, link
    end

    for initial_capacity ∈ (0.0, 5.0)
        case, model, link = generate_pressure_link_investment_case(initial_capacity)
        m = create_model(case, model; check_timeprofiles = true)
        set_optimizer(m, EMGNSetup.mip_optimizer())
        optimize!(m)

        t = first(get_time_struct(case))
        flow = value(m[:link_in][link, t, first(EMB.link_res(link))])
        installed = value(m[:link_cap_inst][link, t])

        @test termination_status(m) == MOI.OPTIMAL
        @test flow ≈ 20.0 atol = 1e-6
        @test installed >= flow - 1e-6
        @test flow > initial_capacity + 1e-6
    end
end
