@testitem "BlendingNode - feasibility and quality" setup = [EMGNSetup] begin
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

    function generate_case_blending_node(; max_h2 = 0.10)
        H2 = ResourceCarrier{Float64}("H2", 0.0)
        CH4 = ResourceCarrier{Float64}("CH4", 1.0)
        CO2 = ResourceEmit{Float64}("CO2", 1.0)
        Gas = ResourcePooling("Gas", [H2, CH4])

        T = TwoLevel(1, 1, SimpleTimes(2, 1); op_per_strat = 2)

        nodes = [
            RefSource("src_h2", FixedProfile(100), FixedProfile(0), FixedProfile(0),
                Dict(H2 => 1.0)),
            RefSource("src_ch4", FixedProfile(100), FixedProfile(0), FixedProfile(0),
                Dict(CH4 => 1.0)),
            BlendingNode("blend", FixedProfile(1e6), FixedProfile(0), FixedProfile(0),
                Dict(H2 => 1.0, CH4 => 1.0), Dict(Gas => 1.0),
                [
                    RefBlendData(Gas, Dict(H2 => max_h2, CH4 => 1.0),
                        Dict(H2 => 0.0, CH4 => 0.0)),
                ]),
            RefSink("sink", FixedProfile(120),
                Dict(:surplus => FixedProfile(-50.0), :deficit => FixedProfile(1e4)),
                Dict(Gas => 1.0),
                [
                    RefBlendData(Gas, Dict(H2 => max_h2, CH4 => 1.0),
                        Dict(H2 => 0.0, CH4 => 0.0)),
                ]),
        ]
        links = [
            Direct("h2_blend", nodes[1], nodes[3], Linear()),
            Direct("ch4_blend", nodes[2], nodes[3], Linear()),
            Direct("blend_sink", nodes[3], nodes[4], Linear()),
        ]
        products = [CO2, Gas, H2, CH4]
        case = Case(T, products, [nodes, links], [[get_nodes, get_links]])
        model_type = OperationalModel(Dict(CO2 => FixedProfile(0.0)),
            Dict(CO2 => FixedProfile(0.0)), CO2)
        return case, model_type
    end

    case_bn, model_bn = generate_case_blending_node(; max_h2 = 0.10)
    m_bn = create_model(case_bn, model_bn)
    set_optimizer(m_bn, optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false))
    optimize!(m_bn)

    𝒩_bn = get_nodes(case_bn)
    ℒ_bn = get_links(case_bn)
    𝒫_bn = get_products(case_bn)
    𝒯_bn = get_time_struct(case_bn)

    H2_bn = first(filter(p -> p.id == "H2", 𝒫_bn))
    Gas_bn = first(filter(p -> p.id == "Gas", 𝒫_bn))
    blend_bn = 𝒩_bn[3]
    l_out_bn = ℒ_bn[3]

    @testset "feasibility and quality" begin
        @test termination_status(m_bn) == MOI.OPTIMAL
        for t ∈ 𝒯_bn
            total = value(m_bn[:link_in][l_out_bn, t, Gas_bn])
            h2 = value(m_bn[:flow_component][l_out_bn, t, H2_bn])
            frac = total > 1e-6 ? h2 / total : 0.0
            @test frac ≤ 0.10 + 1e-6
        end
    end

    @testset "no proportion_out variable" begin
        @test !any(==(blend_bn), axes(m_bn[:proportion_out], 1))
    end
end
