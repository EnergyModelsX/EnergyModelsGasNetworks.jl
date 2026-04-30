# EnergyModelsGasNetworks – Copilot Instructions

`EnergyModelsGasNetworks` (EMGN) is a Julia extension package on top of [`EnergyModelsBase`](https://github.com/EnergyModelsX/EnergyModelsBase.jl) that adds pressure-feasible gas transport and pooling of blended gases (e.g. hydrogen–methane) to the EnergyModelsX ecosystem. It uses JuMP for model construction.

## Build & Test

```julia
# From Julia REPL, in the project root:
using Pkg; Pkg.test()

# Or from the shell:
julia --project test/runtests.jl
```

Tests use the standard `Test` module with `@testset` blocks. Individual test files depend on globals (solver objects) set up in `runtests.jl`, so the easiest way to run a single file interactively is:

```julia
using Pkg; Pkg.activate(".")
# ... set up optimizer variables as in runtests.jl, then:
include("test/test_pressure.jl")
```

CI runs on Julia `lts` (1.10) and the latest stable release, on Ubuntu and Windows.

## Examples

Runnable examples live in `examples/`:

```julia
include("examples/pressure.jl")   # pressure drop with Taylor cuts
include("examples/pooling.jl")    # hydrogen–methane blending (Haverly)
```

Each script is self-contained: it builds a case, sets an optimiser, solves, and prints results with `PrettyTables`.

## Code Formatting

Formatting is enforced by JuliaFormatter. Key rules from `.JuliaFormatter.toml`:
- Line length limit: **92 characters**
- `for ... in` loops must use the Unicode `∈` operator (`for x ∈ collection`)
- Short function definitions are **not** expanded to long form
- `always_use_return` is `false` (explicit `return` not required)
- Alignment is enabled: `align_assignment = true`, `align_conditional = true`, `align_pair_arrow = true`
- `join_lines_based_on_source = true` — the formatter respects existing manual line breaks

Format with:
```julia
using JuliaFormatter; format(".")
```

The `format_check.yml` CI job runs `format("src", ...)`, `format("test", ...)`, and `format("docs", ...)` and fails the PR if any diff is produced. Always run the formatter before pushing.

## Architecture

### Extension Model

EMGN extends EnergyModelsBase purely through Julia multiple dispatch. The key extension points (all in `src/model.jl`) are:

- `EMB.variables_node` – adds `potential_Δ` for `Compressor` nodes
- `EMB.variables_flow_resource` – adds `potential_in`/`potential_out` (for `ResourcePressure`) and `flow_component[link,t,subres]`/`proportion_out[node,t,subres]` (for `ResourcePooling`) to links and nodes respectively
- `EMB.constraints_resource` – dispatches on node/link type × resource type to add pressure balance or blending constraints
- `EMB.constraints_couple_resource` – adds coupling constraints between nodes and links (pressure coupling, bidirectional pressure, pooling proportions/quality/tracking)

The dispatch matrix is: `{ResourcePressure, ResourcePooling, ResourcePooling{<:ResourcePressure}}` × `{Node subtypes, Link subtypes}`.

### Resource Types

| Type | Purpose |
|------|---------|
| `ResourcePressure` | Gas with a pressure potential (e.g. H₂, CH₄, NG) |
| `ResourcePooling{R}` | Blend of multiple `R` subresources; activates pooling constraints; activates pressure too when `R <: ResourcePressure` |
| `CompoundResource` | Abstract supertype for both of the above |

### Node & Link Types

- **`SimpleCompressor`** – `NetworkNode` that increases pressure (`potential_Δ`); requires an energy input resource in `input`
- **`PoolingNode`** – `NetworkNode` where `cap_use` is the sum of inflows from blend subresources (not a single resource); exactly one output resource expected
- **`RefConversion / UnitConversion`** – lossless unit-conversion node (e.g. Sm³/d → MWh/d); no capacity or OPEX; requires `FlowToEnergyData`; must have exactly one input and one output
- **`CapDirect`** – `Link` with an explicit `cap::TimeProfile` capacity limit and `data` field for pressure/blend extension data; default link capacity in EMB is 1e6

### Data Types

Attached to nodes and links via the `data::Vector{<:ExtensionData}` field:

- `FixPressureData` / `MaxPressureData` / `MinPressureData` – fix or bound the pressure at a node or link endpoint
- `PressureLinkData` – Weymouth constant, min/max inlet pressure; required on any link with pressure flow; also triggers PWA generation
- `RefBlendData` – per-resource min/max quality bounds at a node
- `BlendLinkData` – blend tracking for Weymouth PWA on links carrying blended gas; specifies a `tracking_res` (e.g. H₂) with its molar mass and the `other_res`

### Weymouth Flow–Pressure Constraints

Single-component gas uses Taylor linearization cuts. Blended gas uses piecewise-affine (PWA) approximations via `PiecewiseAffineApprox.jl`:

- Call `EMGN.set_optimizer_pwa!(opt)` **before** `create_model()` to provide the optimizer used when generating the PWA.
- Call `EMGN.set_step_pressure!(step)` to control PWA pressure resolution (default 10, in the same units as pressures in the data).
- PWA approximations are **cached** to JSON under a Scratch.jl scratch space keyed on the link parameters; call `EMGN.delete_cache()` to invalidate.

### Pooling Formulation

Component-flow pooling formulation (replaces the earlier Alfaki & Haugland (2013) approach). Key variables:

- `flow_component[link, t, subres]` – volumetric flow of each sub-resource through every blend-carrying link
- `proportion_out[node, t, subres]` – fraction of each sub-resource in the blend leaving a node; defined for all nodes that output a `ResourcePooling`

Constraint structure:

| Location | Constraint type |
|---|---|
| Every blend link | `link_in[l,t,blend] = Σ_p flow_component[l,t,p]` (linear) |
| Source inject links | `flow_component[l,t,p] = link_in[l,t,p]` (linear, fixed) |
| All non-source nodes | Component mass balance: `Σ_in flow_component = Σ_out flow_component` (linear) |
| `TransitNode` / `NetworkNode` | `proportion_out[n] = proportion_out[upstream]` passthrough (linear, big-M on `has_flow`) |
| All blend nodes | `Σ_p proportion_out[n,t,p] = 1` normalisation (linear, universal) |
| `PoolingNode` with ≥2 blend outputs | `flow_component[l_out,t,p] = proportion_out[n,t,p] × link_in[l_out,t,blend]` (bilinear — only location of non-linearity) |

The PWA pressure constraint in `constraints_pwa` uses `proportion_out[l.from, t, p]` directly.

Bilinear terms are **only** introduced at `PoolingNode`s with multiple downstream blend links — all other nodes use purely linear constraints. This reduces NLP complexity significantly compared to the Alfaki formulation.

Quality bounds (`RefBlendData`) are enforced via linear inequalities on `proportion_out`.

## Key Conventions

- **Unicode identifiers** following EnergyModelsBase style: `𝒯` (time periods), `𝒫` (resources), `𝒩` (nodes), `ℒ` (links); filtered subsets use superscripts, e.g. `𝒫ⁿ`, `ℒᵗᵒ`.
- `const EMB = EnergyModelsBase` is the standard alias; use `EMB.` to call base-package functions.
- `for x ∈ collection` — always `∈`, never `in`.
- `@assert_or_log` from EMB is used in `checks.jl` (not Julia's `@assert`) so multiple validation errors accumulate before throwing.
- Several `@warn` debug lines remain in `src/model.jl` (e.g. `@warn "Variables_flow_resource 0"`) — these are intentional development artifacts, not errors.
- `src/structures/data.jl` accessor functions (`get_pressuredata`, `get_blenddata`, `pressure`, `get_pwa`, etc.) are the intended API for reading data from nodes/links — avoid direct field access.
- `structures/data_units.jl` and `data_functions.jl` handle the `FlowToEnergyData` / `RefConversion` unit-conversion path; `resource_lhv` dispatches on whether the input is a `ResourcePooling` (weighted average LHV) or a plain resource (fixed LHV from data).
- `ResourceComponentPotential` and `ResourceComponent` appear in the `export` list but are not yet defined in `structures/resource.jl` — treat these as reserved/future type names and do not add code that depends on them.
