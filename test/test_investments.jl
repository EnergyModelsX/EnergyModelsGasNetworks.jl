function generate_case_investments()

    # Create products
    H2 = EnergyModelsPooling.ResourcePressure("H2", 0.0)
    CH4 = EnergyModelsPooling.ResourcePressure("CH4", 0.0)
    Blend = EnergyModelsPooling.ResourcePooling("Blend", [H2, CH4])
    CO2 = EnergyModelsPooling.ResourceEmit("CO2", 1.0)
    products = [H2, CH4, Blend, CO2]

    # Create time structure
    oper_period = TimeStruct.SimpleTimes(1, 1)
    T = TimeStruct.TwoLevel(2, [10, 10], [oper_period, oper_period], 8760.0)

    # Create nodes
    nodes = [
        RefSource(
            "1", #id
            FixedProfile(10), # capacity
            FixedProfile(0), # opex_var
            FixedProfile(0), # capex_fix
            Dict(H2 => 1) # output
        ),
        RefSource(
            "2", #id
            FixedProfile(30), # capacity
            FixedProfile(0), # opex_var
            FixedProfile(0), # capex_fix
            Dict(CH4 => 1) # output
        ),
        RefSource(
            "3", #id
            FixedProfile(20), # capacity
            FixedProfile(0), # opex_var
            FixedProfile(0), # capex_fix
            Dict(CH4 => 1) # output
        ),
        PoolingNode(
            "4", #id
            FixedProfile(100), # capacity
            FixedProfile(0), # opex_var
            FixedProfile(0), # capex_fix
            Dict(H2 => 1, CH4 => 1), # input products
            Dict(Blend => 1), # output products
            [
                RefBlendData{ResourcePressure{Float64}}(
                    Blend,
                    Dict(H2 => 1, CH4 => 1), # maximum fractions
                    Dict(H2 => 0.01, CH4 => 0.0), # minimum fractions
                ),
            ],
        ),
        RefSink(
            "5", #id
            FixedProfile(1), # capacity
            Dict(:surplus => FixedProfile(-240), :deficit => FixedProfile(500)), # penalty, surplus rewarded, deficit penalised
            Dict(Blend => 1, CH4 => 1), # input products
            [
                RefBlendData{ResourcePressure{Float64}}(
                    Blend,
                    Dict(H2 => 0.15, CH4 => 1.0), # maximum fractions
                    Dict(H2 => 0.01, CH4 => 0.0), # minimum fractions
                ),
            ],
        ),
        RefSink(
            "6", #id
            FixedProfile(1), # capacity
            Dict(:surplus => FixedProfile(-120), :deficit => FixedProfile(500)), # penalty, surplus rewarded, deficit penalised
            Dict(Blend => 1, CH4 => 1), # input products
            [
                RefBlendData{ResourcePressure{Float64}}(
                    Blend,
                    Dict(H2 => 0.1, CH4 => 1.0), # maximum fractions
                    Dict(H2 => 0.01, CH4 => 0.0), # minimum fractions
                ),
            ],
        ),
    ]

    investment_data = SingleInvData(
        FixedProfile(0.0), # capex
        StrategicProfile([75, 75]), # max. installed capacity per str oper_period
        BinaryInvestment(StrategicProfile([75.0, 75.0])), # investment mode
        UnlimitedLife(), # investment lifetime
    )

    pipelines = [
        CapDirect(
            "1-4", # id
            nodes[1], # from
            nodes[4], # to
            Linear(), # formulation
            FixedProfile(0), # capacity
            [
                MinPressureData(FixedProfile(1e-6)), # min pressure data
                MaxPressureData(FixedProfile(250)), # max pressure data
                PressureLinkData(0.24, 200.0, 130.0), # pressure link data, (weymouth, PIN, POUT)
                investment_data, # investment data
            ],
        ),
        CapDirect(
            "2-4", # id
            nodes[2], # from
            nodes[4], # to
            Linear(), # formulation
            FixedProfile(75), # capacity
            [
                MinPressureData(FixedProfile(1e-6)), # min pressure data
                MaxPressureData(FixedProfile(250)), # max pressure data
                PressureLinkData(0.24, 200.0, 130.0), # pressure link data, (weymouth, PIN, POUT)
            ],
        ),
        CapDirect(
            "3-5", # id
            nodes[3], # from
            nodes[5], # to
            Linear(), # formulation
            FixedProfile(75), # capacity
            [
                MinPressureData(FixedProfile(1e-6)), # min pressure data
                MaxPressureData(FixedProfile(250)), # max pressure data
                PressureLinkData(0.24, 200.0, 60.0), # pressure link data, (weymouth, PIN, POUT)
            ],
        ),
        CapDirect(
            "3-6", # id
            nodes[3], # from
            nodes[6], # to
            Linear(), # formulation
            FixedProfile(75), # capacity
            [
                MinPressureData(FixedProfile(1e-6)), # min pressure data
                MaxPressureData(FixedProfile(250)), # max pressure data
                PressureLinkData(0.24, 200.0, 60.0), # pressure link data, (weymouth, PIN, POUT)
            ],
        ),
        CapDirect(
            "4-5", # id
            nodes[4], # from
            nodes[5], # to
            Linear(), # formulation
            FixedProfile(75), # capacity
            [
                MinPressureData(FixedProfile(0)), # min pressure data
                MaxPressureData(FixedProfile(250)), # max pressure data
                PressureLinkData(0.24, 130.0, 60.0), # pressure link data, (weymouth, PIN, POUT)
                BlendLinkData(
                    Blend,
                    Dict{ResourcePressure{Float64},Float64}(H2 => 2.016), # tracking component and molar mass
                    Dict{ResourcePressure{Float64},Any}(H2 => 0.0), # tracking component molar proportion when obtaining weymouth constant
                    0.2, # max. molar proportion of tracking component considered for the PWA
                    0, # min. molar proportion of tracking component considered for the PWA
                    Dict{ResourcePressure{Float64},Float64}(CH4 => 16.4), # other components and molar masses
                ),
            ],
        ),
        CapDirect(
            "4-6", # id
            nodes[4], # from
            nodes[6], # to
            Linear(), # formulation
            FixedProfile(75), # capacity
            [
                MinPressureData(FixedProfile(0)), # min pressure data
                MaxPressureData(FixedProfile(250)), # max pressure data
                PressureLinkData(0.24, 130.0, 60.0), # pressure link data, (weymouth, PIN, POUT)
                BlendLinkData(
                    Blend,
                    Dict{ResourcePressure{Float64},Float64}(H2 => 2.016), # tracking component and molar mass
                    Dict{ResourcePressure{Float64},Any}(H2 => 0.0), # tracking component molar proportion when obtaining weymouth constant
                    0.2, # max. molar proportion of tracking component considered for the PWA
                    0, # min. molar proportion of tracking component considered for the PWA
                    Dict{ResourcePressure{Float64},Float64}(CH4 => 16.4), # other components and molar masses
                ),
            ],
        ),
    ]

    discount_rate = 0.05
    case = Case(T, products, [nodes, pipelines], [[get_nodes, get_links]])
    model = EnergyModelsBase.InvestmentModel(
        Dict(CO2 => FixedProfile(0.0)), # emission limit
        Dict(CO2 => FixedProfile(0.0)), # emission price
        CO2, # co2 instance
        discount_rate,
    )

    return case, model
end

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

    # Works for linear constraints
    vars = [v for (_, v) ∈ JuMP.linear_terms(f)]
    return var in vars
end

@testset "Investments in CapDirect links" begin
    case, model = generate_case_investments()
    EnergyModelsPooling.set_step_pressure!(10) # step pressure for the PWA approximations
    m = EnergyModelsPooling.create_model(
        case,
        model,
        mip_optimizer;
        check_timeprofiles = true,
    )

    @test num_variables(m) == 266

    # Check if the new variables for link capacity investments are created
    new_variables = [
        "link_cap_current[l_1-4,sp1]",
        "link_cap_inst[l_1-4,sp1-t1]",
        "link_cap_capex[l_1-4,sp1]",
        "link_cap_invest_b[l_1-4,sp1]",
        "link_cap_add[l_1-4,sp1]",
        "link_cap_rem[l_1-4,sp1]",
    ]
    for v_name ∈ new_variables
        v = variable_by_name(m, v_name)
        @test v !== nothing
    end

    # Check if the capacity investment constraints are created
    cs = get_all_constraints(m)
    for v_name ∈ new_variables # retrieve the variable
        v = variable_by_name(m, v_name)
        # check if at least one constraint contains the variable
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
