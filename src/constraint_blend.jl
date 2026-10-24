const _PROPORTION_CAPABLE = UInt8(1)
const _COMPONENT_FLOW_ONLY = UInt8(2)

"""
    blend_share_plan(𝒩, ℒ, 𝒫)

Decide which nodes track the blend composition explicitly with `proportion_out`.

The component flows on the links give the composition wherever blend mixes, so a share is
only needed where a composition must be shared or read:

- **Composition sources** ([`_is_composition_source`](@ref)): pooling nodes and blend
  storages in mode `:prescribed` or `:fully_mixed`, whose outflows all carry the
  composition of the node.
- **Weymouth pipes** with `BlendLinkData`, whose PWA depends on the share of the tracked
  resource. The share is read from
  1. the inflow node, if it is a composition source, or else
  2. the first pooling node downstream, if the pipe is its only blend inflow, possibly
     through passthrough nodes with a single blend inflow and outflow. The composition is
     then the same along the whole path. Or else
  3. the inflow node, if all gas reaching it comes from composition sources through
     passthrough nodes, which then copy the share (see
     [`_constraints_blend_passthrough`](@ref)). The copy requires simultaneously active
     inflows of these nodes to have the same composition.

All other nodes, e.g. sinks, merges and passthrough nodes off such paths, only balance the
component flows. A pipe without a share raises an `ArgumentError`.

Returns a `NamedTuple` with
- `provenance`: for each blend, the classification of each node as proportion-capable
  (`_PROPORTION_CAPABLE`), component-flow-only (`_COMPONENT_FLOW_ONLY`) or both,
- `share_nodes`: the nodes with `proportion_out`,
- `copy_nodes`: for each blend, the passthrough nodes copying the share from upstream,
- `pwa_reader`: for each `(link, blend)` pair with `BlendLinkData`, the node whose share the
  PWA uses.
"""
function blend_share_plan(
    𝒩::Vector{<:EMB.Node},
    ℒ::Vector{<:EMB.Link},
    𝒫::Vector{<:ResourcePooling},
)
    provenance = Dict{ResourcePooling,Dict{EMB.Node,UInt8}}()
    share_nodes = EMB.Node[]
    copy_nodes = Dict{ResourcePooling,Set{EMB.Node}}()
    pwa_reader = Dict{Tuple{EMB.Link,ResourcePooling},EMB.Node}()
    add_share!(n) = (any(x -> x === n, share_nodes) || push!(share_nodes, n))

    for blend ∈ 𝒫
        sub = subresources(blend)
        incoming = Dict(
            n => [l for l ∈ ℒ if l.to == n && blend ∈ EMB.link_res(l)] for n ∈ 𝒩
        )
        outgoing = Dict(
            n => [l for l ∈ ℒ if l.from == n && blend ∈ EMB.link_res(l)] for n ∈ 𝒩
        )
        state = _blend_provenance(𝒩, blend, incoming)
        provenance[blend] = state
        copies = Set{EMB.Node}()
        copy_nodes[blend] = copies

        for n ∈ 𝒩
            blend ∈ EMB.outputs(n) && _is_composition_source(n) && add_share!(n)
        end

        # Mark the passthrough nodes upstream of a reader `n` that copy the share
        function mark_forward!(n)
            add_share!(n)
            (_is_composition_source(n) || n ∈ copies) && return
            push!(copies, n)
            for l ∈ incoming[n]
                mark_forward!(l.from)
            end
        end

        for n ∈ 𝒩, l ∈ outgoing[n]
            any(d -> d isa BlendLinkData && get_blendres(d) == blend, EMB.link_data(l)) ||
                continue
            if _is_composition_source(n)
                pwa_reader[(l, blend)] = n
                continue
            end
            # A downstream anchor is exact. Copying the share forward through passthrough
            # nodes requires simultaneously active inflows to have the same composition.
            anchor = _downstream_share_anchor(l, sub, incoming, outgoing)
            if !isnothing(anchor)
                add_share!(anchor)
                pwa_reader[(l, blend)] = anchor
                continue
            end
            if state[n] == _PROPORTION_CAPABLE
                mark_forward!(n)
                pwa_reader[(l, blend)] = n
                continue
            end
            throw(
                ArgumentError(
                    "Link $(l.id) has BlendLinkData for blend $(blend.id), so its pressure " *
                    "drop depends on the composition, but neither end provides it. Node " *
                    "$(n.id) does not get all its gas from composition sources, and node " *
                    "$(l.to.id) is " *
                    "not a pooling node whose only blend inflow is this link. Use a " *
                    "PoolingNode or DiscretizedPoolingNode upstream of the link.",
                ),
            )
        end
    end
    return (; provenance, share_nodes, copy_nodes, pwa_reader)
end

"""
    _blend_provenance(𝒩, blend, incoming)

Classify each node with `blend` as output as proportion-capable (all its gas comes from
composition sources), component-flow-only (its composition is only known through component
flows), or both. The fixed-point propagation through passthrough nodes is cycle-safe,
including networks with anti-parallel links.
"""
function _blend_provenance(𝒩, blend, incoming)
    sub = subresources(blend)
    state = Dict{EMB.Node,UInt8}(n => UInt8(0) for n ∈ 𝒩)
    for n ∈ 𝒩
        blend ∈ EMB.outputs(n) || continue
        if _is_composition_source(n)
            state[n] = _PROPORTION_CAPABLE
        elseif n isa BlendingNode || n isa DeblendNode ||
               _blend_storage_mode(n) == :relaxed ||
               any(p -> p ∈ EMB.inputs(n), sub)
            state[n] = _COMPONENT_FLOW_ONLY
        elseif isempty(incoming[n])
            state[n] = _COMPONENT_FLOW_ONLY
        end
    end

    changed = true
    while changed
        changed = false
        for n ∈ 𝒩
            blend ∈ EMB.outputs(n) || continue
            state[n] != 0x00 &&
                !(state[n] == _PROPORTION_CAPABLE && !_is_composition_source(n)) &&
                continue
            inherited = foldl(|, (state[l.from] for l ∈ incoming[n]); init = UInt8(0))
            new_state = state[n] | inherited
            if new_state != state[n]
                state[n] = new_state
                changed = true
            end
        end
    end
    return state
end

"""
    _downstream_share_anchor(l, sub, incoming, outgoing)

Return the pooling node downstream of link `l` whose share equals the composition on `l`, or
`nothing`. Starting at `l.to`, the path may pass through passthrough nodes with exactly one
blend inflow and outflow. Each node on the path, including the pooling node, must have the
previous link as its only blend inflow and no inputs of the sub-resources `sub`, so that
no other gas mixes in.
"""
function _downstream_share_anchor(l, sub, incoming, outgoing)
    visited = Set{EMB.Node}()
    while true
        n = l.to
        (n ∈ visited || !haskey(incoming, n)) && return nothing
        push!(visited, n)
        (length(incoming[n]) == 1 && only(incoming[n]) == l) || return nothing
        any(p -> p ∈ EMB.inputs(n), sub) && return nothing
        if (n isa PoolingNode || n isa DiscretizedPoolingNode) && !isempty(outgoing[n])
            return n
        end
        (_is_blend_passthrough(n) && length(outgoing[n]) == 1) || return nothing
        l = only(outgoing[n])
    end
end

