function handle_prefixes()
    json(PREFIXES)
end

function validate_path(path)
    if !any(p->startswith(path, p), PREFIXES)
        error("$path does not start with supported prefix")
    end
end

function handle_readdir()
    dirname = query(:dir, nothing)
    dirname === nothing && error("required parameter (dir) is missing")
    validate_path(dirname)
    pattern = Regex(query(:regex, "."))
    dojoin = query(:join, "true") == "true"

    names = filter(s->occursin(pattern, s), readdir(dirname))
    (dojoin ? joinpath.(dirname, names) : names) |> json
end

function handle_finddirs()
    dirname = query(:dir, nothing)
    dirname === nothing && error("required parameter (dir) is missing")
    validate_path(dirname)
    pattern = Regex(query(:regex, "."))
    dojoin = query(:join, "true") == "true"

    mapreduce(vcat, walkdir(dirname)) do (dir, subdirs, _)
        matches = filter(s->occursin(pattern, s), subdirs)
        dojoin ? joinpath.(dir, matches) : matches
    end |> json
end

function handle_findfiles()
    dirname = query(:dir, nothing)
    dirname === nothing && error("required parameter (dir) is missing")
    validate_path(dirname)
    pattern = Regex(query(:regex, "."))
    dojoin = query(:join, "true") == "true"

    mapreduce(vcat, walkdir(dirname)) do (dir, _, files)
        matches = filter(s->occursin(pattern, s), files)
        dojoin ? joinpath.(dir, matches) : matches
    end |> json
end

### FBH5 files

function getfbh5header(fbh5name)
    try
        h5open(fbh5name) do h5
            data = h5["data"]
            attrs = attributes(data)
            pairs = [Symbol(k) => attrs[k][] for k in keys(attrs) if k != "DIMENSION_LABELS"]
            elsize = sizeof(eltype(data))
            if !haskey(attrs, "nfpc")
                # Compute nfpc for Green Bank files as Int32 to match FBH5's nfpc type
                push!(pairs, round(Int32, 187.5/64/abs(fbh[:foff])))
            end
            push!(pairs, :data_size => elsize * prod(size(data)))
            push!(pairs, :nsamps => size(data, ndims(data)))
            sort(pairs, by=first)
            push!(pairs, :hostname => gethostname())
            push!(pairs, :filename => abspath(fbh5name))
            NamedTuple(pairs)
        end
    catch
        (; hostname=gethostname(), filename=abspath(fhh5name))
    end
end

function handle_fbh5files()
    dirname = query(:dir, nothing)
    dirname === nothing && error("required parameter (dir) is missing")
    validate_path(dirname)
    pattern = Regex(query(:regex, "\\.h5\$"))

    mapreduce(vcat, walkdir(dirname)) do (dir, _, files)
        matches = filter(s->occursin(pattern, s), files)
        getfbh5header.(joinpath.(dir, matches))
    end |> json
end

function parse_int_range(s::AbstractString)
    s == ":" && return Colon()
    s == "Colon()" && return Colon()

    parts = parse.(Int, split(s, ":"))
    if length(parts) == 1
        return parts[1]:parts[1]
    elseif length(parts) == 2
        return parts[1]:parts[2]
    elseif length(parts) == 3
        return parts[1]:parts[2]:parts[3]
    else
        error("invalid range syntax ($s)")
    end
end

function handle_fbh5data()
    h5name = query(:file, nothing)
    h5name === nothing && error("required parameter (file) is missing")
    validate_path(h5name)
    chans = query(:chans, ":") |> parse_int_range
    ifs   = query(:ifs,   ":") |> parse_int_range
    times = query(:times, ":") |> parse_int_range

    idxs = (chans, ifs, times)
    if all(==(Colon()), idxs)
        idxs=()
    end

    data = h5open(h5name) do h5
        h5["data"][idxs...]
    end

    p = Ptr{UInt8}(pointer(data))
    hdrs = Dict(
        "content-type" => "application/octet-stream",
        "X-dims" => join(size(data), ",")
    )
    GC.@preserve data HTTP.Messages.Response(200, hdrs, unsafe_wrap(Array, p, (sizeof(data),)))
end

### Filterbank files

function getfbheader(fbname)
    try
        fbh = open(io->read(io, Filterbank.Header), fbname)
        # Compute nfpc for Green Bank files as Int32 to match FBH5's nfpc type
        fbh[:nfpc] = round(Int32, 187.5/64/abs(fbh[:foff]))
        # Delete redundant fields to match FBH5 headers
        delete!(fbh, :header_size)
        delete!(fbh, :sample_size)
        # Add hostname and filename fields
        fbh[:hostname] = gethostname()
        fbh[:filename] = abspath(fbname)
        fbh
    catch
        (; hostname=gethostname(), filename=abspath(fbname))
    end
end

function handle_fbfiles()
    dirname = query(:dir, nothing)
    dirname === nothing && error("required parameter (dir) is missing")
    validate_path(dirname)
    pattern = Regex(query(:regex, "\\.fil\$"))

    mapreduce(vcat, walkdir(dirname)) do (dir, _, files)
        matches = filter(s->occursin(pattern, s), files)
        getfbheader.(joinpath.(dir, matches))
    end |> json
end

function handle_fbdata()
    fbname = query(:file, nothing)
    fbname === nothing && error("required parameter (file) is missing")
    validate_path(fbname)
    chans = query(:chans, ":") |> parse_int_range
    ifs   = query(:ifs,   ":") |> parse_int_range
    times = query(:times, ":") |> parse_int_range

    idxs = (chans, ifs, times)
    if all(==(Colon()), idxs)
        idxs=()
    end

    _, fbd = Filterbank.mmap(fbname)
    data = copy(fbd[idxs...])
    finalize(fbd)

    p = Ptr{UInt8}(pointer(data))
    hdrs = Dict(
        "content-type" => "application/octet-stream",
        "X-dims" => join(size(data), ",")
    )
    GC.@preserve data HTTP.Messages.Response(200, hdrs, unsafe_wrap(Array, p, (sizeof(data),)))
end
