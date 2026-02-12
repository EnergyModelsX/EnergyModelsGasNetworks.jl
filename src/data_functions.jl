"""
    EMB.constraints_ext_data(m, n::Node, 𝒯, 𝒫, modeltype::EnergyModel, data::FlowToEnergyData)

Function to convert flow rates to energy units (e.g., Sm3/d to MWh)
"""
function EMB.constraints_ext_data(m, n::UnitConversion, 𝒯, 𝒫, modeltype::EMB.EnergyModel, data::FlowToEnergyData)
    𝒫ⁿ = EMB.inputs(n)

    # Get the time conversion factor
    Δt = get_time_factor(data)

    # Calculate the volume at each timestep for the input resource
    volume = @expression(m, [t ∈ 𝒯], sum(m[:flow_in][n, t, p] for p in 𝒫ⁿ) * Δt)

    # Calculate the LHV of the input resource
    𝒫ˡʰᵛ = get_LHV(data)
    LHV = resource_lhv(m, n, 𝒫ˡʰᵛ, data, 𝒯)

    # Calculate the flow_out in energy units
    @constraint(m, [t ∈ 𝒯, p ∈ EMB.outputs(n)], m[:flow_out][n, t, p] == LHV[t] * volume[t])

end

"""
    resource_lhv(n::Node, 𝒫ˡʰᵛ::Vector{ResourcePooling}, data::FlowToEnergyData)
    resource_lhv(n::EMB.Node, 𝒫ˡʰᵛ::Vector{Resource}, data::FlowToEnergyData)

Function to calculate the LHV of the input resource for a given node with FlowToEnergyData. 
If the input resource is of type `ResourcePooling`, the LHV is calculated as the weighted average of the LHV of the individual resources in the blend. 
If the input resource is any other type of `Resource`, the LHV is simply retrieved from the data.

"""
function resource_lhv(m, n::EMB.Node, 𝒫ˡʰᵛ::Vector{ResourcePooling}, data::FlowToEnergyData, 𝒯)
    return @expression(m, [t ∈ 𝒯], sum(get_LHV(data, p) * m[:proportion_track][n, t, p] for p in 𝒫ˡʰᵛ))
end
function resource_lhv(m, n::EMB.Node, 𝒫ˡʰᵛ::Vector{<:EMB.Resource}, data::FlowToEnergyData, 𝒯)
    p = first(𝒫ˡʰᵛ)
    return @expression(m, [t ∈ 𝒯], get_LHV(data, p))
end