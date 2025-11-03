# 🏔️ Cliff.jl

🏔️ Cliff (the "command line interface factory," or CLI factory) is a lightweight, type-stable argument parsing library for Julia built to help you assemble polished CLIs without fuss. It provides three building blocks:

- `Argument` – defines positional arguments, short options, long options, and flags.
- `Command` – describes a sub-command with its own arguments and nested sub-commands.
- `Parser` – top-level parser that aggregates arguments and commands.

Parsing command line arguments returns a `Parsed` object—typically stored in a variable named `args`—that exposes convenient indexing for retrieving values as strings or strongly typed data.

## Features

- Positional and option arguments are required by default unless you provide a default or explicitly mark them optional, while flags remain optional with an implicit default of `"false"`.
- Nested sub-commands with disambiguation of arguments by command depth.
- Reusable command definitions via `Command("name", parser)`.
- Explicit handling of `--` to stop option parsing while still allowing sub-command detection.
- Arguments that can terminate parsing early via `stop = true` (ideal for `--help`).
- Repeatable positional arguments, options, and flags with configurable occurrence ranges.
- Retrieval helpers such as `args["name"]`, `args["name", depth]`, `args["name", Type]`, and `args["name", Vector{T}]` (or the shorthand `args["name", Type, +]`).
- Configurable error handling that can exit, throw a `ParseError`, or return a partial `Parsed` result.
- No implicit `--help` handling and no automatic usage string generation.

## Typed Retrieval

Values are stored as strings but can be converted when accessed from a `Parsed` object:

- `args["name"]` or `args["name", String]` returns the raw string value.
- `args["name", Bool]` recognises `true`, `false`, `1`, `0`, `yes`, `no`, `on`, and `off` (case insensitive).
- `args["name", T]` uses `Base.parse(T, value)` for any type `T` with a parsing method, such as `Int`, `Float64`, or `UInt`.
- `args["name", Vector{T}]` (or the shorthand `args["name", T, +]`) converts each provided value for repeatable arguments or flags.

This allows you to keep your parser definitions declarative while still retrieving strongly typed values at the call site.

## Quick Start

In code, bring 🏔️ Cliff into scope with `using Cliff`:

```julia
using Cliff

parser = Parser(
    arguments = [
        Argument("input"),
        Argument(["--count", "-c"]; default = "1"),
        Argument("--verbose"; flag = true)
    ],
    commands = [
        Command("run";
            arguments = [Argument("task")],
            commands = [
                Command("fast";
                    arguments = [Argument("--threads"; default = "4")]
                )
            ]
        )
    ]
)

args = parser(["input.txt", "run", "task-name", "fast", "--threads", "8"])

println(args.command)             # ["run", "fast"]
println(args["input"])           # "input.txt"
println(args["task"])            # "task-name"
println(args["--threads", Int])  # 8
println(args["--verbose", Bool]) # false

# Collect repeated values
println(args["--threads", Vector{String}])  # ["8"]
```

### Flags and `flag_value`

Flags default to the string `"false"` when omitted, so `args["--verbose", Bool]` returns `false` unless the flag appears on the command line. When a flag is present it adopts a value that can be customised via the `flag_value` keyword. If you omit `flag_value` Cliff picks a sensible opposite of the default (`"true"` ↔ `"false"`, `"yes"` ↔ `"no"`, `"on"` ↔ `"off"`, etc.) and falls back to `"true"` for anything else:

```julia
Argument("--confirm"; flag = true, default = "no")        # -> "no" / "yes"
Argument("--enable"; flag = true)                          # -> "false" / "true"
Argument("--mode"; flag = true, default = "disabled", flag_value = "enabled")
```

## Early stopping and error handling

Mark any argument with `stop = true` to halt parsing once that argument (and any associated value) has been consumed. This is particularly handy for implementing manual `--help` handling:

```julia
help_parser = Parser(
    arguments = [
        Argument("input"),
        Argument("--help"; flag = true, stop = true)
    ],
    commands = [Command("run"; arguments = [Argument("task")])]
)

help_args = help_parser(["--help"])
help_args.stopped        # true
help_args.complete       # false – required arguments are unchecked
help_args.stop_argument  # "--help"
```

When validation fails you can control how Cliff responds using the `error_mode` keyword:

```julia
parse(help_parser, String[]; error_mode = :return)  # -> Parsed with success = false
parse(help_parser, String[]; error_mode = :throw)   # -> throws ParseError
parse(help_parser, String[]; error_mode = :exit)    # -> prints message and exits (default)
```

The returned `Parsed` object exposes `success`, `complete`, `stopped`, `stop_argument`, and an optional `error::ParseError` for full diagnostics.

## Examples

`examples/example.jl` demonstrates all core features—including nested commands, positional and option defaults, repeating arguments, early stopping, and error handling. Run it with different argument lists to see how `Parsed` changes:

```bash
julia --project examples/example.jl --help
julia --project examples/example.jl target --tag demo --tag test --verbose run quick --repeat once --repeat twice --threads 6 fast --limit 5 --extra a --extra b
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

🏔️ Cliff intentionally focuses on the core parsing features above. Suggestions for additional capabilities are welcome as follow-up work.
