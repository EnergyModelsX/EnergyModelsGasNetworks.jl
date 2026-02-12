function EMB.check_node_default(n::UnitConversion, 𝒯, modeltype::EMB.EnergyModel, check_timeprofiles::Bool)
    𝒯ᴵⁿᵛ = strategic_periods(𝒯)

    @assert_or_log(
        length(EMB.inputs(n)) == 1,
        "UnitConversion nodes must have exactly one input resource."
    )

    @assert_or_log(
        length(EMB.outputs(n)) == 1,
        "UnitConversion nodes must have exactly one output resource."
    )
end