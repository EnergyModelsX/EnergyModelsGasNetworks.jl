"""
`EnergyContent` as supertype for all Resources.

EnergyContent is used to identify the energy content of the Resources.
"""
abstract type EnergyContent end

struct RefEnergyContent <: EnergyContent
    output::Dict{<:EMB.Component, <:Real}
end

output(e::RefEnergyContent, p::Component) = e.output[p]
