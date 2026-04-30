"""
    constraints_component_blend(m, 𝒩, ℒ, 𝒯, 𝒫)

Entry point for the component-flow pooling formulation.

Adds, in order:
1. Linear link component balances (`link_in[blend] == Σ flow_component[p]`).
2. Linear per-component node mass balances.
3. Bilinear mixing / proportion constraints at `PoolingNode`s.
4. Linear proportion passthrough at `TransitNode`s and generic passthrough nodes.
5. Universal normalisation `Σ proportion_out[n,t,p] = 1` for TransitNode /
   NetworkNode blend-passthrough nodes (PoolingNode already gets it from its
   bilinear dispatch; Sink/Source get it transitively through passthrough).
6. Linear quality bounds from `RefBlendData`.
"""
function constraints_component_blend(
    m,
    𝒩::Vector{<:EMB.Node},
    ℒ::Vector{<:EMB.Link},
    𝒯,
    𝒫::Vector{<:ResourcePooling},
)
    constraints_link_component_balance(m, ℒ, 𝒯, 𝒫)
    for n ∈ 𝒩
        constraints_node_component_balance(m, n, ℒ, 𝒯, 𝒫)
        constraints_blend_proportion(m, n, ℒ, 𝒯, 𝒫)
        constraints_quality_blend(m, n, ℒ, 𝒯, 𝒫)
    end

    # Universal normalisation for blend-originating nodes: proportions must always
    # sum to 1. This catches TransitNode and NetworkNode instances that receive only
    # pure-component inputs (no incoming Blend link) and therefore get no passthrough
    # constraint — without normalisation, their proportion_out variables are free in
    # [0,1] and the solver can push every component to 1.0 simultaneously.
    #
    # Excluded:
    #   - PoolingNode: already gets normalisation inside constraints_blend_proportion.
    #   - EMB.Sink / EMB.Source: proportions are pinned via passthrough/consume
    #     constraints; adding an extra equality can interact poorly with the MIP
    #     relaxation used by MINLP solvers such as Alpine.
    prop_idx = axes(m[:proportion_out], 1)
    for n ∈ 𝒩
        n isa PoolingNode  && continue
        n isa EMB.Sink     && continue
        n isa EMB.Source   && continue
        n ∈ prop_idx || continue
        for blend ∈ 𝒫
            sub = subresources(blend)
            any(p ∈ axes(m[:proportion_out], 3) for p ∈ sub) || continue
            @constraint(m, [t ∈ 𝒯],
                sum(m[:proportion_out][n, t, p] for p ∈ sub) == 1.0
            )
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
function constraints_node_component_balance(m, n::EMB.Node, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling})
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

# ---------------------------------------------------------------------------
# Proportion constraints — dispatched by node type
# ---------------------------------------------------------------------------

"""
    constraints_blend_proportion(m, n, ℒ, 𝒯, 𝒫)

Set the `proportion_out` variable and any associated constraints for node `n`.

- **`PoolingNode`** (bilinear): for each blend output link,
      `flow_component[l_out, t, p] = proportion_out[n, t, p] × link_in[l_out, t, blend]`

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

        # Normalisation: proportions must sum to 1 at every timestep.
        # Kept here (rather than only in the universal loop) to guarantee the
        # constraint is conditioned on `blend ∈ EMB.outputs(n)`, matching the
        # bilinear constraints above.
        @constraint(m, [t ∈ 𝒯], sum(m[:proportion_out][n, t, p] for p ∈ sub) == 1.0)
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
    if any(p -> p isa ResourcePooling, EMB.outputs(n))
        _constraints_blend_passthrough(m, n, ℒ, 𝒯, 𝒫)
    else
        # Node receives blend but doesn't output it (e.g., UnitConversion).
        # Set proportion_out[n] = proportion_out[upstream] as a convenience for LHV
        # and quality constraint lookups.
        _constraints_blend_consume(m, n, ℒ, 𝒯, 𝒫)
    end
end

function constraints_blend_proportion(
    m, n::EMB.Sink, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling},
)
    # Sink nodes receive blend but never output it — propagate proportion_out from
    # upstream so that quality bounds (RefBlendData) are linked to actual composition.
    _constraints_blend_consume(m, n, ℒ, 𝒯, 𝒫)
end

"""
    _constraints_blend_consume(m, n, ℒ, 𝒯, 𝒫)

