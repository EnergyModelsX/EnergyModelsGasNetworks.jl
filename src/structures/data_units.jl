"""
    abstract type UnitsData <: EMB.ExtensionData

Abstract type for data used in conversion units (`UnitConversion`).
"""
abstract type UnitsData <: EMB.ExtensionData end

"""
    struct FlowToEnergyData <: UnitsData

Data structure for converting flow units to energy units in `UnitConversion` nodes.
# Fields
- **`specific_energy_content::Union{Real, Dict{<:Resource,<:Real}}`** it contains the specific energy content of the resources involved in the conversion.
If the input into the `UnitConversion` node is a single resource, it is enough to provide the value as a `Real`. 
If the input into the `UnitConversion` node is a `ResourcePooling`, one must provide a `Dict{<:Resource,<:Real}` with the specific energy content of each resource in the blend.
"""
struct FlowToEnergyData <: UnitsData
    specific_energy_content::Union{Real,Dict{<:Resource,<:Real}} #TODO: Ask Gassco about the conversion we need.
end

"""
    get_LHV(data::FlowToEnergyData)
    get_LHV(data::FlowToEnergyData, p::EMB.Resource) 

Collects the resources if Dict{<:Resource,<:Real} (used for ResourcePooling) or the LHV if is a Real (for other types of resources)
If the resource `p` is specified, retrieves the LHV for that specific resource from the dictionary.
"""
function get_specific_energy_content(data::FlowToEnergyData)
    if isa(data.specific_energy_content, Real)
        return data.specific_energy_content
    elseif isa(data.specific_energy_content, Dict{<:Resource,<:Real})
        return collect(keys(data.specific_energy_content))
    end
end
get_specific_energy_content(data::FlowToEnergyData, p::EMB.Resource) =
    data.specific_energy_content[p]
