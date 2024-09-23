module EnergyModelsPooling

using JuMP
using EnergyModelsBase; const EMB = EnergyModelsBase
using EnergyModelsGeography; const EMG = EnergyModelsGeography
using TimeStruct
using MetaGraphs
using Graphs


include("structures/energy.jl")
include("structures/resource.jl")
include("structures/node.jl")
include("structures/area.jl")
include("utils.jl")
include("model.jl")
include("readgms.jl")


export ResourceBlend, RefBlendingSink, ResourceComponent, RefSourceComponent, RefEnergyContent, RefBlending
export BlendArea, TerminalArea, BlendAvailability
export create_model
export loadGamsFile

end