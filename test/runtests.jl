using Test

using Pkg
Pkg.activate(@__DIR__)

using Test

using Alpine
using Ipopt
using HiGHS
using Juniper 
using PiecewiseAffineApprox

using JuMP
using TimeStruct
using EnergyModelsBase
using EnergyModelsPooling

const EMB = EnergyModelsBase
const EMP = EnergyModelsPooling

include("test_utils.jl")

@testset "EnergyModelsPooling" begin

    include("test_pressure.jl")
    include("test_blending.jl")
    include("test_blending_pressure.jl")

end