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
    specific_energy_content::Union{Real,Dict{<:Resource,<:Real}}
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

"""
    struct EmissionsConversionData <: UnitsData

Data structure for tracking CO₂ emissions from blend combustion in a `UnitConversion` node.

When attached to a `UnitConversion` node, a deferred constraint (added after blend component
variables are available) sets the `CO₂_emitted` output flow equal to the sum of per-subresource
CO₂ intensities weighted by the blend component flows:

    flow_out[n, t, co2_res] = Σ_s  co2_intensity[s] × flow_component[l_in, t, s]

The `co2_output` resource must be listed as an output of the `UnitConversion` node (alongside
the energy output), and must be connected via a link to a dedicated CO₂ acceptance sink node
whose `surplus` encodes the ETS cost.

# Fields
- **`co2_intensity::Dict{<:Resource, <:Real}`**: CO₂ intensity in tCO₂/MSm³ for each
  sub-resource of the blend input. Typically `CH4 => 0.2039, H2 => 0.0`.
- **`co2_output::Resource`**: The output resource used to carry CO₂ emissions (e.g.
  `CO2_emitted`). Must be listed in the node's output dict.
"""
struct EmissionsConversionData <: UnitsData
    co2_intensity::Dict{<:Resource,<:Real}
    co2_output::Resource
end

"""
    get_co2_intensity(data::EmissionsConversionData, p::EMB.Resource)

Return the CO₂ intensity [tCO₂/MSm³] for sub-resource `p`. Returns `0.0` if `p` is not
present in the `co2_intensity` dict.
"""
get_co2_intensity(data::EmissionsConversionData, p::EMB.Resource) =
    get(data.co2_intensity, p, 0.0)

"""
    struct DeblendData <: EMB.ExtensionData

Extension data for [`DeblendNode`](@ref), specifying the separation parameters of the PSA
(pressure-swing adsorption) or membrane unit.

# Fields
- **`max_extract_fraction::Float64`**: Maximum H₂ extraction fraction [0, 1]. For example,
  `0.9` means up to 90 % of the arriving H₂ flow can be deblended into pure H₂ product.
  The remaining H₂ (and all CH₄) continues in the outgoing blend.
- **`psa_efficiency::Float64`**: PSA process efficiency η ∈ (0, 1]. For every unit of H₂
  extracted from the blend, only η units are delivered downstream; the remaining (1−η) is
  consumed internally by the PSA (purge gas, re-pressurisation). Default `1.0` (lossless).
  Example: `0.9` means 10 % of extracted H₂ is consumed by the PSA itself.
"""
struct DeblendData <: EMB.ExtensionData
    max_extract_fraction::Float64
    psa_efficiency::Float64
    function DeblendData(max_extract_fraction::Float64, psa_efficiency::Float64 = 1.0)
        0.0 < psa_efficiency ≤ 1.0 ||
            error("psa_efficiency must be in (0, 1]; got $psa_efficiency")
        0.0 ≤ max_extract_fraction ≤ 1.0 ||
            error("max_extract_fraction must be in [0, 1]; got $max_extract_fraction")
        return new(max_extract_fraction, psa_efficiency)
    end
end

"""
    max_extract_fraction(data::DeblendData) -> Float64
    max_extract_fraction(n::DeblendNode)    -> Float64

Return the maximum H₂ extraction fraction [0, 1] from a [`DeblendData`](@ref) instance
or directly from a [`DeblendNode`](@ref).
"""
max_extract_fraction(data::DeblendData) = data.max_extract_fraction
function max_extract_fraction(n)
    d = filter(x -> x isa DeblendData, n.data)
    isempty(d) && error("DeblendNode $(n.id) has no DeblendData.")
    return max_extract_fraction(first(d))
end

"""
    psa_efficiency(data::DeblendData) -> Float64
    psa_efficiency(n::DeblendNode)    -> Float64

Return the PSA process efficiency η ∈ (0, 1] from a [`DeblendData`](@ref) instance or
directly from a [`DeblendNode`](@ref). For every unit of H₂ extracted from the blend,
η units are delivered downstream and (1−η) are consumed by the PSA internally.
"""
psa_efficiency(data::DeblendData) = data.psa_efficiency
function psa_efficiency(n)
    d = filter(x -> x isa DeblendData, n.data)
    isempty(d) && error("DeblendNode $(n.id) has no DeblendData.")
    return psa_efficiency(first(d))
end

"""
    DeblendNode(id, cap, opex_var, opex_fixed, input, output, deblend_data::DeblendData)

Convenience constructor for [`DeblendNode`](@ref) that wraps a single `DeblendData` entry
into the `data` vector automatically.
"""
function DeblendNode(
    id,
    cap::TimeProfile,
    opex_var::TimeProfile,
    opex_fixed::TimeProfile,
    input::Dict{<:Resource,<:Real},
    output::Dict{<:Resource,<:Real},
    deblend_data::DeblendData,
)
    return DeblendNode(id, cap, opex_var, opex_fixed, input, output, Data[deblend_data])
end
