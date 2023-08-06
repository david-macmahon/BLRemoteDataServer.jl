@swagger """
/version:
  get:
    description: Returns the version of the BLRemoteDataServer.
    responses:
      "200":
        description: OK
"""
route(handle_version, "/version")

@swagger """
/prefixes:
  get:
    description: Returns the list of directories being served.
    responses:
      "200":
        description: OK
"""
route(handle_prefixes, "/prefixes")

@swagger """
/readdir:
  get:
    description: "Read the names if files/directories in a directory."
    parameters:
      - name: dir
        in: query
        required: true
        description: "Specifies directory to read."
        schema:
          type: string
      - name: regex
        in: query
        required: false
        description: "Only names matching `regex` will be returned.  The default is to match all names."
        schema:
          type: string
      - name: join
        in: query
        required: false
        description: "Returns full path names when `join` is `true` (the default)."
        schema:
          type: boolean
    responses:
      "200":
        description: OK
"""
route(handle_readdir, "/readdir")

@swagger """
/finddirs:
  get:
    description: "Find directories in/under the given directory `dir`."
    parameters:
      - name: dir
        in: query
        required: true
        description: "Specifies directory to search in/under."
        schema:
          type: string
      - name: regex
        in: query
        required: false
        description: "Only directories matching `regex` will be returned.  The default is to match all names."
        schema:
          type: string
      - name: join
        in: query
        required: false
        description: "Returns full path names when `join` is `true` (the default)."
        schema:
          type: boolean
    responses:
      "200":
        description: OK
"""
route(handle_finddirs, "/finddirs")

@swagger """
/findfiles:
  get:
    description: "Find files in/under the given directory `dir`."
    parameters:
      - name: dir
        in: query
        required: true
        description: "Specifies directory to search in/under."
        schema:
          type: string
      - name: regex
        in: query
        required: false
        description: "Only files matching `regex` will be returned.  The default is to match all names."
        schema:
          type: string
      - name: join
        in: query
        required: false
        description: "Returns full path names when `join` is `true` (the default)."
        schema:
          type: boolean
    responses:
      "200":
        description: OK
      "500":
        description: Internal server error
"""
route(handle_findfiles, "/findfiles")

@swagger """
/fbfiles:
  get:
    description: >
      Find *Filterbank* files in/under the given directory `dir` and return
      JSON dictionary of their headers with added `hostname` and `filename`
      fields.
    parameters:
      - name: dir
        in: query
        required: true
        description: "Specifies directory to search in/under."
        schema:
          type: string
      - name: regex
        in: query
        required: false
        description: >
          Only files matching `regex` will be returned.  The default is to match
          all files ending in `.fil` or `*.h5` (i.e.
          `regex="\\\\.(fil|h5)\\\$"`).
        schema:
          type: string
    responses:
      "200":
        description: OK
      "500":
        description: Internal server error
"""
route(handle_fbfiles, "/fbfiles")

@swagger """
/fbdata:
  get:
    description: >
      Return data from specified *Filterbank* file.
    parameters:
      - name: file
        in: query
        required: true
        description: Specifies the filterbank file to read.
        schema:
          type: string
      - name: chans
        in: query
        required: false
        description: >
          The channel(s) to read (1-based).  Either an integer, a range or a
          colon (`:`) which means all channels.  Defaults to `:`.
        schema:
          type: integer
      - name: fqav
        in: query
        required: false
        description: >
          Specifies the number of adjacent frequency channels to average
          together.  Defaults to 1 (i.e. no frequency averaging).
        schema:
          type: integer
      - name: ifs
        in: query
        required: false
        description: >
          The IF(s) to read (1-based).  Either an integer, a range or a
          colon (`:`) which means all IFs.  Defaults to `:`.
        schema:
          type: integer
      - name: times
        in: query
        required: false
        description: >
          The time sample(s) to read (1-based).  Either an integer, a range or a
          colon (`:`) which means all time samples.  Defaults to `:`.
        schema:
          type: integer
      - name: tmav
        in: query
        required: false
        description: >
          Specifies the number of adjacent time samples to average
          together.  Defaults to 1 (i.e. no time averaging).
        schema:
          type: integer
    responses:
      "200":
        description: OK
      "500":
        description: Internal server error
"""
route(handle_fbdata, "/fbdata")

build_swagger()

#add route without default layout
route("/", swagui)