"""
    validate_blend_topology(𝒩, ℒ, 𝒫; switched_links = nothing)

Reject blend topologies that the component-flow formulation can not represent, and return
the provenance of [`blend_share_plan`](@ref):

- A `Storage` of a blend requires [`BlendStorageData`](@ref).
- A node with several outgoing blend links must give them the same composition. Pooling
  nodes and blend storages with a shared composition do so. A passthrough node (see
  [`_is_blend_passthrough`](@ref)) is only accepted if all its outgoing blend links are in
  `switched_links`, the links with a `has_flow` binary;
  [`_constraints_passthrough_single_outflow`](@ref) then allows at most one of them to
  carry flow in each period. Other nodes, e.g. `BlendingNode`, are rejected.
- Each link with `BlendLinkData` needs a share, see [`blend_share_plan`](@ref).
"""
function validate_blend_topology(
    𝒩::Vector{<:EMB.Node},
    ℒ::Vector{<:EMB.Link},
    𝒫::Vector{<:ResourcePooling};
    switched_links = nothing,
)
    for n ∈ 𝒩
        n isa EMB.Storage || continue
        stored = EMB.storage_resource(n)
        blended =
            stored isa ResourcePooling ||
            any(p -> p isa ResourcePooling, EMB.inputs(n)) ||
            any(p -> p isa ResourcePooling, EMB.outputs(n))
        (blended && isnothing(get_blendstoragedata(n))) || continue
        throw(
            ArgumentError(
                "Storage node $(n.id) uses a ResourcePooling blend but has no " *
                "BlendStorageData. Add BlendStorageData to choose how the composition " *
                "of the discharged gas is modelled.",
            ),
        )
    end

    plan = blend_share_plan(𝒩, ℒ, 𝒫)
    for blend ∈ 𝒫, n ∈ 𝒩
        ℒᵒᵘᵗ = [l for l ∈ ℒ if l.from == n && blend ∈ EMB.link_res(l)]
        length(ℒᵒᵘᵗ) > 1 || continue
        _is_composition_source(n) && continue
        if _is_blend_passthrough(n)
            (isnothing(switched_links) || any(l ∉ switched_links for l ∈ ℒᵒᵘᵗ)) || continue
            # Passthrough nodes do not tie the component flows of their outgoing links to a
            # common composition, so simultaneous outflows could carry different mixtures.
            # Without `has_flow` on every outgoing link, this cannot be prevented.
            throw(
                ArgumentError(
                    "Node $(n.id) passes blend $(blend.id) through unchanged but has " *
                    "$(length(ℒᵒᵘᵗ)) outgoing blend links, not all with a has_flow " *
                    "binary. Passthrough nodes (e.g. TransitNode) may only send blend " *
                    "down one link per period. Use PoolingNode or DiscretizedPoolingNode " *
                    "where the blend splits.",
                ),
            )
        end
        throw(
            ArgumentError(
                "Node $(n.id) has component-flow-only blend provenance and feeds multiple " *
                "blend outputs for blend $(blend.id). Use PoolingNode or " *
                "DiscretizedPoolingNode where the blend splits.",
            ),
        )
    end
    return plan.provenance
end

"""
    _is_blend_passthrough(n)

Return `true` if the blend composition at node `n` is set by
[`_constraints_blend_passthrough`](@ref), i.e. copied from upstream without a per-link
mixing constraint.
"""
_is_blend_passthrough(n::EMB.Node) = false
_is_blend_passthrough(n::EMB.NetworkNode) = true
_is_blend_passthrough(n::PoolingNode) = false
_is_blend_passthrough(n::DiscretizedPoolingNode) = false
_is_blend_passthrough(n::BlendingNode) = false
_is_blend_passthrough(n::DeblendNode) = false
_is_blend_passthrough(n::EMB.Storage) = false

"""
    _switched_links(m, ℒ)

Return the links whose flow forces `has_flow = 1`, or `nothing` if the model has no
`has_flow` variables. These are the links carrying a `ResourcePressure` or a
`ResourcePooling{<:ResourcePressure}`, for which `constraints_flow_capacity` adds
`link_in ≤ M·has_flow`. Links with carrier-only blends also get a `has_flow` binary, but
nothing ties it to their flow.
"""
function _switched_links(m, ℒ)
    haskey(m, :has_flow) || return nothing
    ℒ_bin = Set(axes(m[:has_flow], 1))
    is_pressure(r) = r isa ResourcePressure || r isa ResourcePooling{<:ResourcePressure}
    return Set(l for l ∈ ℒ if l ∈ ℒ_bin && any(is_pressure, EMB.link_res(l)))
end

"""
    _constraints_passthrough_single_outflow(m, 𝒩, ℒ, 𝒯, 𝒫)

For every passthrough node with several outgoing links carrying a blend, allow at most one
of them to be active in each period:

    Σ_{l_out} has_flow[l_out, t] ≤ 1

Flow on a pressure link forces `has_flow = 1` (`constraints_flow_capacity`), so the blend
leaves the node through a single link, whose component flows equal those entering the node.
This keeps the passthrough linear while allowing bidirectional pipelines, where a junction
has an outgoing link towards each neighbour but only one carries flow.
"""
function _constraints_passthrough_single_outflow(m, 𝒩, ℒ, 𝒯, 𝒫)
    switched_links = _switched_links(m, ℒ)
    isnothing(switched_links) && return
    for n ∈ 𝒩, blend ∈ 𝒫
        _is_blend_passthrough(n) || continue
        blend ∈ EMB.outputs(n) || continue
        ℒ_out = [l for l ∈ ℒ if l.from == n && blend ∈ EMB.link_res(l)]
        length(ℒ_out) > 1 || continue
        all(l ∈ switched_links for l ∈ ℒ_out) || continue  # rejected in validate_blend_topology
        @constraint(m, [t ∈ 𝒯], sum(m[:has_flow][l, t] for l ∈ ℒ_out) ≤ 1)
    end
end

"""
    constraints_component_blend(m, 𝒩, ℒ, 𝒯, 𝒫)

Entry point for the component-flow pooling formulation.

Adds, in order:
1. The checks of [`validate_blend_topology`](@ref) and, at passthrough nodes with several
   outgoing blend links, at most one active outflow.
2. Linear link component balances (`link_in[blend] == Σ flow_component[p]`).
3. Linear per-component node mass balances.
4. The composition constraints of the nodes that track it (see [`blend_share_plan`](@ref)):
   bilinear or discretized mixing at pooling nodes, blend storage, and the share copied by
   passthrough nodes from upstream.
5. Linear quality bounds from `RefBlendData`.
6. Deferred unit conversion and deblending constraints on component flows.
7. Normalisation `Σ proportion_out[n,t,p] = 1` at the passthrough nodes copying a share.
"""
function constraints_component_blend(
    m,
    𝒩::Vector{<:EMB.Node},
    ℒ::Vector{<:EMB.Link},
    𝒯,
    𝒫::Vector{<:ResourcePooling},
)
    switched_links = _switched_links(m, ℒ)
    provenance = validate_blend_topology(𝒩, ℒ, 𝒫; switched_links)
    m.ext[:emgn_blend_provenance] = provenance
    _constraints_passthrough_single_outflow(m, 𝒩, ℒ, 𝒯, 𝒫)

    constraints_link_component_balance(m, ℒ, 𝒯, 𝒫)
    for n ∈ 𝒩
        constraints_node_component_balance(m, n, ℒ, 𝒯, 𝒫)
        constraints_blend_proportion(m, n, ℒ, 𝒯, 𝒫)
        constraints_quality_blend(m, n, ℒ, 𝒯, 𝒫)
    end

    # Deferred linearised FlowToEnergyData constraints for UnitConversion nodes with blend
    # input.  These cannot be built during the node phase (constraints_ext_data) because
    # flow_component link variables do not exist yet at that point.  Now that all link
    # variables are available we add:
    #   flow_out[n,t,p] == Σ_sub  lhv_sub × flow_component[l_in, t, sub]
    # which is linear (flow_component already encodes proportion_out × flow_in).
    _constraints_unit_conversion_blend_lhv(m, 𝒩, ℒ, 𝒯, 𝒫)

    # Deferred CO₂ emission output constraints for UnitConversion nodes that have
    # EmissionsConversionData.  Sets flow_out[n, t, co2_res] from blend component flows.
    _constraints_unit_conversion_co2_output(m, 𝒩, ℒ, 𝒯, 𝒫)

    # Deferred DeblendNode extraction fraction constraints: H₂ extracted ≤ α × incoming H₂.
    # Must run after flow_component variables are available.
    _constraints_deblend_extraction(m, 𝒩, ℒ, 𝒯, 𝒫)

    # Normalisation at the passthrough nodes copying a share. When the copy is relaxed
    # (inactive incoming links), the share would otherwise be free in [0, 1]. Pooling
    # nodes and blend storages add their own normalisation.
    plan = m.ext[:emgn_blend_plan]
    for blend ∈ 𝒫, n ∈ plan.copy_nodes[blend]
        sub = subresources(blend)
        ℒᶠʳᵒᵐ_n, _ = EMB.link_sub(ℒ, n)
        ℒ_blend_out_n = filter(l -> blend ∈ EMB.link_res(l), ℒᶠʳᵒᵐ_n)
        _constraints_proportion_normalisation(m, n, sub, ℒ_blend_out_n, 𝒯)
    end
