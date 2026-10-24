# ---------------------------------------------------------------------------
# Storage of ResourcePooling blends (`BlendStorageData`)
# ---------------------------------------------------------------------------

"""
    _blend_storage_mode(n)

Return the mode of the [`BlendStorageData`](@ref) of node `n`, or `nothing` if `n` is not
a `Storage` or has no such data.
"""
_blend_storage_mode(n::EMB.Node) = nothing
function _blend_storage_mode(n::EMB.Storage)
    data = get_blendstoragedata(n)
    return isnothing(data) ? nothing : get_storage_mode(data)
end

"""
    _is_composition_source(n)

Return `true` if node `n` sets the composition of its blend outputs itself, so that the
composition can be shared by several outgoing links and by composition-dependent
`BlendLinkData` links. These are the pooling nodes, and blend storages in mode
`:prescribed` or `:fully_mixed`.
"""
_is_composition_source(n::EMB.Node) = false
_is_composition_source(n::PoolingNode) = true
_is_composition_source(n::DiscretizedPoolingNode) = true
_is_composition_source(n::EMB.Storage) =
    _blend_storage_mode(n) ∈ (:prescribed, :fully_mixed)

"""
    EMB.variables_ext_data(m, _::Type{<:BlendStorageData}, 𝒩ˢᵗᵒʳ::Vector{<:EMB.Node}, 𝒯, 𝒫, modeltype::EnergyModel)

Create the component inventory variables of the storages `𝒩ˢᵗᵒʳ` with
[`BlendStorageData`](@ref), indexed by the sub-resources `p` of their blend:

- `stor_level_component[n, t, p] ≥ 0` is the stored amount of `p` at the end of `t`.
- `stor_level_component_Δ_op[n, t, p]` is the rate of change of the stored amount of `p`.
- `stor_level_component_Δ_rp[n, t_rp, p]` is the change of the stored amount of `p` in
  the representative period `t_rp`. It is only created if `𝒯` has representative periods.
"""
function EMB.variables_ext_data(
    m,
    _::Type{<:BlendStorageData},
    𝒩ˢᵗᵒʳ::Vector{<:EMB.Node},
    𝒯,
    𝒫,
    modeltype::EnergyModel,
)
    sub(n) = subresources(get_blendstoragedata(n).blend)
    @variable(m, stor_level_component[n ∈ 𝒩ˢᵗᵒʳ, 𝒯, sub(n)] ≥ 0)
    @variable(m, stor_level_component_Δ_op[n ∈ 𝒩ˢᵗᵒʳ, 𝒯, sub(n)])
    if 𝒯 isa TwoLevel{S,T,U} where {S,T,U<:RepresentativePeriods}
        𝒯ʳᵖ = repr_periods(𝒯)
        @variable(m, stor_level_component_Δ_rp[n ∈ 𝒩ˢᵗᵒʳ, 𝒯ʳᵖ, sub(n)])
    end
end

"""
    EMB.constraints_ext_data(m, n::EMB.Storage, 𝒯, 𝒫, modeltype::EnergyModel, data::BlendStorageData)

Add the level balance of each component inventory of the blend storage `n`:

    stor_level_component[n, t, p] = previous level + stor_level_component_Δ_op[n, t, p] × duration(t)

The previous level follows the same rules as the total level of the storage in
`EnergyModelsBase`, including the cyclic constraints of the storage behaviour. The
component levels add up to the total level:

    Σ_p stor_level_component[n, t, p] = stor_level[n, t]

The rate of change `stor_level_component_Δ_op` is set from the component flows on the
links in [`constraints_node_component_balance`](@ref), as the link variables do not exist
yet when this function is called.
"""
function EMB.constraints_ext_data(
    m,
    n::EMB.Storage,
    𝒯,
    𝒫,
    modeltype::EnergyModel,
    data::BlendStorageData,
)
    sub = subresources(data.blend)
    lvl = m[:stor_level_component]

    @constraint(m, [t ∈ 𝒯], sum(lvl[n, t, p] for p ∈ sub) == m[:stor_level][n, t])

    for (t_inv_prev, t_inv) ∈ withprev(strategic_periods(𝒯))
        prev_pers = PreviousPeriods(t_inv_prev, nothing, nothing)
        cyclic_pers = CyclicPeriods(t_inv, t_inv)
        _level_component_iterate(
            m,
            n,
            sub,
            prev_pers,
            cyclic_pers,
            t_inv,
            t_inv.operational,
        )
    end
end

