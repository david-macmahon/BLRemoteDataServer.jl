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

    mapreduce(vcat, walkdir(dirname); init=[]) do (dir, subdirs, _)
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

    mapreduce(vcat, walkdir(dirname); init=[]) do (dir, _, files)
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

    mapreduce(vcat, walkdir(dirname); init=[]) do (dir, _, files)
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
    data = copy(isempty(idxs) ? fbd : @view fbd[idxs...])
    finalize(fbd) # force un-mmap
    data
end

function get_data(fname, idxs)
    HDF5.ishdf5(fname) ? get_h5data(fname, idxs) : get_fbdata(fname, idxs)
end

function parse_int_range(s::AbstractString, av::Integer=1)
    s == ":" && return Colon()
    s == "Colon()" && return Colon()

    # Ignore invalid averaging
    (av < 1) && (av = 1)

    parts = parse.(Int, split(s, ":"))
    if length(parts) == 1
        start = parts[1]
        step = 1
        len = 1
    elseif length(parts) == 2
        start = parts[1]
        step = 1
        len = parts[2] - parts[1] + 1
        len = av * fld(len, av)
    elseif length(parts) == 3
        start = parts[1]
        step = parts[2]
        len = fld(parts[3] - start + 1, step)
        len = av * fld(len, av)
    else
        error500("invalid range syntax ($s)")
    end
    if start < 1 || step < 1 || len < 1
        error500("invalid range ($s with averaging by $av)")
    end

    range(start; step, length=len)
end

function handle_fbdata()
    fname = query(:file, nothing)
    fname === nothing && error500("required parameter (file) is missing")
    validate_file(fname)

    fqav  = query(:fqav,  "1") |> s->something(tryparse(Int, s), 1)
    tmav  = query(:tmav,  "1") |> s->something(tryparse(Int, s), 1)
    (fqav < 1) && (fqav = 1)
    (tmav < 1) && (tmav = 1)

    chans = query(:chans, ":") |> s->parse_int_range(s, fqav)
    ifs   = query(:ifs,   ":") |>    parse_int_range
    times = query(:times, ":") |> s->parse_int_range(s, tmav)

    idxs = all(==(Colon()), (chans, ifs, times)) ?  () : (chans, ifs, times)
    data = get_data(fname, idxs)

    nc, ni, nt = size(data)
    data = mean(reshape(data, fqav, nc÷fqav, ni, tmav, nt÷tmav), dims=(1,4))
    data = dropdims(data, dims=(1,4))

    hdrs = Dict(
        "content-type" => "application/octet-stream",
        "X-dims" => join(size(data), ",")
    )

    HTTP.Messages.Response(200, hdrs, data)
end

### CapnProto Hits files

function handle_hitsfiles()
    dirname = query(:dir, nothing)
    dirname === nothing && error500("required parameter (dir) is missing")
    validate_dir(dirname)
    pattern = Regex(query(:regex, "\\.hits\$"))
    withdata = query(:withdata, "false") == "true"
    hostname = gethostname()

    mapreduce(vcat, walkdir(dirname); init=[]) do (dir, _, files)
        matches = filter(s->occursin(pattern, s), files)
        mapreduce(vcat, matches; init=[]) do f
            p = joinpath(dir, f)
            meta, data = load_hits(p)
            if withdata
                for (m,d) in zip(meta, data)
                    m[:data] = base64encode(d)
                end
            end
            setindex!.(meta, hostname, :hostname)
            setindex!.(meta, p, :filename)
        end
    end |> json
end

function handle_hitdata()
    fname = query(:file, nothing)
    fname === nothing && error500("required parameter (file) is missing")
    validate_file(fname)

    s = query(:offset, nothing)
    s === nothing && error500("required parameter (offset) is missing")
    offset = tryparse(Int, s)
    offset === nothing && error500("could not parse offset '$(s)' as integer")

    _, data = load_hit(fname, offset)

    hdrs = Dict(
        "content-type" => "application/octet-stream",
        "X-dims" => join(size(data), ",")
    )

    HTTP.Messages.Response(200, hdrs, data)
end

### CapnProto Stamps files

function handle_stampsfiles()
    dirname = query(:dir, nothing)
    dirname === nothing && error500("required parameter (dir) is missing")
    validate_dir(dirname)
    pattern = Regex(query(:regex, "\\.stamps\$"))
    hostname = gethostname()

    mapreduce(vcat, walkdir(dirname); init=[]) do (dir, _, files)
        matches = filter(s->occursin(pattern, s), files)
        mapreduce(vcat, matches; init=[]) do f
            p = joinpath(dir, f)
            meta, _ = load_stamps(p)
            setindex!.(meta, hostname, :hostname)
            setindex!.(meta, p, :filename)
        end
    end |> json
end

function handle_stampdata()
    fname = query(:file, nothing)
    fname === nothing && error500("required parameter (file) is missing")
    validate_file(fname)

    s = query(:offset, nothing)
    s === nothing && error500("required parameter (offset) is missing")
    offset = tryparse(Int, s)
    offset === nothing && error500("could not parse offset '$(s)' as integer")

    _, data = load_stamp(fname, offset)

    hdrs = Dict(
        "content-type" => "application/octet-stream",
        "X-dims" => join(size(data), ",")
    )

    HTTP.Messages.Response(200, hdrs, data)
end
