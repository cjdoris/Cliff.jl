# Cliff.jl

Cliff is a lightweight, type-stable argument parsing library for Julia. It provides three building blocks:

- `Argument` – defines positional arguments, short options, long options, and flags.
- `Command` – describes a sub-command with its own arguments and nested sub-commands.
- `Parser` – top-level parser that aggregates arguments and commands.

Parsing command line arguments returns a `Parsed` object—typically stored in a variable named `args`—that exposes convenient indexing for retrieving values as strings or strongly typed data.

## Features

- Positional arguments, options, and boolean flags.
- Nested sub-commands with disambiguation of arguments by command depth.
- Explicit handling of `--` to stop option parsing while still allowing sub-command detection.
- Repeatable positional arguments, options, and flags with configurable occurrence ranges.
- Retrieval helpers such as `args["name"]`, `args["name", depth]`, `args["name", Type]`, and `args["name", Vector{T}]` (or the shorthand `args["name", Type, +]`).
- No implicit `--help` handling and no automatic usage string generation.

## Typed Retrieval

Values are stored as strings but can be converted when accessed from a `Parsed` object:

- `args["name"]` or `args["name", String]` returns the raw string value.
- `args["name", Bool]` recognises `true`, `false`, `1`, `0`, `yes`, `no`, `on`, and `off` (case insensitive).
- `args["name", T]` uses `Base.parse(T, value)` for any type `T` with a parsing method, such as `Int`, `Float64`, or `UInt`.
- `args["name", Vector{T}]` (or the shorthand `args["name", T, +]`) converts each provided value for repeatable arguments or flags.

This allows you to keep your parser definitions declarative while still retrieving strongly typed values at the call site.

## Quick Start

```julia
using Cliff

parser = Parser(
    arguments = [
        Argument("input"; required = true),
        Argument(["--count", "-c"]; default = "1"),
        Argument("--verbose"; flag = true)
    ],
    commands = [
        Command("run";
            arguments = [Argument("task"; required = true)],
            commands = [
                Command("fast";
                    arguments = [Argument("--threads"; default = "4")]
                )
            ]
        )
    ]
)

args = parser(["run", "fast", "--threads", "8", "task-name"])

println(args.command)             # ["run", "fast"]
println(args["task"])            # "task-name"
println(args["--threads", Int])  # 8
println(args["--verbose", Bool]) # false

# Collect repeated values
println(args["--threads", Vector{String}])  # ["8"]
```

## Development

1. Install Julia 1.9 or newer.
2. Activate the project and instantiate dependencies:

   ```julia
   import Pkg
   Pkg.activate(".")
   Pkg.instantiate()
   Pkg.precompile(strict=true, timing=true)
   ```

3. Run the test suite:

   ```julia
   julia --project -e 'using Pkg; Pkg.test()'
   ```

## Status

Cliff intentionally focuses on the core parsing features above. Suggestions for additional capabilities are welcome as follow-up work.
