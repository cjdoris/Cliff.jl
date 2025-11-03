# Cliff.jl

Cliff is a lightweight, type-stable argument parsing library for Julia. It provides three building blocks:

- `Argument` – defines positional arguments, short options, long options, and flags.
- `Command` – describes a sub-command with its own arguments and nested sub-commands.
- `Parser` – top-level parser that aggregates arguments and commands.

Parsing command line arguments returns a `Parsed` object that exposes convenient indexing for retrieving values as strings or strongly typed data.

## Features

- Positional arguments, options, and boolean flags.
- Nested sub-commands with disambiguation of arguments by command depth.
- Explicit handling of `--` to stop option parsing while still allowing sub-command detection.
- Retrieval helpers such as `parsed["name"]`, `parsed["name", depth]`, and `parsed[Type, "name"]`.
- No implicit `--help` handling and no automatic usage string generation.

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

parsed = parser(["run", "fast", "--threads", "8", "task-name"])

println(parsed.command)             # ["run", "fast"]
println(parsed["task"])            # "task-name"
println(parsed[Int, "--threads"])  # 8
println(parsed[Bool, "--verbose"]) # false
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
