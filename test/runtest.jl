using Xpress
using JuMP
using TimeStruct
using EnergyModelsBase
using EnergyModelsGeography
using EnergyModelsPooling
using Test
using TestItems

const EMB = EnergyModelsBase
const EMG = EnergyModelsGeography
const EMP = EnergyModelsPooling

include("utils.jl")

@testset "test EnergyModelsPooling" begin
    
    @testset "Pooling | Only Blend" begin
        include("case1.jl")
    end

end