# The functions below mirror `constraints_level_iterate`, `constraints_level_rp`,
# `constraints_level_scp`, `constraints_level_bounds`, `previous_level` and
# `previous_level_sp` of EnergyModelsBase for `Cyclic` storage behaviours, but act on the
# component levels. The test for `Σ_p stor_level_component = stor_level` catches drift.

function _level_component_iterate(
    m,
    n,
    sub,
    prev_pers,
    cyclic_pers,
    per,
    ::RepresentativePeriods,
)
    𝒯ʳᵖ = repr_periods(per)
    last_rp = last(𝒯ʳᵖ)
    Δ_rp = m[:stor_level_component_Δ_rp]
    Δ_op = m[:stor_level_component_Δ_op]

    if n isa EMB.Storage{CyclicRepresentative}
        @constraint(m, [t_rp ∈ 𝒯ʳᵖ, p ∈ sub], Δ_rp[n, t_rp, p] == 0)
    else
        @constraint(m, [p ∈ sub], sum(Δ_rp[n, t_rp, p] for t_rp ∈ 𝒯ʳᵖ) == 0)
    end
    @constraint(m, [t_rp ∈ 𝒯ʳᵖ, p ∈ sub],
        Δ_rp[n, t_rp, p] == sum(Δ_op[n, t, p] * scale_op_sp(per, t) for t ∈ t_rp)
    )

    for (t_rp_prev, t_rp) ∈ withprev(𝒯ʳᵖ)
        prev_pers = PreviousPeriods(strat_per(prev_pers), t_rp_prev, op_per(prev_pers))
        cyclic_pers = CyclicPeriods(last_rp, t_rp)
        _level_component_iterate(
            m, n, sub, prev_pers, cyclic_pers, t_rp, t_rp.operational.operational,
        )
    end
end
function _level_component_iterate(
    m,
    n,
    sub,
    prev_pers,
    cyclic_pers,
    per,
    ::OperationalScenarios,
)
    𝒯ˢᶜ = opscenarios(per)
    lvl = m[:stor_level_component]

    # Equal level at the end of all operational scenarios
    if (n isa EMB.Storage{<:EMB.Cyclic} && per isa TimeStruct.AbstractStrategicPeriod) ||
       (
        n isa EMB.Storage{CyclicRepresentative} &&
        per isa TimeStruct.AbstractRepresentativePeriod
    )
        last_scp = [last(t_scp) for t_scp ∈ 𝒯ˢᶜ]
        for t ∈ last_scp[2:end]
            @constraint(m, [p ∈ sub], lvl[n, t, p] == lvl[n, first(last_scp), p])
        end
    end

    for t_scp ∈ 𝒯ˢᶜ
        _level_component_iterate(
            m, n, sub, prev_pers, cyclic_pers, t_scp, t_scp.operational.operational,
        )
    end
end
function _level_component_iterate(m, n, sub, prev_pers, cyclic_pers, per, ::SimpleTimes)
    lvl = m[:stor_level_component]
    Δ_op = m[:stor_level_component_Δ_op]
    for (t_prev, t) ∈ withprev(per)
        prev_pers = PreviousPeriods(strat_per(prev_pers), rep_per(prev_pers), t_prev)
        for p ∈ sub
            prev_level = _previous_level_component(m, n, p, prev_pers, cyclic_pers)
            @constraint(m, lvl[n, t, p] == prev_level + Δ_op[n, t, p] * duration(t))
        end

        # With representative periods, the level at the start of the period is not a
        # variable and must be bounded separately.
        if current_per(cyclic_pers) isa TimeStruct.AbstractRepresentativePeriod
            @constraint(m, [p ∈ sub], lvl[n, t, p] - Δ_op[n, t, p] * duration(t) ≥ 0)
        end
    end
end

function _previous_level_component(m, n, p, prev_pers, cyclic_pers)
    lvl = m[:stor_level_component]
    Δ_op = m[:stor_level_component_Δ_op]

    # Level at the start of the representative period `t_rp` plus its change
    level_after(t_rp) =
        lvl[n, first(t_rp), p] - Δ_op[n, first(t_rp), p] * duration(first(t_rp)) +
        m[:stor_level_component_Δ_rp][n, t_rp, p]

    t_prev = op_per(prev_pers)
    isnothing(t_prev) || return lvl[n, t_prev, p]

    rp_prev = rep_per(prev_pers)
    cur = current_per(cyclic_pers)
    if isnothing(rp_prev)
        # First period of a strategic period
        if n isa EMB.Storage{CyclicStrategic} &&
           cur isa TimeStruct.AbstractRepresentativePeriod
            return level_after(last_per(cyclic_pers))
        end
        return lvl[n, last(cur), p]
    end
    # First period of a later representative period
    n isa EMB.Storage{CyclicRepresentative} && return lvl[n, last(cur), p]
    return level_after(rp_prev)
