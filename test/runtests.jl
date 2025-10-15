
using Alpine
using DataFrames
using EnergyModelsBase
using EnergyModelsPooling
using HiGHS
using Ipopt
using JuMP
using Juniper 
using PiecewiseAffineApprox
using Test
using TimeStruct
mip_optimizer = optimizer_with_attributes(HiGHS.Optimizer, MOI.Silent() => true)
try
    import Xpress_jll
    ENV["XPRESS_JL_LIBRARY"] = Xpress_jll.libxprs
    ENV["XPAUTH_PATH"] = realpath(joinpath("xpauth.xpr"))
    ENV["XPRESS_JL_SKIP_LIB_CHECK"] = true
    import Pkg
    Pkg.add("Xpress")
    using Xpress
    global mip_optimizer = optimizer_with_attributes(Xpress.Optimizer, MOI.Silent() => true)
catch err
    nothing
end

const EMB = EnergyModelsBase
const EMP = EnergyModelsPooling

nl_solver = optimizer_with_attributes(Ipopt.Optimizer, MOI.Silent() => true, "sb" => "yes")
minlp_optimizer = optimizer_with_attributes(Juniper.Optimizer, MOI.Silent() => true, "mip_solver" => mip_optimizer, "nl_solver" => nl_solver)
optimizer = optimizer_with_attributes(
    Alpine.Optimizer,
    "nlp_solver" => nl_solver,
    "mip_solver" => mip_optimizer,
    "minlp_solver" => minlp_optimizer,
    "rel_gap" => 0.01,
    "presolve_bt" => false,
    "time_limit" => 300,
)

include("test_utils.jl")

@testset "EnergyModelsPooling" begin

    include("test_pressure.jl")
    include("test_blending.jl")
    include("test_blending_pressure.jl")

end