""" 
    EMB.variables_node(m, 𝒩ᶜ::Vector{<:Compressor}, 𝒯, modeltype::EMB.EnergyModel)

When the node vector is a `Vector{<:Compressor}` the potential increase (`potential_Δ`) variables are created for each compressor and timestep.
"""
function EMB.variables_node(m, 𝒩ᶜ::Vector{<:Compressor}, 𝒯, modeltype::EnergyModel)
    @show "Creating potential increase variables for compressors"
    @variable(m, potential_Δ[𝒩ᶜ, 𝒯] >= 0)
end

"""
    EMB.variables_flow_resource(m, 𝒩::Vector{<:EMB.Node}, 𝒫::Vector{<:ResourcePressure}, 𝒯, modeltype::EMB.EnergyModel)
    EMB.variables_flow_resource(m, 𝒩::Vector{<:EMB.Node}, 𝒫::Vector{<:ResourcePooling}, 𝒯, modeltype::EMB.EnergyModel)  

Define additional potential and blending variables for nodes depending on the resources in the system.
If exists 𝒫::Vector{<:ResourcePressure} then we create potential variables
If exists 𝒫::Vector{<:ResourcePooling{Any}} then we create blending proportion variables
"""
function EMB.variables_flow_resource(
    m,
    𝒩::Vector{<:EMB.Node},
    𝒫::Vector{<:ResourcePressure},
    𝒯,
    modeltype::EMB.EnergyModel,
)
    @variable(m, potential_in[n ∈ 𝒩, 𝒯, EMB.inputs(n)] >= 0)
    @variable(m, potential_out[n ∈ 𝒩, 𝒯, EMB.outputs(n)] >= 0)
end
function EMB.variables_flow_resource(
    m,
    𝒩::Vector{<:EMB.Node},
    𝒫::Vector{<:ResourcePooling},
    𝒯,
    modeltype::EMB.EnergyModel,
)

    # Get the subresources included in the blends (ResourceCarrier or ResourcePressure)
    𝒫ᴿᴾ = [r for res_blend ∈ 𝒫 for r ∈ subresources(res_blend)]

    # Get the sources that can provide the subresources
    𝒮 = filter(n -> EMB.is_source(n) && all(res -> res in 𝒫ᴿᴾ, EMB.outputs(n)), 𝒩)

    # Create all combinations (node, source) for tracking the proportion of source in each node
    @variable(m, 0.0 <= proportion_source[𝒩, 𝒮, 𝒯] <= 1.0)

    # Create a proportion_track variable for each node and subresource
    @variable(m, 0 <= proportion_track[𝒩, 𝒯, 𝒫ᴿᴾ] <= 1.0)
end

"""
    EMB.variables_flow_resource(m, ℒ::Vector{<:EMB.Link}, 𝒫::Vector{:ResourcePressure}, 𝒯, modeltype::EnergyModel) 

Define additional pressure-related variables for links if there are `ResourcePressure` in the system. 
Note! There is no blending variables associated to links.
"""
function EMB.variables_flow_resource(
    m,
    ℒ::Vector{<:EMB.Link},
    𝒫::Vector{<:ResourcePressure},
    𝒯,
    modeltype::EnergyModel,
)
    # Create the link potential variables
    @variable(m, link_potential_in[l ∈ ℒ, 𝒯, EMB.inputs(l.to)] >= 0)
    @variable(m, link_potential_out[l ∈ ℒ, 𝒯, EMB.outputs(l.from)] >= 0)

    # Add link binary variables
    @variable(m, has_flow[l ∈ ℒ, 𝒯], Bin) # auxiliary binary that ensures that all links with flow take value 1, it can take value 1 without flow as well. Careful with this detail, it cannot be used to check actual flows.
    @variable(m, lower_pressure_into_node[l ∈ ℒ, 𝒯], Bin) # binary for tracking lowest pressure going into a node
end

