"""
`EnergyContent` as supertype for all Resources.

EnergyContent is used to identify the energy content of the Resources.
"""
abstract type EnergyContent end

struct RefEnergyContent <: EnergyContent
    output::Dict{<:EMB.Resource,<:Real}
end

output(e::RefEnergyContent, p::Resource) = e.output[p]
