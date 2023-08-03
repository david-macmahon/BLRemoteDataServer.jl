module BLRemoteDataServer

using Genie, Genie.Router
using SwagUI, SwaggerMarkdown
using Genie.Renderers.Json
using HTTP

using Blio
using HDF5, H5Zbitshuffle

const PREFIXES = String[]

const OPENAPI = OpenAPI("3.0", Dict{String,Any}(
    "title"   => "Breakthrough Listen Remote Data Server",
    "version" => "0.0.0"
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
    include(joinpath(@__DIR__, "routes.jl"))
end

function up(prefixes::AbstractVector{<:AbstractString};
            host="127.0.0.1", port=8000, async=false, kwargs...)
    empty!(PREFIXES)
    append!(PREFIXES, prefixes)
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
