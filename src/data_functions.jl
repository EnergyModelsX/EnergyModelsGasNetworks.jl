"""
    EMB.constraints_ext_data(m, n::Node, 𝒯, 𝒫, modeltype::EnergyModel, data::FlowToEnergyData)

Function to convert flow rates to energy rates (e.g., Sm3/d to MWh/d). The time basis of
the flow rates is preserved in the conversion.

When the node receives a `ResourcePooling` blend input with a per-sub-resource LHV dict,
the constraint would be quadratic (`LHV(proportion_out) × flow_in`). In that case this
function **defers** constraint creation — the linearised form is added later in
`constraints_component_blend` once `flow_component` link variables exist:

    flow_out = Σ_sub  lhv_sub × flow_component[l_in, t, sub]

For scalar LHV (single-resource input), the constraint is created here directly:

    flow_out == LHV × flow_in

The scalar constraint is not applied to the CO₂ output of an `EmissionsConversionData`.
"""
function EMB.constraints_ext_data(
    m,
    n::UnitConversion,
    𝒯,
    𝒫,
    modeltype::EMB.EnergyModel,
    data::FlowToEnergyData,
)
    𝒫ˡʰᵛ = get_specific_energy_content(data)

    # When the LHV is a per-sub-resource vector and the node has a blend input, creating the
    # constraint here would produce a quadratic: LHV(proportion_out) × flow_in.
    # Defer to constraints_component_blend where flow_component variables are available.
    if 𝒫ˡʰᵛ isa Vector{<:EMB.Resource}
        blend_inputs = [p for p ∈ EMB.inputs(n) if p isa ResourcePooling]
        if !isempty(blend_inputs)
            return  # deferred — handled in constraints_component_blend
        end
    end

    # Scalar LHV: constraint is linear, safe to add now.
    LHV = resource_lhv(m, n, 𝒫ˡʰᵛ, data, 𝒯)
    𝒫ⁿ = EMB.inputs(n)
    # CO₂ outputs are set by `_constraints_unit_conversion_co2_output`
    co2_outputs = [d.co2_output for d ∈ EMB.node_data(n) if d isa EmissionsConversionData]
    𝒫ᵉ = [p for p ∈ EMB.outputs(n) if p ∉ co2_outputs]
    @constraint(
        m,
        [t ∈ 𝒯, p ∈ 𝒫ᵉ],
        m[:flow_out][n, t, p] == LHV[t] * sum(m[:flow_in][n, t, p] for p ∈ 𝒫ⁿ)
    )
end

"""
    resource_lhv(n::Node, 𝒫ˡʰᵛ::Vector{ResourcePooling}, data::FlowToEnergyData)
    resource_lhv(n::EMB.Node, 𝒫ˡʰᵛ::Vector{Resource}, data::FlowToEnergyData)

Function to calculate the LHV of the input resource for a given node with FlowToEnergyData. 
If the input resource is of type `ResourcePooling`, the LHV is calculated as the weighted average of the LHV of the individual resources in the blend. 
If the input resource is any other type of `Resource`, the LHV is simply retrieved from the data.

"""
function resource_lhv(
    m,
    n::EMB.Node,
    𝒫ˡʰᵛ::Vector{<:EMB.Resource},
    data::FlowToEnergyData,
    𝒯,
)
    return @expression(
        m,
        [t ∈ 𝒯],
        sum(
            get_specific_energy_content(data, p) * m[:proportion_out][n, t, p] for
            p ∈ 𝒫ˡʰᵛ
        )
    )
end
function resource_lhv(m, n::EMB.Node, LHV::Real, data::FlowToEnergyData, 𝒯)
    return @expression(m, [t ∈ 𝒯], LHV)
end
