# [Quick Start](@id man-quick_start)

1. Install the most recent version of [Julia](https://julialang.org/downloads/)
2. Install the package [`EnergyModelsBase`](https://energymodelsx.github.io/EnergyModelsBase.jl/) and the time package [`TimeStruct`](https://sintefore.github.io/TimeStruct.jl/), by running:

    ```julia
    ] add TimeStruct
    ] add EnergyModelsBase
    ```

    These packages are required as we do not only use them internally, but also for building a model.
3. Install the package [`EnergyModelsPooling`](https://energymodelsx.github.io/EnergyModelsPooling.jl/)
   
   ```julia
   ] add EnergyModelsPooling
   ```

4. Install the package [JuMP](https://github.com/jump-dev/JuMP.jl/) by running:

   ```julia
   ] add JuMP
   ```
5. Install a suitable solver
    
    Some constraints defined in `EnergyModelsPooling` are nonlinear and nonconvex. 
        - **Pooling constraints**. The pooling formulation introduces bilinear terms (non-convex quadratic), defining a nonconvex QCQP (and, if integer variables are present, a nonconvex MINLP). 
        - **Pressure-flow constraints for blended gases**. The pressure-flow relation for blended gases is also nonlinear and nonconvex (adapted Weymouth equation for blended gases). However, within the physically operating region (i.e., inlet pressure >= outlet pressure, nonnegative flows and bounded pressures), the relation is smooth and monotonic. To obtain a MILP, we approximate the nonlinear surface using a piecewise-affine outer approximation built from tangent planes via [`PiecewiseAffineApprox`](https://sintefore.github.io/PiecewiseAffineApprox.jl/stable/). 
    Consequently, when pooling and/or pressure-flow constraints are enabled, you need a solver capable of handling nonconvex MINLP problems, such as [`Alpine`](https://github.com/lanl-ansi/Alpine.jl), which uses a MIP solver and a continous NLP solver internally.

    ```julia
    ] add Alpine, Ipopt, HiGHS
    using JuMP, Alpine, Ipopt, HiGHS
    ipopt = optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0)
    highs = optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false)
    model = Model(
        optimizer_with_attributes(
            Alpine.Optimizer,
            "nlp_solver" => ipopt,
            "mip_solver" => highs,
        ),
    )
    ```

    Using other MIP solvers such as  *Gurobi* or *Xpress* can significantly improve performance.


!!! tip "JuMP and solver"
    While JuMP is automatically installed when you add `EnergyModelsBase`, it is still necessary to load it to optimize a model or extract the results.
    It is hence necessary to load it in each model run explicitly.

    `EnergyModelsX` models are in general agnostic towards which solver is used.
    They are hence not automatically included.
    Therefore, they require you to explicitly load the corresponding solver.