end

"""
    _constraints_proportion_normalisation(m, n, sub, ℒ_out, 𝒯)

Require the proportions `proportion_out[n, t, p]` of the sub-resources `sub` to sum to 1.

When `has_flow` variables are present (pressure networks with ZeroDrop / Pipeline links),
a conditional big-M formulation is used:

    Σ_p proportion_out[n, t, p] ≤ 1
    Σ_p proportion_out[n, t, p] ≥ has_flow[l, t]   for each outgoing blend link l ∈ ℒ_out

This relaxes the equality when no gas flows (`has_flow = 0`), allowing the NLP relaxation
to set `proportion_out = 0`. Without it, a node that only receives a single sub-resource
(e.g. a pure-H₂ electrolyser) would propagate `proportion_out[H2] = 1.0` even at zero flow,
violating quality bounds at downstream consumers and causing the NLP relaxation used by
MINLP solvers to report spurious local infeasibility. In the MILP (`has_flow ∈ {0,1}`),
the two constraints collapse to the equality whenever an outgoing blend link is active.
"""
function _constraints_proportion_normalisation(m, n, sub, ℒ_out, 𝒯)
    if haskey(m, :has_flow)
        @constraint(m, [t ∈ 𝒯], sum(m[:proportion_out][n, t, p] for p ∈ sub) ≤ 1.0)
        for l ∈ ℒ_out
            l ∈ axes(m[:has_flow], 1) || continue
            @constraint(m, [t ∈ 𝒯],
                sum(m[:proportion_out][n, t, p] for p ∈ sub) ≥ m[:has_flow][l, t]
            )
        end
    else
        @constraint(m, [t ∈ 𝒯], sum(m[:proportion_out][n, t, p] for p ∈ sub) == 1.0)
    end
end

# ---------------------------------------------------------------------------
# Deferred FlowToEnergyData linearisation for blend-input UnitConversion nodes
# ---------------------------------------------------------------------------

"""
    _constraints_unit_conversion_blend_lhv(m, 𝒩, ℒ, 𝒯, 𝒫)

Add the linearised `FlowToEnergyData` conversion constraint for every `UnitConversion`
node whose input is a `ResourcePooling` blend and whose `FlowToEnergyData` specifies
per-sub-resource LHV values.

This must run **after** link variables (`flow_component`) have been declared, which is
why it cannot be placed in `constraints_ext_data` (the node constraint phase).

For each qualifying node the constraint added is:

    flow_out[n, t, p_out] == Σ_{l_in} Σ_sub  lhv_sub × flow_component[l_in, t, sub]

which is linear because `flow_component[l_in, t, sub]` is an explicit variable
(it already encodes `proportion_out × flow_in`).

Outputs that appear as keys in an `EmissionsConversionData` on the same node are skipped
here — they are handled separately by `_constraints_unit_conversion_co2_output`.
"""
function _constraints_unit_conversion_blend_lhv(
    m,
    𝒩::Vector{<:EMB.Node},
    ℒ::Vector{<:EMB.Link},
    𝒯,
    𝒫::Vector{<:ResourcePooling},
)
    links_with_fc = axes(m[:flow_component], 1)

    for n ∈ 𝒩
        n isa UnitConversion || continue

        # Find FlowToEnergyData with a vector LHV on this node
        lhv_data = nothing
        for d ∈ EMB.node_data(n)
            if d isa FlowToEnergyData
                𝒫ˡʰᵛ = get_specific_energy_content(d)
                if 𝒫ˡʰᵛ isa Vector{<:EMB.Resource}
                    lhv_data = d
                    break
                end
            end
        end
        isnothing(lhv_data) && continue

        # Check the node has a blend (ResourcePooling) input
        blend_inputs = [p for p ∈ EMB.inputs(n) if p isa ResourcePooling]
        isempty(blend_inputs) && continue
        blend = first(blend_inputs)
        sub   = subresources(blend)

        # The LHV dict must cover all sub-resources, otherwise `flow_out` is unconstrained
        lhv_keys = get_specific_energy_content(lhv_data)
        missing_sub = [s for s ∈ sub if s ∉ lhv_keys]
        isempty(missing_sub) || error(
            "UnitConversion $(n.id): FlowToEnergyData has no specific energy content for " *
            "sub-resource(s) $(join([s.id for s ∈ missing_sub], ", ")) of blend $(blend.id).",
        )

        l_in_list = _blend_links_in(n, ℒ, links_with_fc, blend)

        # Collect CO₂ emission output resources (handled by co2_output constraint).
        co2_outputs = Set{EMB.Resource}(
            d.co2_output for d ∈ EMB.node_data(n) if d isa EmissionsConversionData
        )

        # Add linearised constraint for energy outputs only (skip CO₂ emission outputs).
        energy_outputs = [p for p ∈ EMB.outputs(n) if p ∉ co2_outputs]
        @constraint(
            m,
            [t ∈ 𝒯, p ∈ energy_outputs],
            m[:flow_out][n, t, p] ==
            sum(
                get_specific_energy_content(lhv_data, s) *
                m[:flow_component][l_in, t, s] for l_in ∈ l_in_list, s ∈ sub
            )
        )
    end
end

"""
    _blend_links_in(n, ℒ, links_with_fc, blend)

Return all links in `ℒ` delivering `blend` to node `n`. Throws an error if there are none,
or if any of them lacks `flow_component` variables, since the energy and CO₂ outputs of
`n` would then not be fully constrained.
"""
function _blend_links_in(n, ℒ, links_with_fc, blend)
    l_in_list = [l for l ∈ ℒ if l.to == n && blend ∈ EMB.link_res(l)]
    isempty(l_in_list) && error(
        "UnitConversion $(n.id): no incoming link carries blend $(blend.id).",
    )
    for l ∈ l_in_list
        l ∈ links_with_fc || error(
            "UnitConversion $(n.id): incoming blend link $(l.id) has no flow_component " *
            "variables.",
        )
    end
    return l_in_list
end

"""
    _dpn_flow_bound(m, n::DiscretizedPoolingNode, l, 𝒯)

Return a finite upper bound on the blend flow on the outgoing link `l` of `n`: the
smaller of the installed-capacity bounds of `n` and `l`. Used for the flow breakpoints
(`:pwl`) and big-M coefficients (`:bigm`, `:bigm_log`).
"""
function _dpn_flow_bound(m, n::DiscretizedPoolingNode, l, 𝒯)
    bounds = filter(
        !isnothing,
        [_maximum_node_capacity(m, n, 𝒯), _maximum_link_capacity(m, l, 𝒯)],
    )
    isempty(bounds) && error(
        "DiscretizedPoolingNode $(n.id): cannot derive a finite flow bound for link " *
        "$(l.id). Provide a finite (maximum installed) capacity for the node or the link.",
    )
    return minimum(bounds)
