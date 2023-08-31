# BLRemoteDataServer

The *Breakthrough Listen Remote Data Server* provides a convenient RESTful web
based interface to Breakthrough Listen data stored on the host on which the
server runs.  A companion project, [BLRemoteDataClient.jl](
https://github.com/david-macmahon/BLRemoteDataClient.jl) provides a Julia
package that contains functions that access the RESTful API in a very
streamlined way.  Although the server and the Julia client are written in Julia,
clients can be written in any language that can issue HTTP requests and parse
JSON responses.

## Installation

In the Julia REPL, run:

```julia
import Pkg
Pkg.add("https://github.com/david-macmahon/BLRemoteDataServer.jl")
```

## Starting the server

The server only serves data from directories in/under a list of base directories
specified at startup.  Here is a command line to start the BLRemoteDataServer in
a new Julia process to serve data from `/datax`, `/datax2`, and `/datax3` over
all network interfaces:

```sh
julia --project=/path/to/BLRemoteDataServer \
    -e 'using BLRemoteDataServer' \
    -e 'BLRemoteDataServer.up(ARGS, host="0.0.0.0")' \
    -- /datax /datax2 /datax3 &
```

Using `host="0.0.0.0"` will cause BLRemoteDataServer to listen on all
interfaces.  To listen on just the "primary" interface, use
`host=getaddrinfo(gethostname())` (which will also require `using Sockets`).  If
no `host` keyword argument is passed, the server will bind to `127.0.0.1` (i.e.
`localhost`).

The server listens on port 8000 by default.  If you want to use a different port
number, pass it as the value of the `port` keyword argument (e.g. `port=12345`).

## Using the server

The server self-hosts documentation for the RESTful API and provides a web
interface for invoking requests to the supported API endpoints.  To access the
documentation and the web interface, point your browser to `http://host:port/`.

The BLRemoteDataClient package provides more streamlined access from Julia.  See
the documentation for that package for details on its usage.

## Stopping the server

To stop the server, send the server process a `SIGINT` signal.  This will
terminate more cleanly than using `SIGTERM`.  If you want/need to get drastic,
you can use `SIGKILL`.