""" 
    EMB.constraints_resource(m, n::EMB.Node, 𝒯, 𝒫::Vector{:ResourcePressure}, modeltype::EMB.EnergyModel)
    EMB.constraints_resource(m, n::EMB.Node, 𝒯, 𝒫::Vector{:ResourcePooling{Any}}, modeltype::EMB.EnergyModel)  
    EMB.constraints_resource(m, n::EMB.Node, 𝒯, 𝒫::Vector{:ResourcePooling{ResourcePressure}}, modeltype::EMB.EnergyModel)

Add blending and/or pressure related constraints to node `n` based on specific resource types.
- If 𝒫::Vector{<:ResourcePressure} then it adds only pressure related constraints
- If 𝒫::Vector{<:ResourcePooling{Any}} then it adds only blending related constraints
- If 𝒫::Vector{<:ResourcePooling{ResourcePressure}} then it adds both pressure and blending related constraints

Note! The blending constraints for nodes require ℒ:Vector{<:EMB.Link} to be passed as argument. Thus, all of them are 
defined in `constraints_couple_resource()` functions.
"""
function EMB.constraints_resource(
    m,
    n::EMB.Node,
    𝒯,
    𝒫::Vector{<:ResourcePressure},
    modeltype::EMB.EnergyModel,
)
    # Define internal pressure balance constraints
    constraints_balance_pressure(m, n, 𝒯, 𝒫)

    # Get AbstractPressureData and generate limit constraints if any
    constraints_pressure_bounds_element(m, n, 𝒯, 𝒫)

    # Define energy-increase potential relationship constraints for type `Compressor`
    constraints_energy_potential(m, n, 𝒯, 𝒫, modeltype)
end
function EMB.constraints_resource(
    m,
    n::EMB.Node,
    𝒯,
    𝒫::Vector{<:ResourcePooling},
    modeltype::EMB.EnergyModel,
) end
function EMB.constraints_resource(
    m,
    n::EMB.Node,
    𝒯,
    𝒫::Vector{<:ResourcePooling{<:ResourcePressure}},
    modeltype::EMB.EnergyModel,
)
    # Add pressure and blending constraints
    constraints_balance_pressure(m, n, 𝒯, 𝒫)

    # Get AbstractPressureData and generate limit constraints if any
    constraints_pressure_bounds_element(m, n, 𝒯, 𝒫)

    # Define energy-increase potential relationship constraints for type `Compressor`
    constraints_energy_potential(m, n, 𝒯, 𝒫, modeltype)
end

""" 
    EMB.constraints_resource(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:ResourcePressure}, modeltype::EMB.EnergyModel)
    EMB.constraints_resource(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:ResourcePooling{Any}}, modeltype::EMB.EnergyModel)  
    EMB.constraints_resource(m, l::EMB.Link, 𝒯, 𝒫::Vector{<:ResourcePooling{ResourcePressure}}, modeltype::EMB.EnergyModel)

Add blending and/or pressure related constraints to node `l` based on specific resource types transported through `l``.
- If 𝒫::Vector{<:ResourcePressure} then it adds only pressure related constraints
- If 𝒫::Vector{<:ResourcePooling{Any}} then it adds only blending related constraints
- If 𝒫::Vector{<:ResourcePooling{ResourcePressure}} then it adds both pressure and blending related constraints

Note! The blending constraints for nodes require ℒ:Vector{<:EMB.Link} to be passed as argument. Thus, all of them are 
defined in `constraints_couple_resource()` functions.
"""
function EMB.constraints_resource(
    m,
    l::EMB.Link,
    𝒯,
    𝒫::Vector{<:ResourcePressure},
    modeltype::EMB.EnergyModel,
)
    # Define internal pressure balance constraints
    constraints_balance_pressure(m, l, 𝒯, 𝒫)

    # Get AbstractPressureData and generate pressure bounds constraints, if any
    constraints_pressure_bounds_element(m, l, 𝒯, 𝒫)

    # Define capacity limit constraints
    constraints_flow_capacity(m, l, 𝒯, 𝒫)

    # Define weymouth flow-pressure constraints based on the resources flowing into the link.
    constraints_flow_pressure(m, l, 𝒯, 𝒫)
end
function EMB.constraints_resource(
    m,
    l::EMB.Link,
    𝒯,
    𝒫::Vector{<:ResourcePooling},
    modeltype::EMB.EnergyModel,
) end
function EMB.constraints_resource(
    m,
    l::EMB.Link,
    𝒯,
    𝒫::Vector{<:ResourcePooling{<:ResourcePressure}},
    modeltype::EMB.EnergyModel,
)

    # Add pressure and blending constraints
    constraints_balance_pressure(m, l, 𝒯, 𝒫)

    # Get AbstractPressureData and generate limit constraints if any
    constraints_pressure_bounds_element(m, l, 𝒯, 𝒫)

    # Define capacity limit constraints
    constraints_flow_capacity(m, l, 𝒯, 𝒫)

    # Define weymouth flow-pressure constraints based on the resources flowing into the link.
    constraints_flow_pressure(m, l, 𝒯, 𝒫)
