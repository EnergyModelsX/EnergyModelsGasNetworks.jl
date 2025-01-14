function constraints_flow(m, ℒᵗʳᵃⁿˢ, 𝒯)
    TM = [tm for l ∈ ℒᵗʳᵃⁿˢ for tm ∈ EMG.modes(l) if is_pressurepipe(tm)]

    @constraint(
        m, [tm ∈ TM, t ∈ 𝒯],
        m[:trans_in][tm, t] <= EMG.capacity(tm, t) * m[:has_flow][tm, t]
    )
end

function pressure_balance(m, a::Area, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    return nothing
end
function pressure_balance(m, a::SourceArea, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    ℒᵒᵘᵗ = EMG.corr_from(a, ℒᵗʳᵃⁿˢ)
    
    for l ∈ ℒᵒᵘᵗ, tm ∈ EMG.modes(l)
        @constraint(m, [t ∈ 𝒯], 
        m[:p_in][tm, t] <= pressure(a) * m[:has_flow][tm, t])
    end
end
function pressure_balance(m, a::PoolingArea, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    ℒⁱⁿ = EMG.corr_to(a, ℒᵗʳᵃⁿˢ)
    ℒᵒᵘᵗ = EMG.corr_from(a, ℒᵗʳᵃⁿˢ)

    TM_in = [tm for l_in ∈ ℒⁱⁿ for tm in EMG.modes(l_in) ]
    TM_out = [tm for l_out ∈ ℒᵒᵘᵗ for tm in EMG.modes(l_out)]

    if length(TM_in) > 1
        @constraint(m, [t ∈ 𝒯],
                sum(m[:lower_pressure_into_node][tm_in, t] for tm_in ∈ TM_in) == 1)

        for tm_in ∈ TM_in, tm_out ∈ TM_out
            max_in = max_pressure(tm_in)

            @constraint(m, [t ∈ 𝒯],
                m[:p_in][tm_out, t] >= m[:p_out][tm_in, t] - max_in * (1 - m[:lower_pressure_into_node][tm_in, t]))
            
            @constraint(m, [t ∈ 𝒯],
                m[:lower_pressure_into_node][tm_in, t] <= m[:has_flow][tm_in, t])
            
            @constraint(m, [t ∈ 𝒯],
                m[:p_in][tm_out, t] <= m[:p_out][tm_in, t] + max_pressure(tm_out) * (1 - m[:has_flow][tm_in, t]))
        end 
    else
        tm_in = first(TM_in)

        for tm_out ∈ TM_out
            @constraint(m, [t ∈ 𝒯],
                m[:p_in][tm_out, t] >= m[:p_out][tm_in, t] - max_pressure(tm_in) * (1 - m[:has_flow][tm_in, t]))
            @constraint(m, [t ∈ 𝒯],
                m[:p_in][tm_out, t] <= m[:p_out][tm_in, t])
        end
    end
end
function pressure_balance(m, a::TerminalArea, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    ℒⁱⁿ = EMG.corr_to(a, ℒᵗʳᵃⁿˢ)
    TM_in = [tm for l_in ∈ ℒⁱⁿ for tm in EMG.modes(l_in)]

    for tm_in ∈ TM_in
        @constraint(m, [t ∈ 𝒯],
            m[:p_out][tm_in, t] >= pressure(a) * m[:has_flow][tm_in, t])
    end
end

"""
    constraints_weymouth(m, a::Union{SourceArea, PoolingArea}, pwa::PWAFunc{C1, D1}, 𝒫, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)

    When pwa::PWAFunc, the problem must contain two components (1 resource) as the pwa is used for approximating the Weymouth with 2 resources.
    When pwa::Any, the problem is for one resources and the Weymouth will be approximated using the Taylor first-order approximation.
"""
function constraints_weymouth(m, a::Union{SourceArea, PoolingArea}, pwa::PWAFunc{C1, D1}, 𝒫, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯) where {C1, D1} 
    
    if length(𝒞) == 2 #TODO: Examine the possibility of just using Resources rather than components
        p = first(filter(p -> is_component_track(p), 𝒞))
        if isnothing(p)
            throw(ArgumentError("One of the Components must be of type ComponentTrack."))
        end

        for (k, plane) ∈ enumerate(pwa.planes)
            for t ∈ 𝒯
                add_weymouth(m, a, p, ℒᵗʳᵃⁿˢ, t, plane, C1, D1)
            end
        end
    else
        throw(ArgumentError("Pressure capabilities not supported for more than 2 Components."))
    end
end
function constraints_weymouth(m, a::Union{SourceArea, PoolingArea}, pwa, 𝒫, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    𝒫ꜝ = filter(p -> !EMB.is_resource_emit(p), 𝒫)
    
    if length(𝒫ꜝ) > 1
        throw(ArgumentError("Pressure constraints only available for 1 Resource and 1 Resource + 2 Components"))
    elseif length(𝒞) != 0
        throw(ArgumentError("For systems with Components, ensure you add the pwa (plane approximations)."))
    else
        p = first(𝒫ꜝ)

        for t ∈ 𝒯
            add_weymouth(m, a, p, ℒᵗʳᵃⁿˢ, t, nothing, nothing)
        end
    end
end
function constraints_weymouth(m, a::TerminalArea, pwa::Any, 𝒫, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    return nothing
end
function add_weymouth(m, a::Union{PoolingArea, SourceArea}, p::ComponentTrack, ℒᵗʳᵃⁿˢ, t, plane, C1, D1)
    ℒᵒᵘᵗ = EMG.corr_from(a, ℒᵗʳᵃⁿˢ)

    for l ∈ ℒᵒᵘᵗ, tm ∈ EMG.modes(l)
        PiecewiseAffineApprox.constr(C1, m, m[:trans_in][tm, t], plane, (m[:p_in][tm, t], m[:p_out][tm, t], m[:prop_track][p, a, t]))
    end 
end
function add_weymouth(m, a::Union{PoolingArea, SourceArea}, p::Resource, ℒᵗʳᵃⁿˢ, t, C1, D1)
    ℒᵒᵘᵗ = EMG.corr_from(a, ℒᵗʳᵃⁿˢ)

    for l ∈ ℒᵒᵘᵗ, tm ∈ EMG.modes(l)
        K_W = weymouth_ct(tm)
        P = linearised_pressures(tm)
        for (PIn, POut) ∈ P
            @constraint(m, 
            m[:trans_in][tm, t] <= K_W * (
                                            (PIn/(sqrt(PIn^2 - POut^2))) * m[:p_in][tm, t] -
                                            (POut/(sqrt(PIn^2 - POut^2))) * m[:p_out][tm, t]
                                          ))
        end
    end
end 