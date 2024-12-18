function optimize(case, modeltype)
    m = EMP.create_model(case, modeltype)
    optimizer = Xpress.Optimizer
    set_optimizer(m, optimizer)
    set_optimizer_attribute(m, MOI.Silent(), true)
    optimize!(m)
    return m
end

function df_variable(m, element::Symbol)
    val = Containers.rowtable(value, m[element])

    return DataFrame(val)
end