# [Release Notes](@id man-news)

## v0.3.0 (2026-10-06)

### Summary of breaking changes

- Requires `EnergyModelsBase` v0.10.
- The source-attribution pooling variables `proportion_source` and `proportion_track` are
  replaced by `flow_component` on blend links and `proportion_out` at pooling nodes.
- The `lower_pressure_into_node` binary is removed, and `has_flow` is only declared for
  pressure-carrying links.
- Passthrough nodes (e.g. `TransitNode`) send blend down at most one outgoing link per
  period.
- `proportion_out` is only defined at the nodes that need the composition (see
  "Composition tracked only where needed"), no longer at sinks, unit conversions and
  passthrough nodes in general. Use `flow_component` on the links instead.
- Storage of a blended resource requires `BlendStorageData`, which chooses how the
  composition of the discharged gas is modelled. A blend storage without it is rejected.

### Composition tracked only where needed

- The component flows give the composition wherever blend mixes. The share
  `proportion_out` is only created at composition sources (pooling nodes, blend storages
  in mode `:prescribed` or `:fully_mixed`) and at the nodes from which a Weymouth pipe with
  `BlendLinkData` reads it ([`blend_share_plan`](@ref EnergyModelsGasNetworks.blend_share_plan)).
- A merge no longer forces simultaneous inflows to have the same composition, unless a
  Weymouth pipe downstream reads the share through it.
- A Weymouth pipe may read the share from its outflow end: from the first pooling node
  downstream, if the pipe is its only blend inflow. A `BlendingNode` may then feed the pipe
  directly.
- A passthrough node with several outgoing blend links no longer needs a share from
  upstream; it only needs `has_flow` on all of them (one active outflow per period).

### Blend storage

- New [`BlendStorageData`](@ref) for `Storage` nodes that store a `ResourcePooling` blend.
  The storage keeps one inventory per component (`stor_level_component`), following the
  level balance and cyclic constraints of `EnergyModelsBase`, so the storage can not
  discharge more of a component than was charged.
- The discharge composition depends on the mode, which must be given:
  - `:relaxed` only bounds the discharge by the inventories (linear);
  - `:prescribed` follows an extraction quality profile (linear);
  - `:fully_mixed` discharges the average stored composition (bilinear). It suits small,
    well-mixed storages, not depleted gas reservoirs.
- Storages no longer copy the composition of their charge within the same period.

### PWA robustness

- PWA fits are seeded from the cache key and checked against the exact Weymouth flow;
  degenerate fits are refitted and never cached.
- `get_pwa` throws an `ArgumentError` when the pressure step leaves fewer than three
  pressure levels in the range of a link, instead of failing in the fit.
- Blend links without `BlendLinkData` use the Taylor cuts without requiring the PWA
  optimizer to be set.

### Breaking: passthrough nodes send blend down one link per period

`TransitNode`s, and other `NetworkNode`s that pass a blend through unchanged, may now only
send blend down one outgoing link in each period. The linear passthrough did not force the
outgoing links to share the node's composition, so a split could send different mixtures
down each link.

- With several outgoing blend links, `Σ has_flow[l_out, t] ≤ 1` is added. Bidirectional
  pipelines are still supported, since only one direction carries flow.
- If any of those links has no `has_flow` binary tied to its flow (no pressure resource),
  `validate_blend_topology` raises an `ArgumentError`.
- Use `PoolingNode` or `DiscretizedPoolingNode` where the blend must split into several
  pipes at the same time.

### Pooling formulation: reduced bilinear complexity

The pooling formulation has been revised to reduce nonlinear complexity relative to the
earlier Alfaki & Haugland (2013) S-formulation, which introduced bilinear products
``y^s_j \times f_{(j,t)}`` scaling with the number of sources, arcs, and time periods.

The revised approach uses the P-formulation variable `proportion_out[n, t, p]` (fraction
of component `p` in the blend leaving node `n` at time `t`). Bilinear products
`proportion_out × link_in` scale with the number of pooling nodes and blend components,
which is substantially smaller for typical gas network models with few blend components.
Three specialised node types further reduce or eliminate the remaining bilinear terms:

### `BlendingNode` — linear single-output mixing node

A new node type [`BlendingNode`](@ref) replaces [`PoolingNode`](@ref) at junctions with
**exactly one outgoing blend link**. It uses a **linear** formulation:

- No `proportion_out` variable is declared for `BlendingNode` nodes.
- Component balance (`flow_component[l_out] = Σ_in flow_component[l_in] + raw_in`) is
  already linear and fully determines the output composition.
- Quality bounds (`flow_component[l_out, H2] ≤ max_h2 × link_in[l_out, Blend]`) remain
  linear because `max_h2` is a fixed parameter, not a variable.

This eliminates bilinear constraints at all single-output mixing junctions (pre-sink,
post-source, single-path transit mixing), which represent the majority of pooling nodes in
typical gas network cases:

