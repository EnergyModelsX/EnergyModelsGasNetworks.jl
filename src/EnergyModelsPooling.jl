module EnergyModelsPooling

using JuMP
using EnergyModelsBase; const EMB = EnergyModelsBase
using EnergyModelsGeography; const EMG = EnergyModelsGeography
using TimeStruct
using MetaGraphs
using Graphs
using PiecewiseAffineApprox
using LinearAlgebra

include("scratch.jl")
include("structures/resource.jl")
include("structures/node.jl")
include("structures/area.jl")
include("structures/data.jl")
include("utils.jl")
include("constraint_blend.jl")
include("constraint_pressure.jl")
include("model.jl")

export ComponentBlend, AbstractComponent, ComponentTrack
export SourceComponent, BlendingSink
export SourceArea, TerminalArea, PoolingArea, Pressure, Blending, PressBlend
export PressurePipe, PressBlendPipe
export create_model, pwa

end