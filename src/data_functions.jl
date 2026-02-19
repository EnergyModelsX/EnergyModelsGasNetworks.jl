"""
    EMB.constraints_ext_data(m, n::Node, 𝒯, 𝒫, modeltype::EnergyModel, data::FlowToEnergyData)

Function to convert flow rates to energy rates (e.g., Sm3/d to MWh/d). The time basis of the flow rates is preserved in the conversion.
"""
function EMB.constraints_ext_data(
    m,
    n::UnitConversion,
    𝒯,
    𝒫,
    modeltype::EMB.EnergyModel,
    data::FlowToEnergyData,
)

    # Calculate the LHV of the input resource
    𝒫ˡʰᵛ = get_specific_energy_content(data) # collects the resources if Dict{<:Resource,<:Real} (for blends) or the LHV if is a Real (for single resources)
    LHV = resource_lhv(m, n, 𝒫ˡʰᵛ, data, 𝒯)

    # Calculate the flow_out in energy units
    𝒫ⁿ = EMB.inputs(n)
    @constraint(
        m,
        [t ∈ 𝒯, p ∈ EMB.outputs(n)],
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
            get_specific_energy_content(data, p) * m[:proportion_track][n, t, p] for
            p ∈ 𝒫ˡʰᵛ
        )
    )
end
function resource_lhv(m, n::EMB.Node, LHV::Real, data::FlowToEnergyData, 𝒯)
    return @expression(m, [t ∈ 𝒯], LHV)
end