Linear proportion passthrough for nodes that consume blend (have blend as input but not output).

Sets `proportion_out[n, t, p] == proportion_out[upstream, t, p]` so that downstream
constraints (quality bounds, LHV calculation) can access the blend composition at `n`.
"""
function _constraints_blend_consume(m, n, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling})
    for blend ∈ 𝒫
        blend ∈ EMB.inputs(n) || continue
        sub = subresources(blend)

        _, ℒᵗᵒ = EMB.link_sub(ℒ, n)
        ℒ_blend_in = filter(l -> blend ∈ EMB.link_res(l), ℒᵗᵒ)
        isempty(ℒ_blend_in) && continue

        upstream = first(ℒ_blend_in).from
        any(p -> p isa ResourcePooling, EMB.outputs(upstream)) || continue

        @constraint(m, [t ∈ 𝒯, p ∈ sub],
            m[:proportion_out][n, t, p] == m[:proportion_out][upstream, t, p]
        )
    end
end

"""
    _constraints_blend_passthrough(m, n, ℒ, 𝒯, 𝒫)

Linear proportion passthrough for nodes that carry blend unchanged (no injection).

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

Guard per link: only add the constraint if the upstream node itself produces a
`ResourcePooling` blend (i.e., has `proportion_out` defined and meaningful).
"""
function _constraints_blend_passthrough(m, n, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling})
    use_bigm = haskey(m, :has_flow)

    for blend ∈ 𝒫
        blend ∈ EMB.outputs(n) || continue
        sub = subresources(blend)

        _, ℒᵗᵒ = EMB.link_sub(ℒ, n)
        ℒ_blend_in = filter(l -> blend ∈ EMB.link_res(l), ℒᵗᵒ)
        isempty(ℒ_blend_in) && continue

        # Single-link: no circularity possible — hard equality is always safe.
        # Multi-link: use big-M so that only active (has_flow=1) upstreams anchor the
        # proportion; inactive links (has_flow=0) do not over-constrain the proportion.
        force_equality = !use_bigm || length(ℒ_blend_in) == 1

        for l_up ∈ ℒ_blend_in
            upstream = l_up.from
            any(p -> p isa ResourcePooling, EMB.outputs(upstream)) || continue

            if force_equality
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
    constraints_quality_blend(m, n, ℒ, 𝒯, 𝒫)

Enforce the blend composition bounds from `RefBlendData` attached to node `n`.

Since `proportion_out[n]` is now defined for all nodes with blend in inputs or outputs
(including `Sink` and `UnitConversion`), the bounds are applied directly to `proportion_out[n]`.
This is always linear.

No-op when no `RefBlendData` is attached.
"""
function constraints_quality_blend(m, n::EMB.Node, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling})
    for blend ∈ 𝒫
        data_vect = get_blenddata(n, blend)
        isempty(data_vect) && continue
        data = only(data_vect)

        𝒫ᵐᵃˣ, 𝒫ᵐⁱⁿ = res_blendata(data)
        sub = subresources(blend)

        for p ∈ sub
            haskey(𝒫ᵐᵃˣ, p) && 𝒫ᵐᵃˣ[p] < 1 &&
                @constraint(m, [t ∈ 𝒯], m[:proportion_out][n, t, p] <= 𝒫ᵐᵃˣ[p])
            haskey(𝒫ᵐⁱⁿ, p) && 𝒫ᵐⁱⁿ[p] > 0 &&
                @constraint(m, [t ∈ 𝒯], m[:proportion_out][n, t, p] >= 𝒫ᵐⁱⁿ[p])
        end
    end
end

