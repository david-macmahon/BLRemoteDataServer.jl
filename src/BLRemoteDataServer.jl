module BLRemoteDataServer

using Genie, Genie.Router
using SwagUI, SwaggerMarkdown
using Genie.Renderers.Json
using HTTP

using Blio
using HDF5, H5Zbitshuffle

include("version.jl")

const PREFIXES = String[]

const OPENAPI = OpenAPI("3.0", Dict{String,Any}(
    "title"   => "Breakthrough Listen Remote Data Server",
    "version" => string(VERSION)
))

const SWAGGER_DOCUMENT = Ref{Dict{String,Any}}()

function build_swagger()
    SWAGGER_DOCUMENT[] = build(OPENAPI)
end

function swagui()
    render_swagger(SWAGGER_DOCUMENT[])
end

include("handlers.jl")

function __init__()
    # It seems like routes need to be added at runtime
    include(joinpath(@__DIR__, "routes.jl"))
end

function up(prefixes::AbstractVector{<:AbstractString};
            host="127.0.0.1", port=8000, async=false, kwargs...)
    @assert !isempty(prefixes)
    empty!(PREFIXES)
    append!(PREFIXES, prefixes)
    @info "BLRemoteDataServer v$(VERSION) starting to serve data from: $(PREFIXES)"
    sc = Genie.up(port, string(host); async=true, kwargs...)
    while !async
        try
            sleep(1)
        catch ex
            down(sc)
            break
        end
    end
end

end # module RemoteDataService