end

"""
    EMB.constraints_couple_resource(m, 𝒩::Vector{<:EMB.Node}, ℒ::Vector{<:EMB.Link}, 𝒫::Vector{<:ResourcePressure}, 𝒯, modeltype::EMB.EnergyModel)
    EMB.constraints_couple_resource(m, 𝒩::Vector{<:EMB.Node}, ℒ::Vector{<:EMB.Link}, 𝒫::Vector{<:ResourcePooling{Any}}, 𝒯, modeltype::EMB.EnergyModel)
    EMB.constraints_couple_resource(m, 𝒩::Vector{<:EMB.Node}, ℒ::Vector{<:EMB.Link}, 𝒫::Vector{<:ResourcePooling{ResourcePressure}}, 𝒯, modeltype::EMB.EnergyModel)

Add blending and/or pressure related coupling constraints between nodes and links based on specific resource types.
"""
function EMB.constraints_couple_resource(
    m,
    𝒩::Vector{<:EMB.Node},
    ℒ::Vector{<:EMB.Link},
    𝒫::Vector{<:ResourcePressure},
    𝒯,
    modeltype::EMB.EnergyModel,
)
    for n ∈ 𝒩
        constraints_pressure_couple(m, n, ℒ, 𝒯, 𝒫)
    end
end
function EMB.constraints_couple_resource(
    m,
    𝒩::Vector{<:EMB.Node},
    ℒ::Vector{<:EMB.Link},
    𝒫::Vector{<:ResourcePooling},
    𝒯,
    modeltype::EMB.EnergyModel,
)
    for n ∈ 𝒩
        constraints_proportion(m, n, ℒ, 𝒯, 𝒫)
        constraints_quality(m, n, ℒ, 𝒯, 𝒫)
        constraints_tracking(m, n, ℒ, 𝒯, 𝒫)
    end

    constraints_proportion_source(m, 𝒩, ℒ, 𝒯, 𝒫)
end
function EMB.constraints_couple_resource(
    m,
    𝒩::Vector{<:EMB.Node},
    ℒ::Vector{<:EMB.Link},
    𝒫::Vector{<:ResourcePooling{<:ResourcePressure}},
    𝒯,
    modeltype::EMB.EnergyModel,
)
    for n ∈ 𝒩
        constraints_pressure_couple(m, n, ℒ, 𝒯, 𝒫)
    end

    # Set blending couple constraints
    for n ∈ 𝒩
        constraints_proportion(m, n, ℒ, 𝒯, 𝒫)
        constraints_quality(m, n, ℒ, 𝒯, 𝒫)
        constraints_tracking(m, n, ℒ, 𝒯, 𝒫)
    end

    constraints_proportion_source(m, 𝒩, ℒ, 𝒯, 𝒫)
end

"""
    EMB.create_link(m, l::CapDirect, 𝒯, 𝒫::Vector{<:CompoundResource}, modeltype::EMB.EnergyModel) 

Dispatched function for setting the constraints for a link of type `CapDirect`.
"""
function EMB.create_link(m, l::CapDirect, 𝒯, 𝒫, modeltype::EMB.EnergyModel)
    # Generic link in which each output corresponds to the input
    @constraint(m, [t ∈ 𝒯, p ∈ EMB.link_res(l)],
        m[:link_out][l, t, p] == m[:link_in][l, t, p]
    )

    EMB.constraints_capacity(m, l, 𝒯, modeltype)

    if has_capacity(l)
        EMB.constraints_capacity_installed(m, l, 𝒯, modeltype) # calls the function in EMB
    end
end

function EMB.create_node(m, n::SimpleCompressor, 𝒯, 𝒫, modeltype::EMB.EnergyModel)
    # Generic node in which each output corresponds to the input, only for the resources defined in input and output, not the energy resource.
    @constraint(m, [t ∈ 𝒯, p ∈ EMB.outputs(n)],
        m[:flow_out][n, t, p] == m[:flow_in][n, t, p]
    )
end
