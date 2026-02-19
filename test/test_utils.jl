function calculate_linearise_pressures()
    P_min = 30.0  # example minimum pressure
    P_max = 70.0  # example maximum pressure
    n = 5         # number of points

    pressures = range(P_min, P_max, length = n)
    pairs = [(p1, p2) for p1 in pressures, p2 in pressures if p1 > p2]

    return pairs
end

"""
    test_approx(pwa, constant, pin, pout, prop)

Compares the approximation results with the value applying the Weymouth equation
"""
function test_approx(pwa, constant, pin, pout, prop, molmass_other, molmass_track)
    for p_out ∈ pout:pin
        println(PiecewiseAffineApprox.evaluate(pwa, (pin, p_out, prop)), "\t",
            calculate_flow_to_approximate(
                constant,
                pin,
                p_out,
                prop,
                molmass_other,
                molmass_track,
            ), "\t",
            PiecewiseAffineApprox.evaluate(pwa, (pin, p_out, prop)) >=
            calculate_flow_to_approximate(
                constant,
                pin,
                p_out,
                prop,
                molmass_other,
                molmass_track,
            ))
    end
end
function test_approx(
    weymouth,
    pressure_points::Vector,
    link_potential_in,
    link_potential_out,
)
    rhs = Float64[]
    for (p_in, p_out) ∈ pressure_points
        value =
            sqrt(weymouth) *
            (
                (p_in / (sqrt(p_in^2 - p_out^2))) * link_potential_in -
                (p_out / (sqrt(p_in^2 - p_out^2))) * link_potential_out
            )
        push!(rhs, value)
    end
    return minimum(rhs)
end

function calculate_rhs_taylor(link_p_in, link_p_out, l)
    pressure_data = first(filter(data -> data isa PressureLinkData, l.data))
    weymouth_ct = EMP.get_weymouth(pressure_data)
    POut, PIn = EMP.potential_data(pressure_data)

    # Determine the (p_in, p_out) points for the Taylor approximation
    pressures_points = [(PIn, p) for p ∈ range(PIn, POut, length = 150)[2:end]]

    # Create Taylor constraint for each point
    RHS_values = []
    for (p_in, p_out) ∈ pressures_points
        val_rhs =
            sqrt(weymouth_ct) * (
                (p_in/(sqrt(p_in^2 - p_out^2))) * link_p_in -
                (p_out/(sqrt(p_in^2 - p_out^2))) * link_p_out
            )
        push!(RHS_values, val_rhs)
    end
    return RHS_values
end
