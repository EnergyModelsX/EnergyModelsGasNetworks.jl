"""
    EMB.check_node_default(n::SimpleCompressor, 𝒯, modeltype::EnergyModel, check_timeprofiles::Bool)

Standard tests for a [`SimpleCompressor`](@ref) node.

## Checks
- At least two values in the vector `input` are required.
- The values of the vector `output` must be the difference between the resources in input and energy_resource
"""
function EMB.check_node_default(
    n::SimpleCompressor,
    𝒯,
    modeltype::EnergyModel,
    check_timeprofiles::Bool,
)
    𝒯ᴵⁿᵛ = strategic_periods(𝒯)

    @assert_or_log(
        length(inputs(n)) ≥ 2,
        "The compressor must have at least two input resources. One energy resource and the flowing resource.",
    )
    @assert_or_log(
        issubset(outputs(n), setdiff(inputs(n), [get_energy_resource(n)[1]])),
        "The output resources in SimpleCompressors must be the difference between the input resources and the energy resource.",
    )
end
