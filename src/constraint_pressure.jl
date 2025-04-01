function constraints_flow(m, ℒᵗʳᵃⁿˢ, 𝒯)
    TM = [tm for l ∈ ℒᵗʳᵃⁿˢ for tm ∈ EMG.modes(l) if has_pressuredata(tm)]

    @constraint(
        m, [tm ∈ TM, t ∈ 𝒯],
        m[:trans_in][tm, t] <= EMG.capacity(tm, t) * m[:has_flow][tm, t]
    )
end

function pressure_balance(m, a::Area, data, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    return nothing
end
function pressure_balance(m, a::SourceArea, data::PressureMaxArea, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    ℒᵒᵘᵗ = EMG.corr_from(a, ℒᵗʳᵃⁿˢ)
    
    for l ∈ ℒᵒᵘᵗ, tm ∈ EMG.modes(l)
        @constraint(m, [t ∈ 𝒯], 
        m[:p_in][tm, t] <= pressure(a, t) * m[:has_flow][tm, t])
    end
end
function pressure_balance(m, a::SourceArea, data::PressureMinArea, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    ℒᵒᵘᵗ = EMG.corr_from(a, ℒᵗʳᵃⁿˢ)
    
    for l ∈ ℒᵒᵘᵗ, tm ∈ EMG.modes(l)
        @constraint(m, [t ∈ 𝒯], 
        m[:p_in][tm, t] >= pressure(a, t)  * m[:has_flow][tm, t])
    end
end
function pressure_balance(m, a::SourceArea, data::PressureFixedArea, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    ℒᵒᵘᵗ = EMG.corr_from(a, ℒᵗʳᵃⁿˢ)
    
    for l ∈ ℒᵒᵘᵗ, tm ∈ EMG.modes(l)
        @constraint(m, [t ∈ 𝒯], 
        m[:p_in][tm, t] == pressure(a, t) * m[:has_flow][tm_in, t])
    end
end

function pressure_balance(m, a::PoolingArea, data, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
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
function pressure_balance(m, a::TerminalArea, data::PressureMaxArea, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    ℒⁱⁿ = EMG.corr_to(a, ℒᵗʳᵃⁿˢ)
    TM_in = [tm for l_in ∈ ℒⁱⁿ for tm in EMG.modes(l_in)]

    for tm_in ∈ TM_in
        @constraint(m, [t ∈ 𝒯],
            m[:p_out][tm_in, t] <= pressure(a, t) * m[:has_flow][tm_in, t])
    end
end
function pressure_balance(m, a::TerminalArea, data::PressureMinArea, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    ℒⁱⁿ = EMG.corr_to(a, ℒᵗʳᵃⁿˢ)
    TM_in = [tm for l_in ∈ ℒⁱⁿ for tm in EMG.modes(l_in)]

    for tm_in ∈ TM_in
        @constraint(m, [t ∈ 𝒯],
            m[:p_out][tm_in, t] >= pressure(a, t)  * m[:has_flow][tm_in, t])
    end
end
function pressure_balance(m, a::TerminalArea, data::PressureFixedArea, ℒᵗʳᵃⁿˢ, links, 𝒯, 𝒫)
    ℒⁱⁿ = EMG.corr_to(a, ℒᵗʳᵃⁿˢ)
    TM_in = [tm for l_in ∈ ℒⁱⁿ for tm in EMG.modes(l_in)]

    for tm_in ∈ TM_in
        @constraint(m, [t ∈ 𝒯],
            m[:p_out][tm_in, t] == pressure(a, t)  * m[:has_flow][tm_in, t])
    end
end

"""
    constraints_weymouth(m, a::Union{SourceArea, PoolingArea}, pwa::PWAFunc{C1, D1}, 𝒫, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)

    For SourceArea, all transmission carry one resource => always use Taylor approximation
"""
function constraints_weymouth(m, a::SourceArea, 𝒫, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
    p = first(EMG.export_resources(ℒᵗʳᵃⁿˢ, a))
    ℒᵒᵘᵗ = EMG.corr_from(a, ℒᵗʳᵃⁿˢ)

    for l ∈ ℒᵒᵘᵗ
        for tm ∈ EMG.modes(l)
            constraints_taylor(m, a, p, ℒᵗʳᵃⁿˢ, tm, 𝒯)
        end
    end
end
function constraints_weymouth(m, a::PoolingArea, 𝒫, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)

    if length(𝒞) == 2 #TODO: Examine the possibility of just using Resources rather than components
        p = first(filter(is_component_track, 𝒞))
        if isnothing(p)
            throw(ArgumentError("One of the Components must be of type ComponentTrack."))
        end
    else
        p = first(EMG.export_resources(ℒᵗʳᵃⁿˢ, a))
    end

    ℒᵒᵘᵗ = EMG.corr_from(a, ℒᵗʳᵃⁿˢ)
    for l ∈ ℒᵒᵘᵗ
        for tm ∈ EMG.modes(l)
            if is_pressurepipe(tm)
                constraints_taylor(m, a, p, ℒᵗʳᵃⁿˢ, tm, 𝒯)
            else
                pwa = get_pwa(tm)
                for (k, plane) ∈ enumerate(pwa.planes)
                    constraints_pwa(m, a, p, tm, 𝒯, plane, pwa)
                end      
            end
        end
    end      
end
function constraints_weymouth(m, a::Area, 𝒫, 𝒞, ℒᵗʳᵃⁿˢ, links, 𝒯)
end

function constraints_taylor(m, a, p, ℒᵗʳᵃⁿˢ, tm::EMG.TransmissionMode, 𝒯)
    K_W = weymouth_ct(tm)
    P = linearised_pressures(tm)
    for (PIn, POut) ∈ P
        @constraint(m, [t ∈ 𝒯],
        m[:trans_in][tm, t] <= sqrt(K_W) * (
                                        (PIn/(sqrt(PIn^2 - POut^2))) * m[:p_in][tm, t] -
                                        (POut/(sqrt(PIn^2 - POut^2))) * m[:p_out][tm, t]
                                        ))
    end
end
function constraints_pwa(m, a::PoolingArea, p::ComponentTrack, tm, 𝒯, plane, pwa::PWAFunc{C1, D1}) where {C1, D1}
    for t ∈ 𝒯
        PiecewiseAffineApprox.constr(C1, m, m[:trans_in][tm, t], plane, (m[:p_in][tm, t], m[:p_out][tm, t], m[:prop_track][p, a, t]))
    end
end