end

# ---------------------------------------------------------------------------
# Deferred CO₂ emission output constraints for UnitConversion nodes
# ---------------------------------------------------------------------------

"""
    _constraints_unit_conversion_co2_output(m, 𝒩, ℒ, 𝒯, 𝒫)

Add the linearised CO₂ emission output constraint for every `UnitConversion` node that
has an `EmissionsConversionData` attached and a blend (ResourcePooling) input.

Must run **after** `flow_component` link variables exist (i.e., in the deferred blend
constraint phase, called from `constraints_component_blend`).

For each qualifying node and each resource `p` whose value appears as an output in
the node's output dict AND whose key is in `EmissionsConversionData.co2_intensity`,
the constraint is:

    flow_out[n, t, p] == Σ_{l_in} Σ_sub  co2_intensity[sub] × flow_component[l_in, t, sub]

Units: `flow_component` [MSm³/d], `co2_intensity` [tCO₂/MSm³] → `flow_out` [tCO₂/d].
"""
function _constraints_unit_conversion_co2_output(
    m,
    𝒩::Vector{<:EMB.Node},
    ℒ::Vector{<:EMB.Link},
    𝒯,
    𝒫::Vector{<:ResourcePooling},
)
    links_with_fc = axes(m[:flow_component], 1)

    for n ∈ 𝒩
        n isa UnitConversion || continue

        # Find EmissionsConversionData on this node
        em_data = nothing
        for d ∈ EMB.node_data(n)
            if d isa EmissionsConversionData
                em_data = d
                break
            end
        end
        isnothing(em_data) && continue

        # Check the node has a blend (ResourcePooling) input
        blend_inputs = [p for p ∈ EMB.inputs(n) if p isa ResourcePooling]
        isempty(blend_inputs) && continue
        blend = first(blend_inputs)
        sub   = subresources(blend)

        l_in_list = _blend_links_in(n, ℒ, links_with_fc, blend)

        # Identify CO₂ emission output resource from EmissionsConversionData.
        co2_res = em_data.co2_output
        co2_res ∈ EMB.outputs(n) || continue

        # Add constraint: flow_out[co2_res] = Σ_sub co2_int[sub] × flow_component[l_in, sub]
        @constraint(
            m,
            [t ∈ 𝒯],
            m[:flow_out][n, t, co2_res] ==
            sum(
                get_co2_intensity(em_data, s) *
                m[:flow_component][l_in, t, s] for l_in ∈ l_in_list, s ∈ sub
            )
        )
    end
end

# ---------------------------------------------------------------------------
# DeblendNode extraction fraction constraint (deferred — needs flow_component)
# ---------------------------------------------------------------------------

"""
    _constraints_deblend_extraction(m, 𝒩, ℒ, 𝒯, 𝒫)

For each `DeblendNode` in `𝒩`, add the fraction-extraction upper bound on the H₂
*extracted* from the blend (delivered ÷ η):

    flow_out[n, t, p] / η ≤ max_extract_fraction × Σ_{l_in} flow_component[l_in, t, p]

where η = `psa_efficiency(n)`. This must be called **after** `flow_component` variables
have been created.
"""
function _constraints_deblend_extraction(
    m,
    𝒩::Vector{<:EMB.Node},
    ℒ::Vector{<:EMB.Link},
    𝒯,
    𝒫::Vector{<:ResourcePooling},
)
    links_with_fc = axes(m[:flow_component], 1)

    for n ∈ 𝒩
        n isa DeblendNode || continue
        α = max_extract_fraction(n)
        η = psa_efficiency(n)

        for blend ∈ 𝒫
            blend ∈ EMB.inputs(n) || continue
            sub = subresources(blend)
            extracted = [p for p ∈ sub if p ∈ EMB.outputs(n)]
            isempty(extracted) && continue

            _, ℒᵗᵒ = EMB.link_sub(ℒ, n)
            ℒ_blend_in = filter(l -> blend ∈ EMB.link_res(l) && l ∈ links_with_fc, ℒᵗᵒ)
            isempty(ℒ_blend_in) && continue

            for p ∈ extracted
                @constraint(m, [t ∈ 𝒯],
                    m[:flow_out][n, t, p] / η ≤
                    α * sum(m[:flow_component][l, t, p] for l ∈ ℒ_blend_in)
                )
            end
        end
    end
end

# ---------------------------------------------------------------------------
# Link-level balance
# ---------------------------------------------------------------------------

"""
    constraints_link_component_balance(m, ℒ, 𝒯, 𝒫)

For every link carrying a `ResourcePooling` blend, enforce:

    link_in[l, t, blend] == Σ_p flow_component[l, t, p]

so that the sum of all tracked component flows equals the total blend flow.
"""
function constraints_link_component_balance(m, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling})
    ℒ_blend = filter(l -> any(p -> p isa ResourcePooling, EMB.link_res(l)), ℒ)
    for l ∈ ℒ_blend, blend ∈ 𝒫
        blend ∈ EMB.link_res(l) || continue
        sub = subresources(blend)
        @constraint(m, [t ∈ 𝒯],
            m[:link_in][l, t, blend] == sum(m[:flow_component][l, t, p] for p ∈ sub)
        )
    end
end

# ---------------------------------------------------------------------------
# Node-level component mass balance
# ---------------------------------------------------------------------------

"""
    constraints_node_component_balance(m, n, ℒ, 𝒯, 𝒫)

Linear per-component mass balance at a node `n`.

For each subresource `p` of every blend:
    Σ_{l_out blend} flow_component[l_out, t, p]
        == flow_in[n, t, p]  (if p ∈ inputs(n), else 0)
         + Σ_{l_in blend} flow_component[l_in, t, p]

This is a linear identity that connects the raw inflow of `p` (e.g., pure H2
injected at a `PoolingNode`) with the component-tracked flows on the blend links.

No-op for `Source` nodes (no blend output) and `Sink` nodes (no blend output to balance).
"""
function constraints_node_component_balance(
    m,
    n::EMB.Node,
    ℒ,
    𝒯,
    𝒫::Vector{<:ResourcePooling},
)
    for blend ∈ 𝒫
        sub = subresources(blend)

        _, ℒᵗᵒ = EMB.link_sub(ℒ, n)
        ℒᶠʳᵒᵐ, _ = EMB.link_sub(ℒ, n)

        ℒ_blend_in  = filter(l -> blend ∈ EMB.link_res(l), ℒᵗᵒ)
        ℒ_blend_out = filter(l -> blend ∈ EMB.link_res(l), ℒᶠʳᵒᵐ)

        isempty(ℒ_blend_out) && continue

        for p ∈ sub
            raw_in = p ∈ EMB.inputs(n)

            if isempty(ℒ_blend_in) && !raw_in
                # Neither blend nor raw subresource flows in — fix components to 0
                for l ∈ ℒ_blend_out
                    @constraint(m, [t ∈ 𝒯], m[:flow_component][l, t, p] == 0)
                end
                continue
            end

            if raw_in && isempty(ℒ_blend_in)
                # Only raw subresource input — simple assignment (single blend out handled
                # in constraints_blend_proportion; here just balance multi-output case)
                @constraint(m, [t ∈ 𝒯],
                    sum(m[:flow_component][l, t, p] for l ∈ ℒ_blend_out) ==
                    m[:flow_in][n, t, p]
                )
            elseif !raw_in && !isempty(ℒ_blend_in)
                # Only blend inputs carry p — pure passthrough
                @constraint(m, [t ∈ 𝒯],
                    sum(m[:flow_component][l, t, p] for l ∈ ℒ_blend_out) ==
                    sum(m[:flow_component][l, t, p] for l ∈ ℒ_blend_in)
                )
            else
                # Both raw inflow and blend inputs carry p
                @constraint(m, [t ∈ 𝒯],
                    sum(m[:flow_component][l, t, p] for l ∈ ℒ_blend_out) ==
                    m[:flow_in][n, t, p] +
                    sum(m[:flow_component][l, t, p] for l ∈ ℒ_blend_in)
                )
            end
        end
    end
