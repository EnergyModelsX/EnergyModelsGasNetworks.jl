"""
    EMB.constraints_capacity(m, l::CapDirect, 𝒯, modeltype::EMB.EnergyModel)

Function for creating the constraints on the maximum capacity of a link `CapDirect`.
"""
function EMB.constraints_capacity(m, l::CapDirect, 𝒯, modeltype::EMB.EnergyModel)
    @constraint(m, [t ∈ 𝒯, p ∈ EMB.link_res(l)],
        m[:link_in][l, t, p] <= m[:link_cap_inst][l, t]
    )
end

"""
    EMB.constraints_flow_in(m, n::PoolingNode, 𝒯::TimeStructure, modeltype::EMB.EnergyModel)

Function for creating the constraint on the inlet flow of a `PoolingNode`. The sum of the flows
from all input links must be equal to the used capacity of the node. It differs from generic
nodes in that it is not defined as a proportion of the :input and :output fields.
"""
function EMB.constraints_flow_in(
    m,
    n::PoolingNode,
    𝒯::TimeStructure,
    modeltype::EMB.EnergyModel,
)
    # Declaration of the required subsets
    𝒫ⁱⁿ = EMB.inputs(n)

    # Constraint for the individual input stream connections
    @constraint(m, [t ∈ 𝒯],
        sum(m[:flow_in][n, t, p] for p ∈ 𝒫ⁱⁿ) == m[:cap_use][n, t]
    )
end

"""
    Temporal function before integrating Compressors correctly
"""
function EMB.constraints_opex_var(m, n::SimpleCompressor, 𝒯ᴵⁿᵛ, modeltype::EMB.EnergyModel)
    @constraint(m, [t_inv ∈ 𝒯ᴵⁿᵛ],
        m[:opex_var][n, t_inv] == sum(
            m[:potential_Δ][n, t] * EMB.opex_var(n, t) * EMB.scale_op_sp(t_inv, t) for
            t ∈ t_inv
        ))
end

"""
    Temporal function before integrating Compressors correctly. This adds a penalty for increasing link_potential_in and link_potential_out.
"""
function EMB.constraints_opex_var(m, l::CapDirect, 𝒯ᴵⁿᵛ, modeltype::EnergyModel) # TODO: Modify to be able to associate a cost to CapDirect (e.g., mantainance)
    𝒫ˡ = EMB.link_res(l)

    if any(p -> p isa ResourcePressure || p isa ResourcePooling{<:ResourcePressure}, 𝒫ˡ)
        @constraint(m, [t_inv ∈ 𝒯ᴵⁿᵛ],
            m[:link_opex_var][l, t_inv] ==
            0.01 * sum(
                m[:link_potential_in][l, t, p] + m[:link_potential_out][l, t, p]
                for p ∈ 𝒫ˡ, t ∈ t_inv
            ))
    else
        @constraint(m, [t_inv ∈ 𝒯ᴵⁿᵛ],
            m[:link_opex_var][l, t_inv] == 0)
    end
end
function EMB.constraints_opex_fixed(m, l::CapDirect, 𝒯ᴵⁿᵛ, modeltype::EnergyModel)
    @constraint(m, [t_inv ∈ 𝒯ᴵⁿᵛ],
        m[:link_opex_fixed][l, t_inv] == 0)
end
