"""
    abstract type Behaviour

Behaviour is used to identify if a `SourceArea`, `PoolingArea` and `TerminalArea` include pressure, blending or both parameters. 
It is used to dispatch the model constraints.
"""
abstract type Behaviour end

"""
    abstract type NetworkAreas <: EMG.Area

`NetworkAreas` as supertype for the areas whose imports and/or exports are subject to pressure and/or blending constraints.

There are source, pooling (intermediate nodes) and terminal network areas which conforms a unidirectional network. 
These areas have dependencies between each other, so when requiring blending and pressure constraints, the network must be created using only `NetworkArea`s.
"""
abstract type NetworkAreas <: EMG.Area end


"""
    struct Pressure <: Behaviour

A behaviour type for `NetworkAreas` for dispatching with pressure constraints. 

# Fields
- **`pressure::Any`** The pressure value. The pressure will be considered differently depending on the type of `NetworkArea`.
    For SourceArea, the pressure is the maximum outlet pressure.
    For PoolingArea, the value is not used. But, the behaviour is necessary for appropriate dispatching in the model.
    For TerminalArea, the pressure is the minimum inlet pressure.

"""
struct Pressure <: Behaviour
	pressure::Any
end

"""
    struct Blending <: Behaviour

A behaviour type for ``NetworkAreas``for ensuring dispatching with blending constraints.

# Fields
- **`id::String`** The identifier of the blending behaviour.
"""
struct Blending <: Behaviour
	id::String
end

"""
    struct PressBlend <: Behaviour

A behaviour type for ``NetworkAreas``for ensuring dispatching with blending and pressure constraints.

# Fields
- **`pressure::Any`** The pressure value. The pressure will be considered differently depending on the type of `NetworkArea`.
    For SourceArea, the pressure is the maximum outlet pressure.
    For PoolingArea, the value is not used. But, the behaviour is necessary for appropriate dispatching in the model.
    For TerminalArea, the pressure is the minimum inlet pressure.
"""
struct PressBlend <: Behaviour
	pressure::Any
end

"""
    struct SourceArea <: NetworkAreas

It is a network area that will only inject resources into the network. It requires Source nodes in its local energy system.

# Fields
- **`id::Any`** The identifier of the area.
- **`name::Any`** The name of the area.
- **`lon::Real`** The longitude of the area.
- **`lat::Real`** The latitude of the area.
- **`node::EMB.Availability`** The availability node of the area from `EnergyModelsBase``.
- **`behaviour::Behaviour`** The `Behaviour` of the area.
"""
struct SourceArea <: NetworkAreas
	id::Any
	name::Any
	lon::Real
	lat::Real
	node::EMB.Availability
	behaviour::Behaviour
end

"""
    struct PoolingArea <: NetworkAreas

It is the intermediate network area that connects `SourceArea` and `TerminalArea`. 
They do not have any associated local energy system. Their main purpose is to dispatch with blending and pressure constraints when connecting between source and terminal areas.

# Fields
- **`id::Any`** The identifier of the area.
- **`name::Any`** The name of the area.
- **`lon::Real`** The longitude of the area.
- **`lat::Real`** The latitude of the area.
- **`node::EMB.Availability`** The availability node of the area from `EnergyModelsBase``.
- **`behaviour::Behaviour`** The `Behaviour` of the area.
"""
struct PoolingArea <: NetworkAreas
	id::Any
	name::Any
	lon::Real
	lat::Real
	node::EMB.Availability
	behaviour::Behaviour
end

"""
    struct TerminalArea <: NetworkAreas

It is a network area that only withdraws resources from the network. It requires Sink nodes in its local energy system.

# Fields
- **`id::Any`** The identifier of the area.
- **`name::Any`** The name of the area.
- **`lon::Real`** The longitude of the area.
- **`lat::Real`** The latitude of the area.
- **`node::EMB.Availability`** The availability node of the area from `EnergyModelsBase``.
- **`behaviour::Behaviour`** The `Behaviour` of the area.
"""
struct TerminalArea <: NetworkAreas 
	id::Any
	name::Any
	lon::Real
	lat::Real
	node::EMB.Availability
	behaviour::Behaviour 
end

"""
    behaviour(a::NetworkAreas)

Returns the behaviour of the network area `a`.
"""
behaviour(a::NetworkAreas) = a.behaviour

"""
    is_blendbehaviour(b::Behaviour)

Returns true if the behaviour `b` has a blending behaviour.
"""
is_blendbehaviour(b::Behaviour) = true
is_blendbehaviour(b::Pressure) = false

"""
    is_pressurebehaviour(b::Behaviour)

Returns true if the behaviour `b` is a pressure behaviour.
"""
is_pressurebehaviour(b::Behaviour) = true
is_pressurebehaviour(b::Blending) = false

"""
    is_blendarea(a::Area)

Checks whether the area `a` has a blending behaviour.
"""
is_blendarea(a::Area) = false
function is_blendarea(a::NetworkAreas) #TODO: Ensure all areas have the field behaviour
	b = behaviour(a)
	is_blend = is_blendbehaviour(b)
	if is_blend
		return true
	else
		return false
	end
end

"""
    is_pressurearea(a::Area)

Checks whether the area `a` has a pressure behaviour.
"""
is_pressurearea(a::Area) = false
function is_pressurearea(a::Union{PoolingArea, SourceArea, TerminalArea})
	behaviour = behaviour(a)
	is_pressure = is_pressurebehaviour(behaviour)
	if is_pressure
		return true
	else
		return false
	end
end

"""
    pressure(a::NetworkAreas)

Returns the pressure of the network area `a` in case of having a `Pressure` behaviour.
"""
function pressure(a::NetworkAreas)
	behaviour = behaviour(a)
	is_pressure = is_pressurebehaviour(behaviour)
	if is_pressure
		return behaviour.pressure
	else
		error("The area $(a.id) has not a pressure behaviour.")
	end
end

"""
    is_terminalarea(a::Area)

Checks whether the area `a` is a terminal area.
"""
is_terminalarea(a::Area) = false
is_terminalarea(a::TerminalArea) = true