end
function constraints_node_component_balance(
    m, n::EMB.Source, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling},
) end
function constraints_node_component_balance(
    m, n::EMB.Sink, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling},
) end

"""
    constraints_node_component_balance(m, n::DeblendNode, ℒ, 𝒯, 𝒫)

Component balance for `DeblendNode`:

- **Extracted sub-resource** (e.g. H₂ that also appears in `outputs(n)`):
  `flow_component[l_out, t, H₂] = flow_component[l_in, t, H₂] - flow_out[n, t, H₂]`

- **Passthrough sub-resources** (e.g. CH₄):
  `flow_component[l_out, t, CH₄] = flow_component[l_in, t, CH₄]`
"""
function constraints_node_component_balance(
    m, n::DeblendNode, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling},
)
    for blend ∈ 𝒫
        blend ∈ EMB.inputs(n) || continue
        blend ∈ EMB.outputs(n) || continue
        sub = subresources(blend)

        _, ℒᵗᵒ   = EMB.link_sub(ℒ, n)
        ℒᶠʳᵒᵐ, _ = EMB.link_sub(ℒ, n)

        ℒ_blend_in  = filter(l -> blend ∈ EMB.link_res(l), ℒᵗᵒ)
        ℒ_blend_out = filter(l -> blend ∈ EMB.link_res(l), ℒᶠʳᵒᵐ)

        (isempty(ℒ_blend_in) || isempty(ℒ_blend_out)) && continue

        # Sub-resources that are also raw outputs (extracted from the blend)
        extracted = Set(p for p ∈ sub if p ∈ EMB.outputs(n))
        η = psa_efficiency(n)

        for p ∈ sub
            if p ∈ extracted
                # H₂ component on output blend = input H₂ component minus extracted H₂.
                # Extracted H₂ = delivered H₂ / η (PSA consumes (1-η) fraction internally).
                @constraint(m, [t ∈ 𝒯],
                    sum(m[:flow_component][l, t, p] for l ∈ ℒ_blend_out) ==
                    sum(m[:flow_component][l, t, p] for l ∈ ℒ_blend_in) -
                    m[:flow_out][n, t, p] / η
                )
            else
                # All other components (e.g. CH₄) pass through unchanged
                @constraint(m, [t ∈ 𝒯],
                    sum(m[:flow_component][l, t, p] for l ∈ ℒ_blend_out) ==
                    sum(m[:flow_component][l, t, p] for l ∈ ℒ_blend_in)
                )
            end
        end
    end
end

# ---------------------------------------------------------------------------
# Proportion constraints — dispatched by node type
# ---------------------------------------------------------------------------

"""
    constraints_blend_proportion(m, n, ℒ, 𝒯, 𝒫)

Set the `proportion_out` variable and any associated constraints for node `n`.

- **`PoolingNode`** (bilinear/MINLP): for each blend output link,
      `flow_component[l_out, t, p] = proportion_out[n, t, p] × link_in[l_out, t, blend]`

- **`DiscretizedPoolingNode`** (piecewise linear/MILP): same semantics as `PoolingNode`
  but uses `PiecewiseLinearOpt.piecewiselinear` to approximate the bilinear product
  with a piecewise linear function. Controlled by [`DiscretizationData`](@ref).

- **`TransitNode`** and generic blend-passthrough `NetworkNode` (linear):
      `proportion_out[n, t, p] = proportion_out[upstream_node, t, p]`
  where `upstream_node` is the node at the other end of the primary incoming blend link.

- All other node types: no-op.

Normalisation (`Σ proportion_out = 1`) is applied globally by `constraints_component_blend`
and is not repeated here.
"""
function constraints_blend_proportion(
    m, n::EMB.Node, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling},
) end
function constraints_blend_proportion(
    m, n::EMB.Source, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling},
) end

"""
    constraints_blend_proportion(m, n::BlendingNode, ℒ, 𝒯, 𝒫)

No-op for `BlendingNode`. The blend composition on the single outgoing link is fully
determined by the linear component mass balance in `constraints_node_component_balance`.
No bilinear `proportion_out × link_in` constraint is needed or generated.

Quality bounds are handled separately by `constraints_quality_blend` using direct linear
flow-component bounds.
"""
function constraints_blend_proportion(
    m, n::BlendingNode, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling},
) end

function constraints_blend_proportion(
    m, n::PoolingNode, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling},
)
    for blend ∈ 𝒫
        blend ∈ EMB.outputs(n) || continue
        sub = subresources(blend)

        ℒᶠʳᵒᵐ, _ = EMB.link_sub(ℒ, n)
        ℒ_blend_out = filter(l -> blend ∈ EMB.link_res(l), ℒᶠʳᵒᵐ)
        isempty(ℒ_blend_out) && continue

        # Bilinear mixing: each output link carries the blend in proportion_out[n] ratio.
        for l ∈ ℒ_blend_out, p ∈ sub
            @constraint(m, [t ∈ 𝒯],
                m[:flow_component][l, t, p] ==
                m[:proportion_out][n, t, p] * m[:link_in][l, t, blend]
            )
        end

        # Normalisation: proportions must sum to 1 when gas is flowing.
        _constraints_proportion_normalisation(m, n, sub, ℒ_blend_out, 𝒯)
    end
end

"""
    constraints_blend_proportion(m, n::DiscretizedPoolingNode, ℒ, 𝒯, 𝒫)

MILP-compatible mixing constraint for `DiscretizedPoolingNode`.

Dispatches to one of three sub-implementations based on the `method` field of
[`DiscretizationData`](@ref):

- `:pwl` — 2D piecewise-linear approximation via `PiecewiseLinearOpt.piecewiselinear`
  (the original formulation). Bilinear `flow_component = proportion_out × link_in`
  is approximated on a K×K grid. Uses ⌈log₂(K−1)⌉ binary variables per product with
  the `:Logarithmic` method.

- `:bigm` — standard BigM MILP formulation. ONE set of K binary variables
  `δ[t, k]` per time step (shared across all outgoing links). The composition
  `proportion_out` is set directly to a discrete level `α_k = (k-1)/(K-1)`, which is a
  **linear** JuMP expression. This also makes downstream pressure constraints MILP-linear.
  N-1 + 1 = N outgoing link flows are fully determined; the last component flow is
  inferred from the node mass balance.

- `:bigm_log` — logarithmic BigM MILP formulation. Uses `n_bits = ⌈log₂(K)⌉` binary
  variables per time step via binary encoding. The actual number of levels is
  `K_actual = 2^n_bits ≥ n_points`. For `n_points = 10`: 4 bits → 16 levels.

See [`_constraints_dpn_pwl`](@ref), [`_constraints_dpn_bigm`](@ref) for details.
"""
function constraints_blend_proportion(
    m, n::DiscretizedPoolingNode, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling},
)
    discr_data = filter(d -> d isa DiscretizationData, n.data)
    data = isempty(discr_data) ? DiscretizationData(5) : first(discr_data)
    K = get_n_points(data)
    method = get_method(data)
    max_prop = get_max_proportion(data)

    if method == :pwl
        _constraints_dpn_pwl(m, n, ℒ, 𝒯, 𝒫, data, K, max_prop)
    elseif method == :bigm
        _constraints_dpn_bigm(
            m, n, ℒ, 𝒯, 𝒫, data, K, max_prop; log_encoding = false,
        )
    elseif method == :bigm_log
        _constraints_dpn_bigm(
            m, n, ℒ, 𝒯, 𝒫, data, K, max_prop; log_encoding = true,
        )
    else
        error("constraints_blend_proportion: unknown DiscretizationData method :$method")
    end
