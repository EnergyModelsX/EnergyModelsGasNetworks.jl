"""
    run_model(case::Dict, model::EnergyModel, optimizer)

Take the `case` data as a dictionary and the `model` and build and optimize the model.
Returns the solved JuMP model.

The dictionary requires the keys:
 - `:nodes::Vector{Node}`
 - `:links::Vector{Link}`
 - `:products::Vector{Resource}`
 - `:T::TimeStructure`
"""
function run_model(case::Dict, model, optimizer; check_timeprofiles = true)
    @debug "Run model" optimizer

    m = create_model(case, model; check_timeprofiles)

    if !isnothing(optimizer)
        set_optimizer(m, optimizer)
        set_optimizer_attribute(m, MOI.Silent(), true)
        optimize!(m)
        # TODO: print_solution(m) optionally show results summary (perhaps using upcoming JuMP function)
        # TODO: save_solution(m) save results
    else
        @warn "No optimizer given"
    end
    return m
end

function write_constraints_to_file(model::Model, filename::String)
    open(filename, "w") do file
        for T ∈ JuMP.list_of_constraint_types(model)
            cs = all_constraints(model, T...)
            println(file, T)
            println(file, "\n", cs)
        end
    end
end

function create_locatedsink(file_path, locations, resource)
    # Get id and cap
    # Get all sheets in excel
    load_path = joinpath(file_path, "99_aircraftloads.xlsx")
    load_xlsx = XLSX.openxlsx(load_path)
    sheet_names = XLSX.sheetnames(load_xlsx)

    # Intialise vector and dictionary
    ids = []
    cap = Dict()

    # Loop through sheets and populate id list and cap dictionary
    for (i, sheet_name) ∈ enumerate(sheet_names[2:end])   #avoid time
        sheet = load_xlsx[sheet_name]
        header = sheet[1, :]
        unique!(append!(ids, vec(header)[2:end]))   #avoid time

        for (j, head) ∈ enumerate(header[2:end]) #avoid time
            col = sheet[:, j+1]     #avoid time
            col_val = col[2:end]
            if !haskey(cap, head)
                # If flight was not added in previous periods, generate empty demands of those missing periods
                zero_vectors = [zeros(length(col_val)) for _ ∈ 1:(i-1)]
                cap[head] = zero_vectors

                # Add current demand
                push!(cap[head], col_val)
            else
                # Add current demand
                push!(cap[head], col_val)
            end
        end
    end

    # Get location
    # Get path and initiliase location dictionary
    node_path = joinpath(file_path, "1_Aircraft.xlsx")
    location = Dict{String,Location}()

    # Loop through the sheet "Nodes" to get the id and corresponding gate
    XLSX.openxlsx(node_path, enable_cache = false) do f
        sheet = f["Nodes"]
        for r ∈ XLSX.eachrow(sheet)
            if XLSX.row_number(r) in [1, 2]
                continue
            else
                id = r[1]
                v1 = r[2]
                # Filter the struct "Location" in locations with same id as the assigned gate
                location[id] = first(filter(x -> get_location(x, v1), locations))
            end
        end
    end

    # Populate structs

    sinks = []
    for id ∈ ids
        sink = LocatedSink(
            id,
            StrategicProfile([OperationalProfile(cap[id][k]) for k ∈ 1:length(cap[id])]),
            Dict(:surplus => FixedProfile(0), :deficit => FixedProfile(1e12)),
            Dict(resource => 1),
            location[id],
        )

        append!(sinks, [sink])
    end

    return sinks
end

"""
Returns a `DataFrame` with the values of the variables from the JuMP container `var`.
The column names of the `DataFrame` can be specified for the indexing columns in `dim_names`
"""
function convert_container_to_df(
    m,
    var_name::Symbol;
    col_names::Vector{Symbol} = Vector{Symbol}(),
    save_to_excel = false,
    file_name::String = "",
)
    var = m[var_name]

    # Convert variable in dataframe
    table = Containers.rowtable(var)
    df = DataFrames.DataFrame(table)

    # Get the values of the variables
    transform!(df, :y => ByRow(value) => :value)

    # Delete unnecessary columns
    select!(df, Not(:y))

    # Change name of columns
    if length(col_names) != 0
        old_names = names(df)[1:length(col_names)]
        rename!(df, Pair.(old_names, col_names))
    end

    if save_to_excel
        df_ = df_structs_to_strings!(df)
        save_df_to_excel(file_name, df_, string(var_name))
    end

    return df
end

function show_variable(m, element::Symbol)
    val = Containers.rowtable(value, m[element])

    return PrettyTables.pretty_table(val)
end

function df_variable(m, element::Symbol)
    val = Containers.rowtable(value, m[element])

    return DataFrame(val)
end

function save_df_to_excel(file_name::String, df::DataFrame, sheet_name)
    if isfile(file_name)
        XLSX.openxlsx(file_name, mode = "rw") do xf
            sheet = XLSX.addsheet!(xf, sheet_name)
            XLSX.writetable!(sheet, df)
        end
    else
        # If the file does not exist, create it and add the first sheet
        XLSX.openxlsx(file_name, mode = "w") do xf
            sheet = xf[1]
            XLSX.rename!(sheet, sheet_name)
            XLSX.writetable!(sheet, df)
        end
    end
end

function df_structs_to_strings!(df::DataFrame)
    for col ∈ names(df)
        if !(eltype(df[!, col]) in [Int, Float64, String, Bool])
            df[!, col] = string.(df[!, col])
        end
    end
    return df
end

# Function to write all constraints to a file
function write_constraints_to_file(model::Model, filename::String)
    open(filename, "w") do file
        for T ∈ JuMP.list_of_constraint_types(model)
            cs = all_constraints(model, T...)
            println(file, T)
            println(file, "\n", cs)
        end
    end
end