| Case | Bilinear terms before | After | Reduction |
|------|-----------------------|-------|-----------|
| Transmission investment case (2 op periods) | 20 | 8 | −60 % |
| Transmission operational case (1 op period) | 126 | 8 | −94 % |

**Usage:** Use `BlendingNode` wherever a mixing node has exactly one `ResourcePooling`
output. Use `PoolingNode` when two or more output blend links must share the same
composition. Case checking rejects a `BlendingNode` whose output dict has more than one
`ResourcePooling` blend, and `validate_blend_topology` raises an `ArgumentError` if a
`BlendingNode` feeds two or more outgoing blend links.

### `DiscretizedPoolingNode` — MILP-compatible piecewise-linear pooling

A new node type [`DiscretizedPoolingNode`](@ref) replaces the bilinear product at
multi-output pooling nodes with a piecewise-linear MILP approximation via
[`PiecewiseLinearOpt.jl`](https://github.com/jump-dev/PiecewiseLinearOpt.jl). The
approximation divides both the proportion and flow axes into intervals controlled by
[`DiscretizationData`](@ref). The model remains a MILP throughout and can be solved by
standard solvers (HiGHS, Xpress, Gurobi) without MINLP machinery.

`DiscretizationData` now accepts an explicit tracked blend component. This removes the
previous dependence on subresource ordering and allows a restricted discretization range
to be applied only to the tracked component. Legacy constructors remain supported when
the tracked component can be inferred unambiguously from adjacent blend-quality data.

### `DeblendNode` — hydrogen extraction processing facility

A new node type [`DeblendNode`](@ref) models on-site separation of a component (e.g., H₂)
from a blend stream, representing processing facilities such as pressure-swing adsorption
(PSA) units. Unlike mixing nodes, `DeblendNode` applies a separation operation: the
extracted component flow is bounded by `psa_efficiency × incoming_component_flow`. All
constraints are linear. This extends the pooling formulation to networks that include
in-network gas processing, following the generalised pooling framework of
Hellemo & Tomasgard (2016, TOP 24:409–444).

### `FlowPressureCompressor` — flow- and pressure-dependent compressor power

A new compressor type [`FlowPressureCompressor`](@ref) extends [`SimpleCompressor`](@ref)
with power consumption that depends linearly on **both** the gas flow rate and the pressure
increase:

```
Power ≥ flow_weight × cap_use + pressure_weight × potential_Δ
```

This is physically more accurate than `SimpleCompressor` (which ignores flow rate) for
compressors operating over a range of flow conditions. The `flow_weight` and `pressure_weight`
coefficients are computed from the physical design point using the linearisation formula
described in the [`FlowPressureCompressor`](@ref) docstring.

### Binary variable simplification

The `lower_pressure_into_node` binary array has been removed. Pressure-coupling at
nodes with multiple incoming links now uses `has_flow` as the big-M switch for both
the upper and lower bounds on `potential_in[n]`. When `has_flow[l,t]=1` both bounds
bind, forcing `potential_in[n] = link_potential_out[l]` for every active link.

For parallel investment pipeline options connecting the same two nodes, this means all
active options see the same endpoint pressures — physically correct junction behaviour
assuming pressure reduction valves harmonise any pressure differences. The previous
`sum(lower_pressure_into_node) ≤ 1` coupling constraint is eliminated, removing an
artificial restriction that prevented correct selection among parallel pipeline options.

`has_flow` is still declared only for **pressure-carrying links** — those whose
`link_res` includes at least one `CompoundResource` (`ResourcePressure` or
`ResourcePooling{<:ResourcePressure}`). Power-only links remain excluded.

The capacity big-M now uses the maximum possible installed link capacity rather than the
initial physical capacity. Investable pressure links can therefore use capacity added
during the study without weakening the time-dependent `link_cap_inst` constraint.

### Supported topology boundaries

A storage of a blend needs [`BlendStorageData`](@ref) and a `Cyclic` storage behaviour.
Storages in mode `:prescribed` or `:fully_mixed` set the composition of their discharge and
may feed several links and `BlendLinkData` links; storages in mode `:relaxed` may not.

`BlendingNode` and `DeblendNode` retain fully linear component-flow formulations and do
not define `proportion_out`. Their output may feed single-output blend paths, and a
Weymouth pipe with `BlendLinkData` only if the pipe is the only blend inflow of a pooling
node downstream. Use [`PoolingNode`](@ref) or [`DiscretizedPoolingNode`](@ref) where a
composition must be shared over several simultaneous outflows or a Weymouth pipe needs it.

## v0.2.0 - v0.2.2
- Release the first version of `EnergyModelsGasNetworks` publicly after development phase.
- Version aligned with the current `EnergyModelsBase` branch `enhance/transfer_energy_potentials` (date: 26/02/2026). Updates will be required when the corresponding branch is merged into the `main` branch.