end

function _discretized_tracked_resource(
    data::DiscretizationData,
    n::DiscretizedPoolingNode,
    ℒ,
    blend::ResourcePooling,
)
    sub = subresources(blend)
    tracked = get_tracked_resource(data)
    if !isnothing(tracked)
        tracked ∈ sub || throw(
            ArgumentError(
                "DiscretizationData tracked resource $(tracked.id) is not a subresource " *
                "of blend $(blend.id) at node $(n.id).",
            ),
        )
        return tracked
    end

    candidates = EMB.Resource[]
    adjacent_nodes = Any[n]
    append!(adjacent_nodes, (l.to for l ∈ ℒ if l.from == n))
    unique!(adjacent_nodes)
    for candidate_node ∈ adjacent_nodes
        for blend_data ∈ EMB.node_data(candidate_node)
            if blend_data isa RefBlendData && blend_data.blend == blend
                max_res, min_res = res_blendata(blend_data)
                restricted = [
                    p for p ∈ sub if
                    (haskey(max_res, p) && max_res[p] < 1) ||
                        (haskey(min_res, p) && min_res[p] > 0)
                ]
                append!(candidates, restricted)
            end
        end
    end
    unique!(candidates)

    if length(candidates) == 1
        return only(candidates)
    end

    empty!(candidates)
    for l ∈ ℒ
        l.from == n || continue
        for blend_data ∈ EMB.link_data(l)
            blend_data isa BlendLinkData || continue
            get_blendres(blend_data) == blend || continue
            push!(candidates, get_trackres(blend_data))
        end
    end
    unique!(candidates)

    if length(candidates) == 1
        return only(candidates)
    elseif isempty(candidates) && get_max_proportion(data) == 1.0
        return first(sub)
    end

    detail = isempty(candidates) ? "none" : join((p.id for p ∈ candidates), ", ")
    throw(
        ArgumentError(
            "Cannot infer the tracked resource for legacy DiscretizationData at node " *
            "$(n.id); candidates from adjacent RefBlendData/BlendLinkData: $detail. " *
            "Use DiscretizationData(tracked_resource, n_points, method, max_proportion).",
        ),
    )
end

"""
    _constraints_dpn_pwl(m, n, ℒ, 𝒯, 𝒫, K, max_prop)

Original PWL formulation for `DiscretizedPoolingNode` using `PiecewiseLinearOpt`.

For each outgoing blend link `l`, subresource `p`, and time `t`, approximates the
bilinear product `proportion_out[n,t,p] × link_in[l,t,blend]` on a K×K grid using
the `:Logarithmic` method (⌈log₂(K−1)⌉ binary variables per product).

`max_prop` limits the proportion axis to `[0, max_prop]` instead of `[0, 1]`, placing
all K breakpoints within the physically feasible H₂ fraction range.
"""
function _constraints_dpn_pwl(
    m,
    n::DiscretizedPoolingNode,
    ℒ,
    𝒯,
    𝒫::Vector{<:ResourcePooling},
    data::DiscretizationData,
    K::Int,
    max_prop::Float64,
)
    for blend ∈ 𝒫
        blend ∈ EMB.outputs(n) || continue
        sub = subresources(blend)
        tracked = _discretized_tracked_resource(data, n, ℒ, blend)

        ℒᶠʳᵒᵐ, _ = EMB.link_sub(ℒ, n)
        ℒ_blend_out = filter(l -> blend ∈ EMB.link_res(l), ℒᶠʳᵒᵐ)
        isempty(ℒ_blend_out) && continue

        for l ∈ ℒ_blend_out, p ∈ sub
            prop_min, prop_max = if p == tracked
                (0.0, max_prop)
            elseif length(sub) == 2
                (1.0 - max_prop, 1.0)
            else
                (0.0, 1.0)
            end
            prop_bpts = collect(range(prop_min, prop_max; length = K))
            F_max = _dpn_flow_bound(m, n, l, 𝒯)
            flow_bpts = collect(range(0.0, F_max; length = K))

            for t ∈ 𝒯
                z = PiecewiseLinearOpt.piecewiselinear(
                    m,
                    m[:proportion_out][n, t, p],
                    m[:link_in][l, t, blend],
                    prop_bpts,
                    flow_bpts,
                    (u, v) -> u * v;
                    method = :Logarithmic,
                )
                @constraint(m, m[:flow_component][l, t, p] == z)
            end
        end

        # has_flow-guarded normalisation (same as PoolingNode).
        if haskey(m, :has_flow)
            @constraint(m, [t ∈ 𝒯], sum(m[:proportion_out][n, t, p] for p ∈ sub) ≤ 1.0)
            for l ∈ ℒ_blend_out
                l ∈ axes(m[:has_flow], 1) || continue
                @constraint(m, [t ∈ 𝒯],
                    sum(m[:proportion_out][n, t, p] for p ∈ sub) ≥ m[:has_flow][l, t]
                )
            end
        else
            @constraint(m, [t ∈ 𝒯], sum(m[:proportion_out][n, t, p] for p ∈ sub) == 1.0)
        end
    end
end

