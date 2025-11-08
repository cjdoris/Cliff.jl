# 🏔️ Cliff.jl

Cliff, the Command Line InterFace Factory, is a lightweight, type-stable argument parsing library for Julia built to help you assemble polished CLIs without fuss. It combines familiar ergonomics with a few focused conveniences:

- Standard command-line affordances such as positional arguments, long options (`--arg=foo`), short options (`-n 5`), flags (`--version`), and repeated arguments (`-vvv`).
- Arbitrarily nested subcommands so complex workflows like `git remote add ...` feel natural.
- Type-stable retrieval helpers that convert values on access, keeping downstream code predictable.
- Early-stopping hooks and auto-help support so `--help` and similar flags can exit gracefully.

```julia
using Cliff

hello = Parser([
    Argument("name"),
    Argument("--uppercase"; flag = true),
    Argument("--excitement"; default = "1"),
])

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
- `args["name", Vector{T}]` (or the shorthand `args["name", T, +]`) converts each value provided on the command line—defaults are not injected.
- `args["name", Union{String, Nothing}]` returns `nothing` when the argument was optional, not supplied, and has no default. Use `args["name", T, -]` (or `args["name", -]` for strings) as a shorthand for optional typed lookups that honour defaults (including the implicit `"0"` for flags).

Single-valued lookups such as `args["--mode"]` raise an `ArgumentError` if the option was omitted and has no default. Pair them with the optional retrieval form when you need to distinguish between “missing” and “present with a default”.

This allows you to keep your parser definitions declarative while still retrieving strongly typed values at the call site. The returned `Parsed` object also exposes `success`, `complete`, `stopped`, `stop_argument`, and an optional `error::ParseError` for full diagnostics.

### Argument validation and repetition

Cliff can validate incoming values without custom code:

- `choices = [...]` forces inputs to match a curated allowlist. Defaults must appear in the same list, and flags require both `"0"` and `"1"` when choices are provided.
- `regex = r"..."` requires each value to match the supplied pattern.
- Positional arguments remain required unless a default is present or you explicitly relax them with `required = false`.

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

parser = Parser([
    Argument("input"),
    Argument(["--count", "-c"]; default = "1"),
    Argument("--tag"; repeat = true),
    Argument("--mode"; choices = ["fast", "slow"], default = "fast"),
    Argument("--verbose"; flag = true)
], [
    Command("run", [Argument("task")], [
        Command("fast", [Argument("--threads"; default = "4")])
    ])
])

# Non-positional arguments are optional unless you set `required = true` or
# supply repetition bounds that demand at least one occurrence.

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

#### Flags and counts

Flags default to the string "0" and record "1" for every occurrence. `args["--verbose", Bool]` therefore returns `false` unless the flag appears on the command line, `args["--verbose"]` yields "0" or "1", and `args["--verbose", Int]` reports the number of times the flag was provided. When a flag is absent `args["--verbose", Vector{T}]` returns an empty vector, making it easy to detect whether users opted in.

### Early stopping and error handling

Mark any argument with `stop = true` to halt parsing once that argument (and any associated value) has been consumed. Cliff treats these arguments as optional so they never block required-argument checks. This is particularly handy for implementing manual `--help` handling:

```julia
help_parser = Parser([
    Argument("input"),
    Argument("--help"; flag = true, stop = true)
], [
    Command("run", [Argument("task")])
])

help_args = help_parser(["--help"])
help_args.stopped        # true
help_args.complete       # false – required arguments are unchecked
help_args.stop_argument  # "--help"
```

Prefer `Argument("--help"; auto_help = true)` when you want Cliff to wire up
help flags automatically. Auto help arguments behave like the manual example
above but also propagate to sub-commands and, when invoked with `error_mode =
:exit`, print a basic usage summary before exiting.

When validation fails you can control how Cliff responds using the `error_mode` keyword:

```julia
parse(help_parser, String[]; error_mode = :return)  # -> Parsed with success = false
parse(help_parser, String[]; error_mode = :throw)   # -> throws ParseError
parse(help_parser, String[]; error_mode = :exit)    # -> prints message and exits (default)
```

### Examples

`examples/example.jl` demonstrates all core features—including nested commands, positional and option defaults, value validation, repeating arguments, early stopping, and error handling. The script prints `@show` summaries for top-level arguments and active sub-commands, exits on error, and honours `--help` stops. Run it with different argument lists to see how `Parsed` changes:

```bash
julia --project examples/example.jl --help
julia --project examples/example.jl target --tag demo --tag test --verbose --profile release --label nightly-build run quick --repeat once --repeat twice --threads 6 fast --limit 5 --extra a --extra b
```
