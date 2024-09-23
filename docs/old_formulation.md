# Pooling problem - EMX

### Structs
1. ResourceComponent
2. ResourceBlend
4. RefSourceComponent <: Source
3. RefBlending <: NetworkNode
4. RefBlendingSink <: Sink

### Indices and Sets
$i,j \in \A$: Areas
$tm \in L$: Transmission modes connecting areas
$l$: Links between components within areas
$s \in S$: Source nodes
$t$: Time

### Variables
$y^{s}_{tm, t}$: Ratio of the flow in transmission $tm$ coming from source $s$
$f_{(i,j)}$: Total flow from $i$ to $j$ (from EMG)



### Objective function

### Balance equations
When an area contains a **sink node**, the ratio of flows $y^{s}_{tm^{in}, t}$ from the inflow equals the ratio from the outflow $y^{s}_{tm^{out}, t}$. Note that a sink node must the single node within an area. This means that you must have the same number of transmission modes going in and out of the area as blending cannot occur.

$$y^{s}_{tm^{in}, t} = y^{s}_{tm^{out}, t}, \ \ \forall \ tm^{in} \in L, tm^{out} \in \{tm | L^{-}_{a}, a=A^{in}_{t^{in}}\}, t \in T$$