"""
    _constraints_dpn_bigm(m, n, ℒ, 𝒯, 𝒫, K, max_prop; log_encoding=false)

BigM MILP formulation for `DiscretizedPoolingNode` using the **composition approach**.

## Composition Approach

Rather than per-link split fractions, a SINGLE set of binary variables selects the
composition (proportion) level for the pooling node at each time step. This is shared
across ALL outgoing links — the same composition applies to all downstream pipelines,
which is the physical interpretation of a pooling node.

`max_prop` limits the proportion axis to `[0, max_prop]`. All K levels span this range,
so every level is within the feasible H₂ fraction bound. With `max_prop = 1.0` (default),
levels span `[0%, 100%]`; with `max_prop = 0.20`, they span `[0%, 20%]`.

### Standard BigM (log_encoding = false):
- K binary variables `δ[t, k]` per time step, exactly one active: `Σ_k δ[t,k] = 1`
- K discrete levels `α_k = (k-1)/(K-1) × max_prop` for k=1..K
- `proportion_out[n, t, sub[1]] = Σ_k α_k · δ[t,k]`  ← linear!
- `proportion_out[n, t, sub[2]] = 1 - proportion_out[n, t, sub[1]]`
- For each outgoing link `l` and level `k`:
  - `w[l,t,k]` approximates `δ[t,k] · link_in[l,t,blend]` via BigM:
    - `w ≤ F_max · δ[t,k]`
    - `w ≥ link_in - F_max · (1 - δ[t,k])`
    - `0 ≤ w ≤ link_in`
  - `flow_component[l,t,sub[1]] = Σ_k α_k · w[l,t,k]`
  - `flow_component[l,t,sub[2]] = link_in[l,t,blend] - flow_component[l,t,sub[1]]`

### Logarithmic BigM (log_encoding = true):
- `n_bits = ⌈log₂(K)⌉` binary variables `b[t, j]` per time step
- Actual levels: `K_actual = 2^n_bits` (rounded up from K)
- Level index: `k = Σ_j 2^(j-1) · b[t,j]` (binary encoding)
- `proportion_out[n, t, sub[1]] = Σ_j 2^(j-1)/(K_actual-1) × max_prop · b[t,j]`  ← linear!
- For each outgoing link `l` and bit `j`:
  - `w_j[l,t]` approximates `b[t,j] · link_in[l,t,blend]` via BigM
  - `flow_component[l,t,sub[1]] = Σ_j 2^(j-1)/(K_actual-1) × max_prop · w_j[l,t]`

### Why This Is Equivalent to the User's N-1 Split Fraction Description
For a 2-component blend and N outgoing links: the composition approach uses ONE binary
set (not N-1) because all N links share the same pooled composition. The N-th link's
component flows are then inferred by the node mass balance (already a linear constraint).

### Restriction
Currently supports only 2-component blends (M = 2). Asserts `length(sub) == 2`.
"""
function _constraints_dpn_bigm(
    m,
    n::DiscretizedPoolingNode,
    ℒ,
    𝒯,
    𝒫::Vector{<:ResourcePooling},
    data::DiscretizationData,
    K::Int,
    max_prop::Float64;
    log_encoding::Bool = false,
)
    𝒯_vec = collect(𝒯)

    for blend ∈ 𝒫
        blend ∈ EMB.outputs(n) || continue
        sub = subresources(blend)
        @assert length(sub) == 2 "BigM pooling formulation requires a 2-component blend; " *
                                 "node $(n.id) has $(length(sub)) subresources: $sub"

        ℒᶠʳᵒᵐ, _ = EMB.link_sub(ℒ, n)
        ℒ_blend_out = filter(l -> blend ∈ EMB.link_res(l), ℒᶠʳᵒᵐ)
        isempty(ℒ_blend_out) && continue

        p_disc = _discretized_tracked_resource(data, n, ℒ, blend)
        p_rest = only(filter(!=(p_disc), sub))

        F_max = Dict(l => _dpn_flow_bound(m, n, l, 𝒯) for l ∈ ℒ_blend_out)
        node_id = string(n.id)  # safe base name for JuMP variable names

        if log_encoding
            # ── Logarithmic BigM ─────────────────────────────────────────────
            n_bits = max(1, ceil(Int, log2(K)))
            K_actual = 2^n_bits  # actual number of levels (≥ K)
            bit_weights = [2^(j - 1) for j ∈ 1:n_bits]  # 1, 2, 4, ...
            level_coeffs = bit_weights ./ (K_actual - 1) .* max_prop  # proportion per bit

            # Binary variables: one set per time step
            δ = @variable(m, [𝒯_vec, 1:n_bits], Bin,
                base_name = "dpn_bigm_b_$(node_id)")

            # w variables: BigM linearization of b[t,j] * link_in[l,t,blend]
            w = @variable(m, [l ∈ ℒ_blend_out, t ∈ 𝒯_vec, j ∈ 1:n_bits],
                lower_bound = 0.0, upper_bound = F_max[l],
                base_name = "dpn_bigm_w_$(node_id)")

            # Set proportion_out[n, t, p_disc] = Σ_j coeff_j * b[t,j]
            @constraint(m, [t ∈ 𝒯_vec],
                m[:proportion_out][n, t, p_disc] ==
                sum(level_coeffs[j] * δ[t, j] for j ∈ 1:n_bits)
            )
            @constraint(m, [t ∈ 𝒯_vec],
                m[:proportion_out][n, t, p_rest] ==
                1.0 - m[:proportion_out][n, t, p_disc]
            )

            # BigM constraints: w_j[l,t] ≈ b[t,j] * link_in[l,t,blend]
            @constraint(m, [l ∈ ℒ_blend_out, t ∈ 𝒯_vec, j ∈ 1:n_bits],
                w[l, t, j] ≤ F_max[l] * δ[t, j]
            )
            @constraint(m, [l ∈ ℒ_blend_out, t ∈ 𝒯_vec, j ∈ 1:n_bits],
                w[l, t, j] ≥ m[:link_in][l, t, blend] - F_max[l] * (1 - δ[t, j])
            )
            @constraint(m, [l ∈ ℒ_blend_out, t ∈ 𝒯_vec, j ∈ 1:n_bits],
                w[l, t, j] ≤ m[:link_in][l, t, blend]
            )

            # Component flow: flow_comp[l,t,p_disc] = Σ_j coeff_j * w_j[l,t]
            @constraint(m, [l ∈ ℒ_blend_out, t ∈ 𝒯_vec],
                m[:flow_component][l, t, p_disc] ==
                sum(level_coeffs[j] * w[l, t, j] for j ∈ 1:n_bits)
            )
            @constraint(m, [l ∈ ℒ_blend_out, t ∈ 𝒯_vec],
                m[:flow_component][l, t, p_rest] ==
                m[:link_in][l, t, blend] - m[:flow_component][l, t, p_disc]
            )

        else
            # ── Standard BigM ─────────────────────────────────────────────────
            # K discrete composition levels: α_k = (k-1)/(K-1) * max_prop for k=1..K
            alphas = [(k - 1) / (K - 1) * max_prop for k ∈ 1:K]

            # Binary variables: one set per time step, exactly one active
            δ = @variable(m, [𝒯_vec, 1:K], Bin,
                base_name = "dpn_bigm_d_$(node_id)")
            @constraint(m, [t ∈ 𝒯_vec], sum(δ[t, k] for k ∈ 1:K) == 1)

            # w variables: BigM linearization of δ[t,k] * link_in[l,t,blend]
            w = @variable(m, [l ∈ ℒ_blend_out, t ∈ 𝒯_vec, k ∈ 1:K],
                lower_bound = 0.0, upper_bound = F_max[l],
                base_name = "dpn_bigm_w_$(node_id)")

            # Set proportion_out[n, t, p_disc] = Σ_k α_k * δ[t,k]  (linear!)
            @constraint(m, [t ∈ 𝒯_vec],
                m[:proportion_out][n, t, p_disc] ==
                sum(alphas[k] * δ[t, k] for k ∈ 1:K)
            )
            @constraint(m, [t ∈ 𝒯_vec],
                m[:proportion_out][n, t, p_rest] ==
                1.0 - m[:proportion_out][n, t, p_disc]
            )

            # BigM constraints: w[l,t,k] ≈ δ[t,k] * link_in[l,t,blend]
            @constraint(m, [l ∈ ℒ_blend_out, t ∈ 𝒯_vec, k ∈ 1:K],
                w[l, t, k] ≤ F_max[l] * δ[t, k]
            )
            @constraint(m, [l ∈ ℒ_blend_out, t ∈ 𝒯_vec, k ∈ 1:K],
                w[l, t, k] ≥ m[:link_in][l, t, blend] - F_max[l] * (1 - δ[t, k])
            )
            @constraint(m, [l ∈ ℒ_blend_out, t ∈ 𝒯_vec, k ∈ 1:K],
                w[l, t, k] ≤ m[:link_in][l, t, blend]
            )

            # Component flow: flow_comp[l,t,p_disc] = Σ_k α_k * w[l,t,k]
            @constraint(m, [l ∈ ℒ_blend_out, t ∈ 𝒯_vec],
                m[:flow_component][l, t, p_disc] ==
                sum(alphas[k] * w[l, t, k] for k ∈ 1:K)
            )
            @constraint(m, [l ∈ ℒ_blend_out, t ∈ 𝒯_vec],
                m[:flow_component][l, t, p_rest] ==
                m[:link_in][l, t, blend] - m[:flow_component][l, t, p_disc]
            )
        end
    end
end

function constraints_blend_proportion(
    m, n::TransitNode, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling},
)
    _constraints_blend_passthrough(m, n, ℒ, 𝒯, 𝒫)
end

function constraints_blend_proportion(
    m, n::EMB.NetworkNode, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling},
)
    # Nodes that only consume the blend (e.g. UnitConversion) use the component flows of
    # their inflows for LHV and quality bounds.
    any(p -> p isa ResourcePooling, EMB.outputs(n)) || return nothing
    _constraints_blend_passthrough(m, n, ℒ, 𝒯, 𝒫)
end

function constraints_blend_proportion(
    m, n::DeblendNode, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling},
)
    # DeblendNode uses linear flow_component balance (constraints_node_component_balance).
    # It has no proportion_out variable, so the generic NetworkNode fallback
    # (_constraints_blend_passthrough) must not be invoked here.
    return nothing
