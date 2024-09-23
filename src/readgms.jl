function readGamsFile(infile)
    @assert isfile(infile)

    count = 1

    inside = false
    intable = false
    tablerow = 0
    params = Dict()
    thisparam = Dict()
    pname = ""
    idxs = []

    for line in eachline(infile)

        # Strip comments at end of line
        if occursin(r"#", line)
            line = split(line, "#")[1]
        end

        if occursin(r"^#", line) # skip comments

        elseif inside && occursin(r"/\s*;", line) #toggle
            inside = false
            vs = split(split(line, '/')[1])

            if length(vs) >= 2
                (k, v) = translateStrings(vs)
                thisparam[k] = v
            end

            params[pname] = thisparam # store current params dictionary
            thisparam = Dict() # new dictionary for next parameter
        elseif inside
            vs = split(line)
            if length(vs) >= 2
                (k, v) = translateStrings(vs)
                thisparam[k] = v
            end

        elseif occursin(r"^parameter", line) # toggle
            inside = true
            pname = replace(split(line)[2], "/" => "")
            vs = split(split(line, '/')[2])
            if length(vs) >= 2
                (k, v) = translateStrings(vs)
                thisparam[k] = v
            end
        elseif occursin(r"^table", line)
            intable = true
            tablerow = 0
            pname = split(line)[2]
        elseif intable
            mline = line
            if tablerow == 0
                idxs = parse.(Int, split(mline))
            end

            if occursin(r";", line)
                mline = replace(line, ";" => "")
            end

            vs = split(mline)
            idx = parse(Int, vs[1])
            vals = parse.(Float64, vs[2:end])
            if tablerow > 0
                for (i, id) in enumerate(idxs)
                    thisparam[(idx, id)] = vals[i]
                end
            end

            if occursin(r";", line)
                intable = false
                params[pname] = thisparam # store current params dictionary
                thisparam = Dict() # new dictionary for next parameter
            end

            tablerow = tablerow + 1
        end
    end
    return params
end

function parsenum(n)
    nn = 0
    try
        nn = parse(Int, n)
    catch err
        nn = parse(Float64, n)
    end
    return nn
end

function parseindex(n)
    return parse(Int, n[2:end])
end

function translateStrings(vs)
    @assert length(vs) >= 2
    # First value always integer
    fv = parse(Int, vs[1])

    mv = [parseindex(n) for n in vs[2:(end - 1)]]
    pushfirst!(mv, fv)
    # Last value usually float
    lv = parsenum(vs[end])

    return (tuple(mv...), lv)
end

function sources(sg)
    ss = Int[]
    for v in vertices(sg)
        if length(inneighbors(sg, v)) == 0
            push!(ss, v)
        end
    end
    return ss
end

function sinks(sg)
    ss = Int[]
    for v in vertices(sg)
        if length(outneighbors(sg, v)) == 0
            push!(ss, v)
        end
    end
    return ss
end

function createGraph(dict)
    g = SimpleDiGraph(maximum(maximum((collect(k) for k in keys(dict)))))

    for k in keys(dict)
        if dict[k] > 0
            add_edge!(g, k...)
        end
    end
    return g
end

# TODO: Set metadata (file/case name etc?, optimal solution?)
function addMeta(g::SimpleDiGraph, dict)
    mg = MetaDiGraph(g)

    # capacity, ub
    ubdict = dict["bu(i)"]
    for k in keys(ubdict)
        set_prop!(mg, k..., :ub, ubdict[k])
    end
    # capacity, lb
    lbdict = dict["bl(i)"]
    for k in keys(lbdict)
        set_prop!(mg, k..., :lb, lbdict[k])
    end

    # cost
    costdict = dict["c(i,j)"]
    for k in keys(costdict)
        set_prop!(mg, k..., :cost, costdict[k])
    end

    # Source qualities/terminal quality upper bounds
    qdict = dict["q(i,k)"]
    q = Dict()
    for k in keys(qdict)
        (i, j) = k
        if !haskey(q, i)
            q[i] = Dict()
        end
        q[i][j] = qdict[k]
    end

    for k in keys(q)
        set_prop!(mg, k, :q, q[k])
    end

    # TODO: Other sink quality constraints

    return mg
end
function getk(mg)
    retk = []
    for v in vertices(mg)
        if has_prop(mg, v, :q)
            push!(retk, Int.(collect(keys(get_prop(mg, v, :q)))))
        end
    end
    return sort(unique(Iterators.flatten(retk))) #retk array of arrays, need to be flattened
end

function getc(mg)
    c = zeros(size(adjacency_matrix(mg)))
    for e in edges(mg)
        if has_prop(mg, src(e), dst(e), :cost)
            c[src(e), dst(e)] = get_prop(mg, src(e), dst(e), :cost)
        else
            c[src(e), dst(e)] = 0.0
        end
    end
    return c
end

function getub(mg; bound=:ub)
    ub = zeros(size(vertices(mg)))
    for i in vertices(mg)
        if has_prop(mg, i, bound)
            ub[i] = get_prop(mg, i, bound)
        end
    end
    return ub
end

function getlb(mg)
    return getub(mg; bound=:lb)
end

function getq(mg)
    q = zeros(length(vertices(mg)), length(getk(mg)))
    for i in vertices(mg), k in getk(mg)
        if has_prop(mg, i, :q)
            prop = get_prop(mg, i, :q)
            if haskey(prop, k)
                q[i, k] = prop[k]
            end
        end
    end
    return q
end

function populateProblemStruct(mg)
    # Network
    I = vertices(mg)    # Nodes
    S = sources(mg)     # Production/sources
    T = sinks(mg)       # Terminals/sinks
    K = getk(mg)        # Qualities
    L = setdiff(I, S, T)  # Pools

    # Data
    a = adjacency_matrix(mg)
    c = getc(mg) # Cost matrix
    ub = getub(mg)
    lb = getlb(mg)
    q = getq(mg)

    return data = [mg, I, S, T, K, L, a, c, ub, lb, q]
end

function loadGamsFile(infile)
    gams = readGamsFile(infile)
    g = createGraph(gams["a(i,j)"])
    mg = addMeta(g, gams)
    return populateProblemStruct(mg)
end


