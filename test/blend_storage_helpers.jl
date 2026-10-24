# Shared helpers for blend storage test items (included inside each @testitem)

function bs_resources()
    H2 = ResourceCarrier("H2", 0.0)
    CH4 = ResourceCarrier("CH4", 0.0)
    Blend = ResourcePooling("Blend", [H2, CH4])
    CO2 = ResourceEmit("CO2", 1.0)
    return H2, CH4, Blend, CO2
end

# Resources shared by the cases and the tests of a test item
const BS_RES = bs_resources()

"""
    make_blend_storage_case(; kwargs...)

Two sources (H₂ and CH₄) feed a `BlendingNode`, which charges a blend storage. The storage
discharges to a sink. By default, the sources are available in the first operational period
(summer) and the sink demands gas in the second (winter), so all delivered gas passes
through the storage.

The keyword arguments `h2`, `ch4` and `demand` are the profiles of the source capacities and
the sink demand, `storage_data` the data of the storage, `max_h2`/`min_h2` the quality
bounds of the sink, and `T` the time structure.
"""
function make_blend_storage_case(;
    resources = BS_RES,
    h2 = OperationalProfile([10.0, 0.0]),
    ch4 = OperationalProfile([90.0, 0.0]),
    demand = OperationalProfile([0.0, 100.0]),
    storage_data = nothing,
    mode = :relaxed,
    behaviour = CyclicStrategic,
    min_h2 = 0.0,
    max_h2 = 1.0,
    h2_cost = 1.0,
    level_cap = FixedProfile(1000.0),
    stor_extra_data = ExtensionData[],
    n_storage_outlets = 1,
    stor_inputs = nothing,
    T = TwoLevel(1, 1, SimpleTimes(2, 1); op_per_strat = 2),
    model = nothing,
)
    H2, CH4, Blend, CO2 = resources
    data = isnothing(storage_data) ? [BlendStorageData(Blend; mode)] : storage_data
    sinks = [
        RefSink("sink_$i", demand,
            Dict(:surplus => FixedProfile(0.0), :deficit => FixedProfile(1000.0)),
            Dict(Blend => 1),
            [
                RefBlendData(Blend, Dict(H2 => max_h2, CH4 => 1.0),
                    Dict(H2 => min_h2, CH4 => 0.0)),
            ])
        for i ∈ 1:n_storage_outlets
    ]
    nodes = [
        RefSource("src_h2", h2, FixedProfile(h2_cost), FixedProfile(0), Dict(H2 => 1)),
        RefSource("src_ch4", ch4, FixedProfile(1.0), FixedProfile(0), Dict(CH4 => 1)),
        BlendingNode("mix", FixedProfile(1000), FixedProfile(0), FixedProfile(0),
            Dict(H2 => 1.0, CH4 => 1.0), Dict(Blend => 1.0),
            [RefBlendData(Blend, Dict(H2 => 1.0, CH4 => 1.0), Dict(H2 => 0.0, CH4 => 0.0))]),
        RefStorage{behaviour}("stor",
            StorCapOpex(FixedProfile(1000), FixedProfile(0), FixedProfile(0)),
            StorCap(level_cap), Blend, something(stor_inputs, Dict(Blend => 1)),
            Dict(Blend => 1),
            vcat(data, stor_extra_data)),
        sinks...,
    ]
    links = [
        Direct("h2_mix", nodes[1], nodes[3], Linear()),
        Direct("ch4_mix", nodes[2], nodes[3], Linear()),
        Direct("charge", nodes[3], nodes[4], Linear()),
        [Direct("discharge_$i", nodes[4], s, Linear()) for (i, s) ∈ enumerate(sinks)]...,
    ]
    if isnothing(model)
        model = OperationalModel(
            Dict(CO2 => FixedProfile(0.0)), Dict(CO2 => FixedProfile(0.0)), CO2)
    end
    case = Case(T, [CO2, Blend, H2, CH4], [nodes, links], [[get_nodes, get_links]])
    return case, model, nodes, links
end

function solve_blend_storage(case, model; optimizer = EMGNSetup.mip_optimizer())
    m = create_model(case, model)
    set_optimizer(m, optimizer)
    optimize!(m)
    return m
end

"""
    check_component_levels(m, stor, 𝒯, sub; atol = 1e-5)

Return `true` if the component levels of `stor` are nonnegative and add up to the storage
level in every period.
"""
function check_component_levels(m, stor, 𝒯, sub; atol = 1e-5)
    lvl = m[:stor_level_component]
    return all(
        isapprox(sum(value(lvl[stor, t, p]) for p ∈ sub), value(m[:stor_level][stor, t]);
            atol) && all(value(lvl[stor, t, p]) ≥ -atol for p ∈ sub)
        for t ∈ 𝒯
    )
end

# Total of a component on a set of links over all periods, weighted by duration and scaling
function bs_total(m, links, 𝒯, p)
    return sum(
        value(m[:flow_component][l, t, p]) * duration(t) * scale_op_sp(t_inv, t)
        for l ∈ links, t_inv ∈ strategic_periods(𝒯) for t ∈ t_inv
    )
end
