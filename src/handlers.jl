function handle_version()
    json(VERSION)
end

function handle_prefixes()
    json(PREFIXES)
end

function error500(message)
    throw(Genie.Exceptions.InternalServerException(message))
end

function validate_path(path, must_exist=true)
    if !any(p->startswith(path, p), PREFIXES)
        error500("$path does not start with supported prefix")
    end
    if must_exist && !ispath(path)
        throw(Genie.Exceptions.NotFoundException(path))
    end
end

function validate_dir(dir, must_exist=true)
    validate_path(dir, must_exist)
    if must_exist && !isdir(dir)
        error500("$dir is not a dir")
    end
end

function validate_file(fname, must_exist=true)
    validate_path(fname, must_exist)
    if must_exist && !isfile(fname)
        error500("$fname is not a file")
    end
end

function handle_readdir()
    dirname = query(:dir, nothing)
    dirname === nothing && error500("required parameter (dir) is missing")
    validate_dir(dirname)
    pattern = Regex(query(:regex, "."))
    dojoin = query(:join, "true") == "true"

    names = filter(s->occursin(pattern, s), readdir(dirname))
    (dojoin ? joinpath.(dirname, names) : names) |> json
end

function handle_finddirs()
    dirname = query(:dir, nothing)
    dirname === nothing && error500("required parameter (dir) is missing")
    validate_dir(dirname)
    pattern = Regex(query(:regex, "."))
    dojoin = query(:join, "true") == "true"

    mapreduce(vcat, walkdir(dirname)) do (dir, subdirs, _)
        matches = filter(s->occursin(pattern, s), subdirs)
        dojoin ? joinpath.(dir, matches) : matches
    end |> json
end

function handle_findfiles()
    dirname = query(:dir, nothing)
    dirname === nothing && error500("required parameter (dir) is missing")
    validate_dir(dirname)
    pattern = Regex(query(:regex, "."))
    dojoin = query(:join, "true") == "true"

    mapreduce(vcat, walkdir(dirname)) do (dir, _, files)
        matches = filter(s->occursin(pattern, s), files)
        dojoin ? joinpath.(dir, matches) : matches
    end |> json
end

### Filterbank/HDF5 headers

function get_h5header(fname)
    try
        h5open(fname) do h5
            data = h5["data"]
            attrs = attributes(data)
            pairs = [Symbol(k) => attrs[k][] for k in keys(attrs) if k != "DIMENSION_LABELS"]
            elsize = sizeof(eltype(data))
            if !haskey(attrs, "nfpc")
                # Compute nfpc for Green Bank files as Int32 to match FBH5's nfpc type
                push!(pairs, round(Int32, 187.5/64/abs(attrs["foff"][])))
            end
            push!(pairs, :data_size => elsize * prod(size(data)))
            push!(pairs, :nsamps => size(data, ndims(data)))
            sort(pairs, by=first)
            push!(pairs, :hostname => gethostname())
            push!(pairs, :filename => abspath(fname))
            NamedTuple(pairs)
        end
    catch
        (; hostname=gethostname(), filename=abspath(fname))
    end
end

function get_fbheader(fbname)
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
        NamedTuple(fbh)
    catch
        (; hostname=gethostname(), filename=abspath(fbname))
    end
end

function get_header(fname)
    HDF5.ishdf5(fname) ? get_h5header(fname) : get_fbheader(fname)
end

function handle_fbfiles()
    dirname = query(:dir, nothing)
    dirname === nothing && error500("required parameter (dir) is missing")
    validate_dir(dirname)
    pattern = Regex(query(:regex, "\\.(fil|h5)\$"))

    mapreduce(vcat, walkdir(dirname)) do (dir, _, files)
        matches = filter(s->occursin(pattern, s), files)
        get_header.(joinpath.(dir, matches))
    end |> json
end

### Filterbank/HDF5 data

function get_h5data(fname, idxs)
    h5open(h5->h5["data"][idxs...], fname)
end

function get_fbdata(fname, idxs)
    _, fbd = Filterbank.mmap(fname)
    data = copy(fbd[idxs...])
    finalize(fbd) # force un-mmap
    data
end

function get_data(fname, idxs)
    HDF5.ishdf5(fname) ? get_h5data(fname, idxs) : get_fbdata(fname, idxs)
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
        error500("invalid range syntax ($s)")
    end
end

function handle_fbdata()
    fname = query(:file, nothing)
    fname === nothing && error500("required parameter (file) is missing")
    validate_file(fname)
    chans = query(:chans, ":") |> parse_int_range
    ifs   = query(:ifs,   ":") |> parse_int_range
    times = query(:times, ":") |> parse_int_range

    idxs = all(==(Colon()), (chans, ifs, times)) ?  () : (chans, ifs, times)
    data = get_data(fname, idxs)

    hdrs = Dict(
        "content-type" => "application/octet-stream",
        "X-dims" => join(size(data), ",")
    )

    p = Ptr{UInt8}(pointer(data))
    GC.@preserve data HTTP.Messages.Response(200, hdrs, unsafe_wrap(Array, p, (sizeof(data),)))
end
