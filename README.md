# 🏔️ Cliff.jl

Cliff, the Command Line InterFace Factory, is a lightweight, type-stable argument parsing library for Julia built to help you assemble polished CLIs without fuss.

```julia
using Cliff

hello = Parser(
    arguments = [
        Argument("name"),
        Argument("--uppercase"; flag = true),
        Argument("--excitement"; default = "1"),
    ],
)

function greet(argv)
    args = hello(argv)
    name = args["name"]
    exclamations = repeat("!", args["--excitement", Int])
    if args["--uppercase", Bool]
        name = uppercase(name)
    end
    println("Hello ", name, exclamations)
end

greet(["Julia", "--uppercase", "--excitement", "3"])
# prints: Hello JULIA!!!
```

See `examples/example.jl` for a more detailed walk-through of nested commands, typed retrieval, validation, and error handling.

## Features

### Argument definition

- Cliff automatically marks arguments optional whenever a sensible default exists: providing `default`, using `flag = true`, marking `stop = true`, or specifying `repeat = true` all drop the minimum occurrence to zero.
- Apply `choices` to constrain input to an explicit allowlist and `regex` to enforce pattern matching.
- Repeatable positional arguments, options, and flags with configurable occurrence ranges.
- Arguments that can terminate parsing early via `stop = true` (ideal for `--help`).

### Command orchestration

- Nested sub-commands with disambiguation of arguments by command depth.
- Reusable command definitions via `Command("name", parser)`.
- Explicit handling of `--` to stop option parsing while still allowing sub-command detection.

### Retrieval & diagnostics

- Retrieval helpers such as `args["name"]`, `args["name", depth]`, `args["name", Type]`, and `args["name", Vector{T}]` (or the shorthand `args["name", Type, +]`).
- Configurable error handling that can exit, throw a `ParseError`, or return a partial `Parsed` result.
- No implicit `--help` handling and no automatic usage string generation.

## User Guide

### Core types

Cliff provides three building blocks:

- `Argument` – defines positional arguments, short options, long options, and flags.
- `Command` – describes a sub-command with its own arguments and nested sub-commands.
- `Parser` – top-level parser that aggregates arguments and commands.

Parsing command line arguments returns a `Parsed` object—typically stored in a variable named `args`—that exposes convenient indexing for retrieving values as strings or strongly typed data.

### Working with parsed values

Values are stored as strings but can be converted when accessed from a `Parsed` object:

- `args["name"]` or `args["name", String]` returns the raw string value.
- `args["name", Bool]` recognises `true`, `false`, `1`, `0`, `yes`, `no`, `on`, and `off` (case insensitive).
- `args["name", T]` uses `Base.parse(T, value)` for any type `T` with a parsing method, such as `Int`, `Float64`, or `UInt`.
- `args["name", Vector{T}]` (or the shorthand `args["name", T, +]`) converts each provided value for repeatable arguments or flags.

This allows you to keep your parser definitions declarative while still retrieving strongly typed values at the call site. The returned `Parsed` object also exposes `success`, `complete`, `stopped`, `stop_argument`, and an optional `error::ParseError` for full diagnostics.

### Argument validation and repetition

Cliff can validate incoming values without custom code:

- `choices = [...]` forces inputs to match a curated allowlist. Defaults and explicit `flag_value`s must appear in the same list.
- `regex = r"..."` requires each value to match the supplied pattern.
- Use `required = false` to assert that an argument stays optional; Cliff raises an error if no sensible default exists.

Both options apply to positional arguments, options, and flags, and they work alongside repetition controls. When validation fails Cliff raises a `ParseError` with kind `:invalid_value` so you can render a friendly message or surface it to the user as-is.

```julia
Argument("mode"; choices = ["fast", "slow"], default = "fast")
Argument("--name"; regex = r"^[a-z]+$", default = "guest")
Argument("--tag"; choices = ["red", "blue"], repeat = true)
```

### Constructing parsers

Bring Cliff into scope with `using Cliff` and assemble your parser from the building blocks above:

```julia
using Cliff

parser = Parser(
    arguments = [
        Argument("input"),
        Argument(["--count", "-c"]; default = "1"),
        Argument("--tag"; repeat = true),
        Argument("--mode"; choices = ["fast", "slow"], default = "fast"),
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

args = parser(["input.txt", "--tag", "demo", "--tag", "release", "run", "task-name", "fast", "--threads", "8"])

println(args.command)             # ["run", "fast"]
println(args["input"])           # "input.txt"
println(args["task"])            # "task-name"
println(args["--mode"])          # "fast"
println(args["--threads", Int])  # 8
println(args["--verbose", Bool]) # false

# Collect repeated values
println(args["--tag", Vector{String}])      # ["demo", "release"]
```

#### Flags and `flag_value`

Flags default to the string "false" when omitted, so `args["--verbose", Bool]` returns `false` unless the flag appears on the command line. When a flag is present it adopts a value that can be customised via the `flag_value` keyword. If you omit `flag_value` Cliff picks a sensible opposite of the default ("true" ↔ "false", "yes" ↔ "no", "on" ↔ "off", etc.) and falls back to "true" for anything else:

```julia
Argument("--confirm"; flag = true, default = "no")        # -> "no" / "yes"
Argument("--enable"; flag = true)                          # -> "false" / "true"
Argument("--mode"; flag = true, default = "disabled", flag_value = "enabled")
```

### Early stopping and error handling

Mark any argument with `stop = true` to halt parsing once that argument (and any associated value) has been consumed. Cliff treats these arguments as optional so they never block required-argument checks. This is particularly handy for implementing manual `--help` handling:

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

### Examples

`examples/example.jl` demonstrates all core features—including nested commands, positional and option defaults, value validation, repeating arguments, early stopping, and error handling. Run it with different argument lists to see how `Parsed` changes:

```bash
julia --project examples/example.jl --help
julia --project examples/example.jl target --tag demo --tag test --verbose --profile release --label nightly-build run quick --repeat once --repeat twice --threads 6 fast --limit 5 --extra a --extra b
```
