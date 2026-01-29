module EnergyModelsPooling

using EnergyModelsBase
const EMB = EnergyModelsBase
using TimeStruct
using JuMP

using PiecewiseAffineApprox
using LinearAlgebra

using Scratch
using JSON3

### PARAMETERS
const _STEP_PRESSURE = Ref(10) # Pressure step for PWA approximation
get_step_pressure() = _STEP_PRESSURE[]
set_step_pressure!(step_pressure) = (_STEP_PRESSURE[] = step_pressure)

const _OPT = Ref{Any}(nothing)
"""
Set the optimizer used by EnergyModelsPooling for PWA approximations.
"""
set_optimizer!(opt) = (_OPT[] = opt)
"Get optimizer; error if not set."
function _get_optimizer()
    opt = _OPT[]
    opt === nothing && error("B: optimizer not set. Call B.set_optimizer!(...) first.")
    return opt
end

include("utils.jl")
include("scratch.jl")
include("structures/resource.jl")
include("structures/node.jl")
include("structures/link.jl")
include("structures/data.jl")
# include("structures/area.jl")
include("constraint_blend.jl")
include("constraint_pressure.jl")
include("model.jl")

export create_model
export SimpleCompressor, PoolingNode, CapDirect
export ResourcePressure, ResourceComponentPotential, ResourceComponent, ResourcePooling
export FixPressureData, MaxPressureData, MinPressureData, PressureLinkData
export RefBlendData, BlendLinkData

end