end

"""
    _constraints_blend_passthrough(m, n, ℒ, 𝒯, 𝒫)

Linear proportion passthrough for nodes that carry blend unchanged (no injection). Only the
passthrough nodes that [`blend_share_plan`](@ref) selects to copy the share, i.e. those
between composition sources and a link with `BlendLinkData`, get these constraints.

**Single-link case (no circularity possible):**  
When a node has exactly one incoming blend link, a hard equality is used:
    proportion_out[n, t, p] == proportion_out[upstream, t, p]

**Multi-link case (bidirectional / cyclic networks):**  
When a node has two or more incoming blend links, a big-M formulation conditioned on
`has_flow` is used instead of a hard equality.  For each incoming link `l_up`:

    proportion_out[n, t, p] - proportion_out[upstream, t, p] ∈ [-(1 - has_flow), (1 - has_flow)]

When `has_flow[l_up, t] = 1` (link is active) this collapses to a hard equality, propagating
the upstream composition.  When `has_flow[l_up, t] = 0` (link is inactive) the constraint is
trivially satisfied and `proportion_out[n]` is not pinned to that (inactive) upstream.

This matters in bidirectional networks: a pair {A→B, B→A} carries
`has_flow[A→B] + has_flow[B→A] ≤ 1`, guaranteeing at most one direction is active.
Without conditioning, iterating both links would add `proportion[n] = proportion[A]` and
`proportion[n] = proportion[B]` — contradictory if A and B carry different compositions, and
circular (free) if they share the same cycle.  Conditioning on `has_flow` breaks the
contradiction: only the active-direction link constrains the proportion.

`proportion_out ∈ [0, 1]`, so M = 1 is the tightest valid big-M coefficient.

Fallback: if `has_flow` is not in the model (networks without `ResourcePressure`), hard
equalities are used in all cases — safe for the acyclic / unidirectional topologies those
models represent.

A copy node may have several simultaneously active inflows (a merge). The constraints then
require their compositions to be equal, which restricts the solution; place a pooling node
at such merges instead.
"""
function _constraints_blend_passthrough(m, n, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling})
    use_bigm = haskey(m, :has_flow)
    prop_nodes = axes(m[:proportion_out], 1)
    prop_res = axes(m[:proportion_out], 3)
    n ∈ prop_nodes || return nothing

    plan = m.ext[:emgn_blend_plan]
    for blend ∈ 𝒫
        blend ∈ EMB.outputs(n) || continue
        n ∈ plan.copy_nodes[blend] || continue
        sub = subresources(blend)
        all(p ∈ prop_res for p ∈ sub) || continue

        _, ℒᵗᵒ = EMB.link_sub(ℒ, n)
        ℒ_blend_in = filter(l -> blend ∈ EMB.link_res(l), ℒᵗᵒ)
        isempty(ℒ_blend_in) && continue

        # Use hard equality only when no has_flow variables exist (pure NLP / operational
        # model without binary on/off). When has_flow is present (MILP or NLP relaxation),
        # always use big-M so that inactive links (has_flow→0 in the NLP interior) do not
        # propagate upstream proportions and make the relaxation infeasible.
        force_equality = !use_bigm

        for l_up ∈ ℒ_blend_in
            upstream = l_up.from
            upstream ∈ prop_nodes || continue

            if force_equality || l_up ∉ axes(m[:has_flow], 1)
                @constraint(m, [t ∈ 𝒯, p ∈ sub],
                    m[:proportion_out][n, t, p] == m[:proportion_out][upstream, t, p]
                )
            else
                # Big-M conditional equality: binding when has_flow = 1, relaxed when 0.
                @constraint(m, [t ∈ 𝒯, p ∈ sub],
                    m[:proportion_out][n, t, p] - m[:proportion_out][upstream, t, p] <=
                    1 - m[:has_flow][l_up, t]
                )
                @constraint(m, [t ∈ 𝒯, p ∈ sub],
                    m[:proportion_out][n, t, p] - m[:proportion_out][upstream, t, p] >=
                    -(1 - m[:has_flow][l_up, t])
                )
            end
        end
    end
end

# ---------------------------------------------------------------------------
# Quality / composition bounds
# ---------------------------------------------------------------------------

"""
    constraints_quality_blend(m, n::BlendingNode, ℒ, 𝒯, 𝒫)

Enforce blend composition bounds for `BlendingNode` using **linear** flow-component
bounds on the single outgoing blend link.

Since `BlendingNode` has no `proportion_out` variable, bounds from `RefBlendData` are
expressed directly in terms of `flow_component` and `link_in`:

    flow_component[l_out, t, H₂] ≤ max_h2 × link_in[l_out, t, Blend]   (LINEAR)
    flow_component[l_out, t, H₂] ≥ min_h2 × link_in[l_out, t, Blend]   (LINEAR)

With big-M relaxation for `has_flow = 0` (same pattern as the generic `proportion_out`
quality dispatch):

    flow_component[l_out, t, H₂] ≤ max_h2 × link_in[l_out, t, Blend] + M × (1 - has_flow)

where M = 1 (the maximum possible flow_component / link_in ratio).

No-op when no `RefBlendData` is attached.
"""
function constraints_quality_blend(m, n::BlendingNode, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling})
    _constraints_quality_blend_flows(m, n, ℒ, 𝒯, 𝒫)
end

"""
    constraints_quality_blend(m, n, ℒ, 𝒯, 𝒫)

Enforce the blend composition bounds from `RefBlendData` attached to node `n`.

Since `proportion_out[n]` is now defined for all nodes with blend in inputs or outputs
(including `Sink` and `UnitConversion`), the bounds are applied directly to `proportion_out[n]`.
This is always linear.

No-op when no `RefBlendData` is attached.
"""
function constraints_quality_blend(m, n::EMB.Node, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling})
    _constraints_quality_blend_flows(m, n, ℒ, 𝒯, 𝒫)
end

function _constraints_quality_blend_flows(
    m,
    n::EMB.Node,
    ℒ,
    𝒯,
    𝒫::Vector{<:ResourcePooling},
)
    links_with_fc = axes(m[:flow_component], 1)

    for blend ∈ 𝒫
        data_vect = get_blenddata(n, blend)
        isempty(data_vect) && continue
        data = only(data_vect)

        𝒫ᵐᵃˣ, 𝒫ᵐⁱⁿ = res_blendata(data)
        sub = subresources(blend)

        ℒ_out = [
            l for l ∈ ℒ if l.from == n && blend ∈ EMB.link_res(l) &&
                               l ∈ links_with_fc
        ]
        ℒ_in = [
            l for l ∈ ℒ if l.to == n && blend ∈ EMB.link_res(l) &&
                               l ∈ links_with_fc
        ]
        ℒ_quality = isempty(ℒ_out) ? ℒ_in : ℒ_out
        isempty(ℒ_quality) && continue

        for p ∈ sub
            if haskey(𝒫ᵐᵃˣ, p) && 𝒫ᵐᵃˣ[p] < 1
                ub = 𝒫ᵐᵃˣ[p]
                @constraint(m, [t ∈ 𝒯],
                    sum(m[:flow_component][l, t, p] for l ∈ ℒ_quality) ≤
                    ub * sum(m[:link_in][l, t, blend] for l ∈ ℒ_quality)
                )
            end
            if haskey(𝒫ᵐⁱⁿ, p) && 𝒫ᵐⁱⁿ[p] > 0
                lb = 𝒫ᵐⁱⁿ[p]
                @constraint(m, [t ∈ 𝒯],
                    sum(m[:flow_component][l, t, p] for l ∈ ℒ_quality) ≥
                    lb * sum(m[:link_in][l, t, blend] for l ∈ ℒ_quality)
                )
            end
        end
    end
end
