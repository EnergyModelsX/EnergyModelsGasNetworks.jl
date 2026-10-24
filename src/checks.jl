function EMB.check_node_default(
    n::UnitConversion,
    𝒯,
    modeltype::EMB.EnergyModel,
    check_timeprofiles::Bool,
)
    𝒯ᴵⁿᵛ = strategic_periods(𝒯)

    @assert_or_log(
        length(EMB.inputs(n)) == 1,
        "UnitConversion nodes must have exactly one input resource."
    )

    # When EmissionsConversionData is attached, exactly one CO₂ output is allowed in
    # addition to the single primary (energy) output.
    has_em_data = any(d isa EmissionsConversionData for d ∈ EMB.node_data(n))
    n_out = length(EMB.outputs(n))
    @assert_or_log(
        n_out == 1 || (has_em_data && n_out == 2),
        "UnitConversion nodes must have exactly one output resource " *
        "(or one energy + one CO₂ output when EmissionsConversionData is attached)."
    )

    # EmissionsConversionData is only linked to the CO₂ output for blend inputs
    blend_inputs = [p for p ∈ EMB.inputs(n) if p isa ResourcePooling]
    @assert_or_log(
        !has_em_data || !isempty(blend_inputs),
        "UnitConversion $(n.id): EmissionsConversionData requires a ResourcePooling input."
    )

    # A per-component LHV dict must cover every sub-resource of the blend input
    for d ∈ EMB.node_data(n)
        d isa FlowToEnergyData || continue
        𝒫ˡʰᵛ = get_specific_energy_content(d)
        𝒫ˡʰᵛ isa Vector{<:EMB.Resource} || continue
        for blend ∈ blend_inputs
            @assert_or_log(
                all(s ∈ 𝒫ˡʰᵛ for s ∈ subresources(blend)),
                "UnitConversion $(n.id): FlowToEnergyData must give the specific energy " *
                "content of every sub-resource of blend $(blend.id)."
            )
        end
    end
end

function EMB.check_node_default(
    n::BlendingNode,
    𝒯,
    modeltype::EMB.EnergyModel,
    check_timeprofiles::Bool,
)
    # Structural check: BlendingNode uses a linear formulation that is only correct
    # when there is exactly one outgoing ResourcePooling blend output. Multiple blend
    # outputs would require the bilinear pooling formulation of PoolingNode.
    n_blend_out = count(p -> p isa ResourcePooling, keys(n.output))
    @assert_or_log(
        n_blend_out == 1,
        "BlendingNode must have exactly one ResourcePooling blend in its output dict. " *
        "Found $n_blend_out. Use PoolingNode for nodes with ≥2 blend outputs."
    )
end

function EMB.check_node_default(
    n::DeblendNode,
    𝒯,
    modeltype::EMB.EnergyModel,
    check_timeprofiles::Bool,
)
    # Require exactly one blend resource in input and output
    n_blend_in  = count(p -> p isa ResourcePooling, keys(n.input))
    n_blend_out = count(p -> p isa ResourcePooling, keys(n.output))
    @assert_or_log(
        n_blend_in == 1,
        "DeblendNode must have exactly one ResourcePooling blend in its input dict. Found $n_blend_in."
    )
    @assert_or_log(
        n_blend_out == 1,
        "DeblendNode must have exactly one ResourcePooling blend in its output dict. Found $n_blend_out."
    )

    # Require a DeblendData entry with a valid fraction
    deblend_data = filter(d -> d isa DeblendData, n.data)
    @assert_or_log(
        !isempty(deblend_data),
        "DeblendNode $(n.id): data must include a DeblendData entry."
    )
    if !isempty(deblend_data)
        α = max_extract_fraction(first(deblend_data))
        @assert_or_log(
            0.0 ≤ α ≤ 1.0,
            "DeblendNode $(n.id): max_extract_fraction must be in [0, 1], got $α."
        )
    end

    # Require at least one extracted sub-resource (blend sub-resource also in outputs)
    if n_blend_in == 1
        blend = first(p for p ∈ keys(n.input) if p isa ResourcePooling)
        n_extracted = count(p -> p ∈ subresources(blend), keys(n.output))
        @assert_or_log(
            n_extracted ≥ 1,
            "DeblendNode $(n.id): output dict must include at least one sub-resource of the blend " *
            "(the resource to be extracted). None found."
        )
    end
end

"""
    EMB.check_node_data(n::EMB.Node, data::BlendStorageData, 𝒯, modeltype::EMB.EnergyModel, check_timeprofiles::Bool)

Check that a [`BlendStorageData`](@ref) is valid:

- the node is a `Storage` with a `Cyclic` behaviour that stores the blend of the data,
- the node has only one `BlendStorageData`,
- the sub-resources of the blend are not inputs or outputs of the node, and
- in mode `:prescribed`, the composition is given for all sub-resources, lies in [0, 1]
  and sums to 1 in every operational period.
"""
function EMB.check_node_data(
    n::EMB.Node,
    data::BlendStorageData,
    𝒯,
    modeltype::EMB.EnergyModel,
    check_timeprofiles::Bool,
)
    blend = data.blend
    sub = subresources(blend)
    @assert_or_log(
        n isa EMB.Storage{<:EMB.Cyclic},
        "Node $(n.id): BlendStorageData requires a Storage with a Cyclic storage behaviour."
    )
    n isa EMB.Storage || return
    @assert_or_log(
        EMB.storage_resource(n) == blend,
        "Storage $(n.id): BlendStorageData is given for blend $(blend.id), but the storage " *
        "stores $(EMB.storage_resource(n).id)."
    )
    @assert_or_log(
        count(d -> d isa BlendStorageData, EMB.node_data(n)) == 1,
        "Storage $(n.id): only one BlendStorageData can be added to a node."
    )
    @assert_or_log(
        !any(p -> p ∈ sub, vcat(EMB.inputs(n), EMB.outputs(n))),
        "Storage $(n.id): the sub-resources of blend $(blend.id) can not be inputs or " *
        "outputs of a blend storage."
    )
    get_storage_mode(data) == :prescribed || return
    comp = data.discharge_composition
    @assert_or_log(
        Set(keys(comp)) == Set(sub),
        "Storage $(n.id): the discharge composition must be given for each sub-resource " *
        "of blend $(blend.id)."
    )
    Set(keys(comp)) == Set(sub) || return
    @assert_or_log(
        all(0 ≤ comp[p][t] ≤ 1 for p ∈ sub, t ∈ 𝒯),
        "Storage $(n.id): the discharge composition must lie in [0, 1]."
    )
    @assert_or_log(
        all(isapprox(sum(comp[p][t] for p ∈ sub), 1; atol = 1e-6) for t ∈ 𝒯),
        "Storage $(n.id): the discharge composition must sum to 1 in every period."
    )
end
