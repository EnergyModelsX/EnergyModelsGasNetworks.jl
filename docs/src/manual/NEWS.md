# [Release Notes](@id man-news)

## v0.1 (work in progress)
- Initial pressure-capable extension of `EnergyModelsBase` with `ResourcePressure` and Weymouth-based link constraints.
- Pooling formulation for blended resources with component tracking and quality bounds.
- Piecewise-affine approximation workflow for blended-gas pressure drops, including `set_optimizer_pwa!` and `set_step_pressure!` controls.
- Example scripts for single-component pressure (`single_pressure.jl`) and compositional pooling (`pooling.jl`).