end

"""
    constraints_node_component_balance(m, n::EMB.Storage, ℒ, 𝒯, 𝒫)

Set the rate of change of the component inventories of a blend storage `n` from the
component flows on its charge links `ℒⁱⁿ` and discharge links `ℒᵒᵘᵗ`:

    stor_level_component_Δ_op[n, t, p] =
        Σ_{l ∈ ℒⁱⁿ} flow_component[l, t, p] - Σ_{l ∈ ℒᵒᵘᵗ} flow_component[l, t, p]

Together with the level balance in `EMB.constraints_ext_data` and the bound
`stor_level_component ≥ 0`, the storage can not discharge more of a component than was
charged and stored.

No-op for storages without [`BlendStorageData`](@ref).
"""
function constraints_node_component_balance(
    m, n::EMB.Storage, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling},
)
    data = get_blendstoragedata(n)
    isnothing(data) && return nothing
    blend = data.blend
    ℒᶠʳᵒᵐ, ℒᵗᵒ = EMB.link_sub(ℒ, n)
    ℒ_in = filter(l -> blend ∈ EMB.link_res(l), ℒᵗᵒ)
    ℒ_out = filter(l -> blend ∈ EMB.link_res(l), ℒᶠʳᵒᵐ)
    fc = m[:flow_component]
    for t ∈ 𝒯, p ∈ subresources(blend)
        charge = isempty(ℒ_in) ? 0 : sum(fc[l, t, p] for l ∈ ℒ_in)
        discharge = isempty(ℒ_out) ? 0 : sum(fc[l, t, p] for l ∈ ℒ_out)
        @constraint(m, m[:stor_level_component_Δ_op][n, t, p] == charge - discharge)
    end
end

"""
    constraints_blend_proportion(m, n::EMB.Storage, ℒ, 𝒯, 𝒫)

Set the composition of the gas discharged from a blend storage `n` according to the mode of
its [`BlendStorageData`](@ref):

- `:relaxed`: no constraint, the component inventories bound the discharge.
- `:prescribed`: `flow_component[l, t, p] = q_p(t) × link_in[l, t, blend]` on each
  discharge link `l`, and `proportion_out[n, t, p] = q_p(t)`.
- `:fully_mixed`: `flow_component[l, t, p] = proportion_out[n, t, p] × link_in[l, t, blend]`
  on each discharge link `l` and
  `stor_level_component[n, t, p] = proportion_out[n, t, p] × stor_level[n, t]` (bilinear).
  The composition is that of the stored gas at the end of period `t`.

No-op for storages without [`BlendStorageData`](@ref).
"""
function constraints_blend_proportion(
    m, n::EMB.Storage, ℒ, 𝒯, 𝒫::Vector{<:ResourcePooling},
)
    data = get_blendstoragedata(n)
    isnothing(data) && return nothing
    mode = get_storage_mode(data)
    mode == :relaxed && return nothing

    blend = data.blend
    sub = subresources(blend)
    ℒᶠʳᵒᵐ, _ = EMB.link_sub(ℒ, n)
    ℒ_out = filter(l -> blend ∈ EMB.link_res(l), ℒᶠʳᵒᵐ)
    fc = m[:flow_component]
    prop = m[:proportion_out]

    if mode == :prescribed
        @constraint(m, [l ∈ ℒ_out, t ∈ 𝒯, p ∈ sub],
            fc[l, t, p] == discharge_composition(data, p, t) * m[:link_in][l, t, blend]
        )
        @constraint(m, [t ∈ 𝒯, p ∈ sub],
            prop[n, t, p] == discharge_composition(data, p, t)
        )
    else  # :fully_mixed
        @constraint(m, [l ∈ ℒ_out, t ∈ 𝒯, p ∈ sub],
            fc[l, t, p] == prop[n, t, p] * m[:link_in][l, t, blend]
        )
        @constraint(m, [t ∈ 𝒯, p ∈ sub],
            m[:stor_level_component][n, t, p] == prop[n, t, p] * m[:stor_level][n, t]
        )
        _constraints_proportion_normalisation(m, n, sub, ℒ_out, 𝒯)
    end
end
