# [Quick Start](@id man-quick_start)

1. Install the most recent version of [Julia](https://julialang.org/downloads/)
2. Install the package [`EnergyModelsBase`](https://energymodelsx.github.io/EnergyModelsBase.jl/) and the time package [`TimeStruct`](https://sintefore.github.io/TimeStruct.jl/), by running:

  ```julia
  ] add TimeStruct EnergyModelsBase
  ```

    These packages are required as we do not only use them internally, but also for building a model.
3. Install the package [`EnergyModelsGasNetworks`](https://energymodelsx.github.io/EnergyModelsGasNetworks.jl/)
   
  ```julia
  ] add EnergyModelsGasNetworks
  ```

4. Install the package [JuMP](https://github.com/jump-dev/JuMP.jl/) by running:

  ```julia
  ] add JuMP
  ```
5. Install a suitable solver
    
    Some constraints defined in `EnergyModelsGasNetworks` are nonlinear and nonconvex. 

    - **Pooling constraints**. The pooling formulation introduces bilinear terms (non-convex quadratic), defining a nonconvex QCQP (and, if integer variables are present, a nonconvex MINLP). 
        
    - **Pressure-flow constraints for blended gases**. The pressure-flow relation for blended gases is also nonlinear and nonconvex (adapted Weymouth equation for blended gases). However, within the physically operating region (i.e., inlet pressure >= outlet pressure, nonnegative flows and bounded pressures), the relation is smooth and monotonic. To obtain a MILP, we approximate the nonlinear surface using a piecewise-affine outer approximation built from tangent planes via [`PiecewiseAffineApprox`](https://sintefore.github.io/PiecewiseAffineApprox.jl/stable/). 
    
    Consequently, when pooling and/or pressure-flow constraints are enabled, you need a solver capable of handling nonconvex MINLP problems. [`SCIP`](https://github.com/scipopt/SCIP.jl) is the recommended open-source option; commercial alternatives such as Gurobi and Xpress also work.

  ```julia
  ] add SCIP, HiGHS
  using JuMP, SCIP, HiGHS
  model = Model(SCIP.Optimizer)
  ```

  When only `DiscretizedPoolingNode` and `BlendingNode` are used (no `PoolingNode`), the model is a pure MILP and HiGHS suffices:

  ```julia
  model = Model(HiGHS.Optimizer)
  ```

!!! tip "JuMP and solver"
    While JuMP is automatically installed when you add `EnergyModelsBase`, it is still necessary to load it to optimize a model or extract the results.
    It is hence necessary to load it in each model run explicitly.

    `EnergyModelsX` models are in general agnostic towards which solver is used.
    They are hence not automatically included.
    Therefore, they require you to explicitly load the corresponding solver.