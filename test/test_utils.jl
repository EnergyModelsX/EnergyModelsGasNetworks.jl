
function df_variable(m, element::Symbol)
    val = Containers.rowtable(value, m[element])

    return DataFrame(val)
end

function calculate_linearise_pressures()
    P_min = 30.0  # example minimum pressure
    P_max = 70.0  # example maximum pressure
    n = 5         # number of points

    pressures = range(P_min, P_max, length = n)
    pairs = [(p1, p2) for p1 in pressures, p2 in pressures if p1 > p2]

    return pairs
end
