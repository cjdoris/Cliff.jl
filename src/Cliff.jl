module Cliff

export Argument, Command, Parser, Parsed, ParseError

"""
    Argument(names; required=false, default=nothing, flag=false, stop=false,
             min_occurs=1, max_occurs=1, choices=nothing, regex=nothing)

Define a positional argument, option, or flag.

Construct with a single `names` argument (string or vector of strings) and optional
keyword arguments such as `required`, `default`, `flag`, `stop`, and
repetition controls.

Fields marked here form the public API and are safe to inspect after
construction:

  * `names::Vector{String}` – canonical names for the argument (first entry is
    typically used when rendering messages).
  * `required::Bool` – whether the argument must appear.
  * `flag::Bool` – `true` for boolean-style flags, otherwise the argument
    expects values.
  * `stop::Bool` – indicates that parsing should halt once this argument is
    seen.
  * `has_default::Bool` – whether default values were supplied.
  * `default::Vector{String}` – default values represented as strings.
  * `positional::Bool` – `true` when the argument is positional.
  * `min_occurs::Int` / `max_occurs::Int` – occurrence bounds.
  * `flag_value::String` – value recorded each time a flag is triggered.
  * `choices::Vector{String}` – explicit allowlist of permitted values.
  * `has_regex::Bool` / `regex::Regex` – pattern validation metadata.

Flags always default to the string "0" (reported as falsey) and record "1"
when encountered. Repeated arguments accumulate values in the order they were
provided.
"""
struct Argument
    names::Vector{String}
    required::Bool
    flag::Bool
    stop::Bool
    has_default::Bool
    default::Vector{String}
    positional::Bool
    min_occurs::Int
    max_occurs::Int
    flag_value::String
    choices::Vector{String}
    has_regex::Bool
    regex::Regex
end

"""
    Command(names, [arguments], [commands])

Describe a command or sub-command with its own `arguments` and nested
`commands`.

Construct with a single `names` argument plus positional collections for the
argument list and nested commands.

Public fields:

  * `names::Vector{String}` – aliases recognised for the command.
  * `arguments::Vector{Argument}` – command-scoped arguments.
  * `commands::Vector{Command}` – nested sub-commands.
  * `argument_lookup::Dict{String, Int}` – mapping from argument name to index
    (exposed for introspection, though generally internal).
  * `positional_indices::Vector{Int}` – order of positional arguments.
  * `command_lookup::Dict{String, Int}` – sub-command lookup table.
"""
struct Command
    names::Vector{String}
    arguments::Vector{Argument}
    commands::Vector{Command}
    argument_lookup::Dict{String, Int}
    positional_indices::Vector{Int}
    command_lookup::Dict{String, Int}
end

"""
    Parser([arguments], [commands])

Create a top-level parser with optional global arguments and nested commands.

Use `parser(argv)` or `parse(parser, argv)` to obtain a `Parsed` result. Once
constructed, the following fields constitute the public API:

  * `arguments::Vector{Argument}` – arguments accepted at the current level.
  * `commands::Vector{Command}` – immediate sub-commands.
  * `argument_lookup`, `positional_indices`, `command_lookup` – lookup tables
    provided for advanced inspection and tooling.
"""
struct Parser
    arguments::Vector{Argument}
    commands::Vector{Command}
    argument_lookup::Dict{String, Int}
    positional_indices::Vector{Int}
    command_lookup::Dict{String, Int}
end

"""
    LevelResult

Internal cache of argument metadata and collected values for a parser level.

Each `Parsed` object carries a vector of `LevelResult`s – one per active
command. They are mutated during parsing and should not be constructed or
modified directly by API consumers.
"""
mutable struct LevelResult
    arguments::Vector{Argument}
    argument_lookup::Dict{String, Int}
    positional_indices::Vector{Int}
    values::Vector{Vector{String}}
    counts::Vector{Int}
end

"""
    ParseError <: Exception

Exception raised when parsing fails.

Fields exposed for diagnostics include:

  * `kind::Symbol` – error classification (:missing_required, :invalid_value,
    etc.).
  * `message::String` – human-readable explanation.
  * `command::Vector{String}` – command path active when the error occurred.
  * `levels::Vector{LevelResult}` – parser state snapshot, useful for tooling.
  * `argument::Union{Nothing, String}` – offending argument name, if any.
  * `token::Union{Nothing, String}` – input token that triggered the error.
  * `stopped::Bool` / `stop_argument::Union{Nothing, String}` – indicate that a
    stop argument halted parsing before completion.
"""
struct ParseError <: Exception
    kind::Symbol
    message::String
    command::Vector{String}
    levels::Vector{LevelResult}
    argument::Union{Nothing, String}
    token::Union{Nothing, String}
    stopped::Bool
    stop_argument::Union{Nothing, String}
end

"""
    Base.showerror(io::IO, err::ParseError)

Display a `ParseError` by printing its message.

Allows pretty printing via the standard Julia error-reporting machinery.
"""
function Base.showerror(io::IO, err::ParseError)
    print(io, err.message)
end

function _throw_parse_error(kind::Symbol, message::AbstractString, command_path::Vector{String}, levels::Vector{LevelResult};
        argument::Union{Nothing, AbstractString} = nothing,
        token::Union{Nothing, AbstractString} = nothing,
        stopped::Bool = false,
        stop_argument::Union{Nothing, AbstractString} = nothing)
    arg_name = argument === nothing ? nothing : String(argument)
    token_name = token === nothing ? nothing : String(token)
    stop_name = stop_argument === nothing ? nothing : String(stop_argument)
    throw(ParseError(kind, String(message), copy(command_path), copy(levels), arg_name, token_name, stopped, stop_name))
end

"""
    Parsed

Parsed representation returned by `parse` or calling a `Parser` as a function.

Key public fields:

  * `command::Vector{String}` – selected command path.
  * `levels::Vector{LevelResult}` – internal data for each command level.
  * `success::Bool` – `true` when parsing succeeded.
  * `complete::Bool` – `false` when stop arguments short-circuit required
    checks.
  * `error::Union{Nothing, ParseError}` – populated when parsing fails.
  * `stopped::Bool` / `stop_argument::Union{Nothing, String}` – information
    about stop arguments.

Index into a `Parsed` object via `args[name]`, `args[name, depth]`, or typed
accessors such as `args[name, T]` and `args[name, Vector{T}]`.
"""
struct Parsed
    command::Vector{String}
    levels::Vector{LevelResult}
    success::Bool
    complete::Bool
    error::Union{Nothing, ParseError}
    stopped::Bool
    stop_argument::Union{Nothing, String}
end

# Internal helpers

"""
    _collect_names(names)

Internal helper used by `Argument` and `Command` constructors to normalise name
inputs. Accepts a single string or a collection of strings and returns a
de-duplicated `Vector{String}`.
"""
function _collect_names(names)
    collected = String[]
    seen = Dict{String, Bool}()
    if names isa AbstractString
        _push_name!(collected, seen, String(names))
    elseif names isa AbstractVector{<:AbstractString} || names isa Tuple
        for item in names
            if item isa AbstractString
                _push_name!(collected, seen, String(item))
            else
                throw(ArgumentError("Argument names must be strings"))
            end
        end
    else
        throw(ArgumentError("Argument names must be strings"))
    end
    if isempty(collected)
        throw(ArgumentError("At least one name must be provided"))
    end
    return collected
end

"""
    _push_name!(collected, seen, name)

Shared helper for `_collect_names` that enforces uniqueness while preserving
insertion order.
"""
function _push_name!(collected::Vector{String}, seen::Dict{String, Bool}, name::String)
    if haskey(seen, name)
        throw(ArgumentError("Duplicate name: $(name)"))
    end
    push!(collected, name)
    seen[name] = true
    return nothing
end

"""
    _build_argument_lookup(arguments)

Construct a name-to-index lookup table for a set of arguments. Used during
parser initialisation and referenced repeatedly while parsing.
"""
function _build_argument_lookup(arguments::Vector{Argument})
    lookup = Dict{String, Int}()
    for (idx, argument) in enumerate(arguments)
        for name in argument.names
            if haskey(lookup, name)
                throw(ArgumentError("Duplicate argument name: $(name)"))
            end
            lookup[name] = idx
        end
    end
    return lookup
end

"""
    _build_positional_indices(arguments)

Return indices of positional arguments in the order they appear. Enables quick
iteration over pending positional slots while parsing.
"""
function _build_positional_indices(arguments::Vector{Argument})
    indices = Int[]
    for (idx, argument) in enumerate(arguments)
        if argument.positional
            push!(indices, idx)
        end
    end
    return indices
end

"""
    _build_command_lookup(commands)

Build a mapping from command name to index for fast command dispatch during
parsing.
"""
function _build_command_lookup(commands::Vector{Command})
    lookup = Dict{String, Int}()
    for (idx, command) in enumerate(commands)
        for name in command.names
            if haskey(lookup, name)
                throw(ArgumentError("Duplicate command name: $(name)"))
            end
            lookup[name] = idx
        end
    end
    return lookup
end

const _UNBOUNDED = typemax(Int)

"""
    _normalize_repeat_value(value, name)

Validate and convert repetition bounds supplied to `Argument`. Ensures values
are non-negative integers and raises descriptive errors otherwise.
"""
function _normalize_repeat_value(value, name::String)
    if !(value isa Integer) || value < 0
        throw(ArgumentError("$(name) must be a non-negative integer"))
    end
    return Int(value)
end

"""
    _normalize_max(value)

Normalise `max_repeat` specifications into integer limits. Supports integers,
`Inf`/`:inf`, and `:∞`.
"""
function _normalize_max(value)
    if value === :inf || value === :∞
        return _UNBOUNDED
    elseif value isa Integer
        if value < 0
            throw(ArgumentError("Maximum occurrences must be non-negative"))
        end
        return Int(value)
    elseif value isa AbstractFloat && !isfinite(value)
        return _UNBOUNDED
    else
        throw(ArgumentError("Unsupported maximum occurrences specification"))
    end
end

"""
    _normalize_repeat_spec(repeat)

Interpret the `repeat` keyword, supporting integers, ranges, and `(min, max)`
tuples. Returns `(min_occurs, max_occurs)`.
"""
function _normalize_repeat_spec(repeat)
    if repeat isa Integer
        if repeat < 0
            throw(ArgumentError("Repeat count must be non-negative"))
        end
        val = Int(repeat)
        return val, val
    elseif repeat isa AbstractRange
        first_val = first(repeat)
        last_val = last(repeat)
        if !(first_val isa Integer) || first_val < 0
            throw(ArgumentError("Repeat range must start with a non-negative integer"))
        end
        if step(repeat) != 1
            throw(ArgumentError("Repeat range must have a step size of 1"))
        end
        min_occurs = Int(first_val)
        if last_val isa Integer
            if last_val < min_occurs
                throw(ArgumentError("Repeat range must have non-decreasing bounds"))
            end
            return min_occurs, Int(last_val)
        elseif last_val isa AbstractFloat && !isfinite(last_val)
            return min_occurs, _UNBOUNDED
        else
            throw(ArgumentError("Repeat range must end with an integer or Inf"))
        end
    elseif repeat isa Tuple && length(repeat) == 2
        min_spec, max_spec = repeat
        min_occurs = _normalize_repeat_value(min_spec, "Minimum occurrences")
        max_occurs = max_spec === nothing ? _UNBOUNDED : _normalize_max(max_spec)
        return min_occurs, max_occurs
    else
        throw(ArgumentError("Unsupported repeat specification"))
    end
end

"""
    _determine_occurrences(required, repeat, min_repeat, max_repeat)

Combine required/repeat settings into `(min_occurs, max_occurs)` pairs. Called
from the `Argument` constructor.
"""
function _determine_occurrences(required::Bool, repeat, min_repeat, max_repeat)
    min_occurs = required ? 1 : 0
    max_occurs = 1
    if repeat !== nothing && (min_repeat !== nothing || max_repeat !== nothing)
        throw(ArgumentError("Cannot specify repeat together with min_repeat or max_repeat"))
    end
    if repeat !== nothing
        if repeat === true
            min_occurs = required ? 1 : 0
            max_occurs = _UNBOUNDED
        else
            min_occurs, max_occurs = _normalize_repeat_spec(repeat)
        end
    end
    if min_repeat !== nothing
        min_occurs = _normalize_repeat_value(min_repeat, "Minimum occurrences")
    end
    if max_repeat !== nothing
        max_occurs = _normalize_max(max_repeat)
    end
    if required && min_occurs == 0
        min_occurs = 1
    end
    if max_occurs != _UNBOUNDED && min_occurs > max_occurs
        throw(ArgumentError("Minimum occurrences cannot exceed maximum occurrences"))
    end
    return min_occurs, max_occurs
end

"""
    _normalize_choices(values)

Ensure that `choices` is a non-empty vector of unique strings. Used by
`Argument` for validation.
"""
function _normalize_choices(values)
    if !(values isa AbstractVector)
        throw(ArgumentError("choices must be provided as a vector of strings"))
    end
    seen = Dict{String, Bool}()
    normalised = String[]
    for value in values
        if !(value isa AbstractString)
            throw(ArgumentError("choices must contain only strings"))
        end
        str = String(value)
        if haskey(seen, str)
            throw(ArgumentError("Duplicate choice: $(str)"))
        end
        push!(normalised, str)
        seen[str] = true
    end
    if isempty(normalised)
        throw(ArgumentError("choices must contain at least one value"))
    end
    return normalised
end

"""
    _normalize_regex(regex)

Accept either a `Regex` or pattern string and return a `Regex` instance for
argument validation.
"""
function _normalize_regex(regex)
    if regex isa Regex
        return regex
    elseif regex isa AbstractString
        return Regex(String(regex))
    else
        throw(ArgumentError("regex must be a Regex or a string pattern"))
    end
end

"""
    Argument(names...; required=nothing, default=nothing, flag=false,
             stop=false, repeat=nothing, min_repeat=nothing,
             max_repeat=nothing, choices=nothing, regex=nothing)

Create an `Argument` for positional values, long options, or flags. Supply one
or more names as strings (or vectors of strings); short options must be exactly
two characters long (e.g. `"-h"`). Keyword arguments:

  * `required` – force the argument to be required (`true`), optional (`false`),
    or let Cliff infer the requirement (`nothing`).
  * `default` – default value(s). Non-string inputs are rendered via `repr` so
    `default = 5` behaves as expected.
  * `flag` – mark the argument as a flag. Flags always default to "0" and
    record "1" for each occurrence.
  * `stop` – halt parsing once the argument has been consumed.
  * `repeat`, `min_repeat`, `max_repeat` – control occurrence counts.
  * `choices` – restrict accepted values to a specific list.
  * `regex` – require values to match a `Regex`.

Flags cannot customise defaults or `flag_value`; they always behave like
booleans with string representations "0"/"1". When `default` is a vector each
element is stored in the order provided, making `default = [1, 2, 3]` suitable
for repeatable arguments. Internally this constructor validates combinations
and prepares lookup tables consumed by `Parser`.
"""
function Argument(names; required::Union{Bool, Nothing} = nothing, default = nothing, flag::Bool = false, flag_value = nothing, stop::Bool = false, repeat = nothing, min_repeat = nothing, max_repeat = nothing, choices = nothing, regex = nothing)
    collected = _collect_names(names)
    positional = any(!startswith(name, "-") for name in collected)
    option = any(startswith(name, "-") for name in collected)
    if positional && option
        throw(ArgumentError("An argument cannot mix positional and option names"))
    end
    if flag && positional
        throw(ArgumentError("Flags must use option-style names"))
    end
    for name in collected
        if startswith(name, "-") && !startswith(name, "--")
            dash_index = firstindex(name)
            char_index = nextind(name, dash_index)
            if char_index > lastindex(name)
                throw(ArgumentError("Short option name must include a character after '-': $(name)"))
            end
            terminal = nextind(name, char_index)
            if terminal <= lastindex(name)
                throw(ArgumentError("Short option names must consist of '-' followed by a single character: $(name)"))
            end
        end
    end
    if flag_value !== nothing
        throw(ArgumentError("flag_value is not configurable"))
    end
    if stop && (repeat !== nothing || min_repeat !== nothing || max_repeat !== nothing)
        throw(ArgumentError("Stop arguments cannot be repeatable"))
    end
    if flag && default !== nothing
        throw(ArgumentError("Flags do not support default values"))
    end
    has_default = !flag && default !== nothing
    default_values = String[]
    if has_default
        if default isa AbstractVector
            default_values = String[]
            for item in default
                if item isa AbstractString
                    push!(default_values, String(item))
                else
                    push!(default_values, repr(item))
                end
            end
        elseif default isa AbstractString
            push!(default_values, String(default))
        else
            push!(default_values, repr(default))
        end
    end
    computed_flag_value = flag ? "1" : ""
    repeat_implies_optional = repeat === true
    has_sensible_default = has_default || flag || repeat_implies_optional || stop
    if required === false && !has_sensible_default
        throw(ArgumentError("required=false is only supported when the argument is optional by default"))
    end
    required_flag = required === nothing ? !has_sensible_default : required
    min_occurs, max_occurs = _determine_occurrences(required_flag, repeat, min_repeat, max_repeat)
    if has_default && max_occurs != _UNBOUNDED && length(default_values) > max_occurs
        throw(ArgumentError("Default value count exceeds maximum occurrences"))
    end
    choice_values = choices === nothing ? String[] : _normalize_choices(choices)
    regex_obj = regex === nothing ? r"" : _normalize_regex(regex)
    has_regex = regex !== nothing
    if !isempty(choice_values)
        for value in default_values
            if value ∉ choice_values
                throw(ArgumentError("Default value $(repr(value)) is not permitted by choices"))
            end
        end
        if flag && !("1" in choice_values && "0" in choice_values)
            throw(ArgumentError("Flags require choices to include both \"0\" and \"1\""))
        end
    end
    if has_regex
        for value in default_values
            if match(regex_obj, value) === nothing
                throw(ArgumentError("Default value $(repr(value)) does not match regex"))
            end
        end
        if flag
            if match(regex_obj, "0") === nothing || match(regex_obj, computed_flag_value) === nothing
                throw(ArgumentError("Flags require regex patterns that match both \"0\" and \"1\""))
            end
        end
    end
    return Argument(collected, min_occurs > 0, flag, stop, has_default, default_values, positional, min_occurs, max_occurs, computed_flag_value, choice_values, has_regex, regex_obj)
end

"""
    Command(names, arguments, commands)
    Command(names, arguments)
    Command(names, commands)
    Command(names)

Create a command or sub-command. Provide a `names` argument plus positional
arguments for the command-local `arguments` and nested `commands`. Commands can
be nested directly or constructed from an existing `Parser` using
`Command(name, parser)`.
"""
function Command(names, arguments::Vector{Argument}, commands::Vector{Command})
    collected = _collect_names(names)
    args_vec = Vector{Argument}(arguments)
    cmds_vec = Vector{Command}(commands)
    argument_lookup = _build_argument_lookup(args_vec)
    positional_indices = _build_positional_indices(args_vec)
    command_lookup = _build_command_lookup(cmds_vec)
    return Command(collected, args_vec, cmds_vec, argument_lookup, positional_indices, command_lookup)
end

Command(names, arguments::Vector{Argument}) = Command(names, arguments, Command[])
Command(names, commands::Vector{Command}) = Command(names, Argument[], commands)
Command(names) = Command(names, Argument[], Command[])

"""
    Command(name::AbstractString, nested::Parser)

Wrap an existing parser so it can be mounted as a sub-command. The nested
parser's arguments and commands are copied into the resulting `Command`.
"""
function Command(name::AbstractString, nested::Parser)
    return Command(name, nested.arguments, nested.commands)
end

"""
    Parser(arguments, commands)
    Parser(arguments)
    Parser(commands)
    Parser()

Construct a top-level parser. Arguments and commands apply to the root level.
Invoking the parser with `parser(argv)` (or `parse(parser, argv)`) returns a
`Parsed` value that exposes indexing helpers and error diagnostics.
"""
function Parser(arguments::Vector{Argument}, commands::Vector{Command})
    args_vec = Vector{Argument}(arguments)
    cmds_vec = Vector{Command}(commands)
    argument_lookup = _build_argument_lookup(args_vec)
    positional_indices = _build_positional_indices(args_vec)
    command_lookup = _build_command_lookup(cmds_vec)
    return Parser(args_vec, cmds_vec, argument_lookup, positional_indices, command_lookup)
end

Parser(arguments::Vector{Argument}) = Parser(arguments, Command[])
Parser(commands::Vector{Command}) = Parser(Argument[], commands)
Parser() = Parser(Argument[], Command[])

"""
    _init_level(arguments, lookup, positional_indices)

Create a fresh `LevelResult` for a parser level. Called when entering the root
parser and whenever a sub-command is activated.
"""
function _init_level(arguments::Vector{Argument}, lookup::Dict{String, Int}, positional_indices::Vector{Int})
    values = [String[] for _ in arguments]
    counts = fill(0, length(arguments))
    return LevelResult(arguments, lookup, positional_indices, values, counts)
end

"""
    _ensure_required(level, command_path, levels)

Verify that required arguments at a given level have been satisfied. Invoked
after parsing completes (unless halted by a stop argument).
"""
function _ensure_required(level::LevelResult, command_path::Vector{String}, levels::Vector{LevelResult})
    for (idx, argument) in enumerate(level.arguments)
        provided = level.counts[idx]
        default_count = (argument.has_default && provided == 0) ? length(argument.default) : 0
        total = provided + default_count
        if total < argument.min_occurs
            _throw_parse_error(
                :missing_required,
                "Missing required argument: $(first(argument.names))",
                command_path,
                levels;
                argument = first(argument.names),
            )
        end
    end
end

"""
    _lookup_argument(level, name)

Return the index of the named argument within a level, or `nothing` when the
name is unknown.
"""
function _lookup_argument(level::LevelResult, name::String)
    idx = get(level.argument_lookup, name, 0)
    return idx == 0 ? nothing : idx
end

"""
    _find_level_index(args, name)

Search all parser levels (starting from the innermost) for an argument and
return the level plus index when present. Used by the indexing API.
"""
function _find_level_index(args::Parsed, name::String)
    for idx in Iterators.reverse(eachindex(args.levels))
        level = args.levels[idx]
        position = _lookup_argument(level, name)
        if position !== nothing
            return level, position
        end
    end
    return nothing, 0
end

"""
    _argument_values(level, idx)

Return all recorded (or default) values for the argument at `idx`. Flags return
an empty vector when not present, allowing `args[name, Vector]` to yield `[]`.
"""
function _argument_values(level::LevelResult, idx::Int)
    argument = level.arguments[idx]
    stored = level.values[idx]
    if !isempty(stored)
        return copy(stored)
    elseif argument.has_default
        return copy(argument.default)
    elseif argument.flag
        return String[]
    else
        return String[]
    end
end

"""
    _single_value(level, idx)

Fetch a single value for the argument at `idx`, applying default handling.
Raises when the argument accepts multiple values.
"""
function _single_value(level::LevelResult, idx::Int)
    argument = level.arguments[idx]
    if argument.max_occurs != 1
        throw(ArgumentError("Argument $(first(argument.names)) accepts multiple values; use args[name, Vector] instead"))
    end
    stored = level.values[idx]
    if !isempty(stored)
        return stored[1]
    elseif argument.has_default && !isempty(argument.default)
        return argument.default[1]
    elseif argument.flag
        return "0"
    else
        return ""
    end
end

"""
    _validate_argument_value(argument, value, command_path, levels)

Check `value` against `choices` and `regex` constraints, throwing a `ParseError`
when validation fails. Called for every stored value.
"""
function _validate_argument_value(argument::Argument, value::String, command_path::Vector{String}, levels::Vector{LevelResult})
    if !isempty(argument.choices) && !(value in argument.choices)
        valid = join(argument.choices, ", ")
        _throw_parse_error(
            :invalid_value,
            "Argument $(first(argument.names)) must be one of: $(valid)",
            command_path,
            levels;
            argument = first(argument.names),
            token = value,
        )
    end
    if argument.has_regex && match(argument.regex, value) === nothing
        _throw_parse_error(
            :invalid_value,
            "Argument $(first(argument.names)) must match pattern $(argument.regex)",
            command_path,
            levels;
            argument = first(argument.names),
            token = value,
        )
    end
    return nothing
end

"""
    _set_value!(level, idx, value, command_path, levels)

Store a value for the argument at `idx`, performing validation and respecting
occurrence limits. Returns `true` when a stop argument halts parsing.
"""
function _set_value!(level::LevelResult, idx::Int, value::String, command_path::Vector{String}, levels::Vector{LevelResult})
    argument = level.arguments[idx]
    count = level.counts[idx]
    _validate_argument_value(argument, value, command_path, levels)
    if argument.max_occurs == 1 && count == 1
        level.values[idx][1] = value
        return argument.stop
    elseif argument.max_occurs != _UNBOUNDED && count >= argument.max_occurs
        _throw_parse_error(
            :too_many_occurrences,
            "Argument $(first(argument.names)) cannot be provided more than $(argument.max_occurs) times",
            command_path,
            levels;
            argument = first(argument.names),
        )
    end
    push!(level.values[idx], value)
    level.counts[idx] = count + 1
    return argument.stop
end

"""
    _set_flag!(level, idx, command_path, levels)

Specialised wrapper around `_set_value!` for flags. Stores the string "1" and
returns whether parsing should stop.
"""
function _set_flag!(level::LevelResult, idx::Int, command_path::Vector{String}, levels::Vector{LevelResult})
    argument = level.arguments[idx]
    return _set_value!(level, idx, argument.flag_value, command_path, levels)
end

"""
    _has_outstanding_required(level)

Determine whether there are positional arguments at `level` that still require
values. Used to prevent premature command transitions.
"""
function _has_outstanding_required(level::LevelResult)
    for idx in level.positional_indices
        argument = level.arguments[idx]
        provided = level.counts[idx]
        if provided < argument.min_occurs
            default_count = (argument.has_default && provided == 0) ? length(argument.default) : 0
            if provided + default_count < argument.min_occurs
                return true
            end
        end
    end
    return false
end

"""
    _next_positional_index(level, cursor)

Identify the next positional argument that can accept a value, returning its
index and the cursor position. Enables round-robin handling of positional
arguments with repetition.
"""
function _next_positional_index(level::LevelResult, cursor::Int)
    current = cursor
    while current <= length(level.positional_indices)
        idx = level.positional_indices[current]
        argument = level.arguments[idx]
        if argument.max_occurs == _UNBOUNDED || level.counts[idx] < argument.max_occurs
            return idx, current
        end
        current += 1
    end
    return nothing, current
end

"""
    _consume_option!(levels, argv, i, token, command_path)

Handle a long option token (e.g. `--name` or `--name=value`). Consumes any
associated value, updates the active level, and returns the next index plus an
optional stop-argument name.
"""
function _consume_option!(levels::Vector{LevelResult}, argv::Vector{String}, i::Int, token::String, command_path::Vector{String})
    level = levels[end]
    eq_index = findfirst(==('='), token)
    name = token
    inline_value = nothing
    if eq_index !== nothing
        before = prevind(token, eq_index)
        name = token[firstindex(token):before]
        value_index = nextind(token, eq_index)
        inline_value = value_index > lastindex(token) ? "" : token[value_index:end]
    end
    idx = _lookup_argument(level, name)
    if idx === nothing
        _throw_parse_error(:unknown_option, "Unknown option: $(name)", command_path, levels; token = name)
    end
    argument = level.arguments[idx]
    if argument.positional
        _throw_parse_error(
            :invalid_option_usage,
            "Positional argument $(first(argument.names)) cannot be used as an option",
            command_path,
            levels;
            argument = first(argument.names),
            token = name,
        )
    end
    if argument.flag
        if inline_value !== nothing
            _throw_parse_error(
                :flag_value,
                "Flag $(name) does not accept a value",
                command_path,
                levels;
                argument = first(argument.names),
                token = token,
            )
        end
        triggered = _set_flag!(level, idx, command_path, levels)
        stop_name = triggered ? name : nothing
        return i + 1, stop_name
    end
    if inline_value !== nothing
        triggered = _set_value!(level, idx, inline_value, command_path, levels)
        stop_name = triggered ? name : nothing
        return i + 1, stop_name
    end
    next_index = i + 1
    if next_index > length(argv)
        _throw_parse_error(
            :missing_option_value,
            "Option $(name) requires a value",
            command_path,
            levels;
            argument = first(argument.names),
            token = name,
        )
    end
    triggered = _set_value!(level, idx, argv[next_index], command_path, levels)
    stop_name = triggered ? name : nothing
    return next_index + 1, stop_name
end

"""
    _consume_short_option!(levels, argv, i, token, command_path)

Process short options (tokens beginning with a single `-`). Supports bundled
flags (e.g. `-vvv`), inline values (e.g. `-n3`), and treats forms such as
`-x=3` as the option `-x` with value `"=3"`.
"""
function _consume_short_option!(levels::Vector{LevelResult}, argv::Vector{String}, i::Int, token::String, command_path::Vector{String})
    level = levels[end]
    eq_index = findfirst(==('='), token)
    if eq_index !== nothing
        name_end = prevind(token, eq_index)
        name = token[firstindex(token):name_end]
        idx = _lookup_argument(level, name)
        if idx === nothing
            _throw_parse_error(:unknown_option, "Unknown option: $(name)", command_path, levels; token = name)
        end
        argument = level.arguments[idx]
        if argument.flag
            _throw_parse_error(
                :flag_value,
                "Flag $(name) does not accept a value",
                command_path,
                levels;
                argument = first(argument.names),
                token = token,
            )
        end
        value = token[eq_index:end]
        triggered = _set_value!(level, idx, value, command_path, levels)
        stop_name = triggered ? name : nothing
        return i + 1, stop_name
    end
    dash_index = firstindex(token)
    char_index = nextind(token, dash_index)
    if char_index > lastindex(token)
        _throw_parse_error(:unknown_option, "Unknown option: $(token)", command_path, levels; token = token)
    end
    next_index = nextind(token, char_index)
    name = token[dash_index:prevind(token, next_index)]
    idx = _lookup_argument(level, name)
    if idx === nothing
        _throw_parse_error(:unknown_option, "Unknown option: $(name)", command_path, levels; token = name)
    end
    argument = level.arguments[idx]
    if next_index > lastindex(token)
        if argument.flag
            triggered = _set_flag!(level, idx, command_path, levels)
            stop_name = triggered ? name : nothing
            return i + 1, stop_name
        end
        next_arg_index = i + 1
        if next_arg_index > length(argv)
            _throw_parse_error(
                :missing_option_value,
                "Option $(name) requires a value",
                command_path,
                levels;
                argument = first(argument.names),
                token = name,
            )
        end
        triggered = _set_value!(level, idx, argv[next_arg_index], command_path, levels)
        stop_name = triggered ? name : nothing
        return next_arg_index + 1, stop_name
    end
    if argument.flag
        stop_name = nothing
        triggered = _set_flag!(level, idx, command_path, levels)
        if triggered
            stop_name = name
        end
        rest_index = next_index
        while rest_index <= lastindex(token) && stop_name === nothing
            char_end = nextind(token, rest_index)
            short_piece = token[rest_index:prevind(token, char_end)]
            rest_name = string('-', short_piece)
            rest_idx = _lookup_argument(level, rest_name)
            if rest_idx === nothing
                _throw_parse_error(:unknown_option, "Unknown option: $(rest_name)", command_path, levels; token = rest_name)
            end
            rest_argument = level.arguments[rest_idx]
            if !rest_argument.flag
                _throw_parse_error(
                    :unsupported_short_option,
                    "Unsupported short option bundle: $(token)",
                    command_path,
                    levels;
                    token = token,
                )
            end
            triggered = _set_flag!(level, rest_idx, command_path, levels)
            if triggered
                stop_name = rest_name
            end
            rest_index = char_end
        end
        return i + 1, stop_name
    end
    value = token[next_index:end]
    triggered = _set_value!(level, idx, value, command_path, levels)
    stop_name = triggered ? name : nothing
    return i + 1, stop_name
end

"""
    _execute_parse(parser, argv)

Core parsing loop shared by all entry points. Walks the token list, tracks
active commands, dispatches options/flags, and produces a `Parsed` result. All
error handling (throwing `ParseError`s) lives here.
"""
function _execute_parse(parser::Parser, argv::Vector{String})
    levels = LevelResult[]
    push!(levels, _init_level(parser.arguments, parser.argument_lookup, parser.positional_indices))
    positional_cursors = Int[1]
    command_path = String[]
    current = parser
    i = 1
    allow_options = true
    command_requirements = Bool[!isempty(parser.commands)]
    command_satisfied = Bool[false]
    level_labels = String["parser"]
    level_is_root = Bool[true]
    stopped = false
    stop_argument = nothing
    while i <= length(argv)
        token = argv[i]
        if allow_options && token == "--"
            allow_options = false
            i += 1
            continue
        end
        level = levels[end]
        cmd_idx = get(current.command_lookup, token, 0)
        if cmd_idx != 0 && !_has_outstanding_required(level)
            command_satisfied[end] = true
            next_command = current.commands[cmd_idx]
            current = next_command
            push!(command_path, token)
            push!(levels, _init_level(next_command.arguments, next_command.argument_lookup, next_command.positional_indices))
            push!(positional_cursors, 1)
            allow_options = true
            push!(command_requirements, !isempty(next_command.commands))
            push!(command_satisfied, false)
            push!(level_labels, token)
            push!(level_is_root, false)
            i += 1
            continue
        end
        if allow_options && startswith(token, "--") && token != "--"
            i, stop_name = _consume_option!(levels, argv, i, token, command_path)
            if stop_name !== nothing
                stopped = true
                if stop_argument === nothing
                    stop_argument = stop_name
                end
                break
            end
            continue
        elseif allow_options && startswith(token, "-") && token != "-"
            i, stop_name = _consume_short_option!(levels, argv, i, token, command_path)
            if stop_name !== nothing
                stopped = true
                if stop_argument === nothing
                    stop_argument = stop_name
                end
                break
            end
            continue
        end
        positional_index, cursor_position = _next_positional_index(level, positional_cursors[end])
        if positional_index === nothing
            _throw_parse_error(:unexpected_positional, "Unexpected positional argument: $(token)", command_path, levels; token = token)
        end
        argument = level.arguments[positional_index]
        triggered = _set_value!(level, positional_index, token, command_path, levels)
        if argument.max_occurs != _UNBOUNDED && level.counts[positional_index] >= argument.max_occurs
            positional_cursors[end] = cursor_position + 1
        else
            positional_cursors[end] = cursor_position
        end
        if triggered
            stopped = true
            if stop_argument === nothing
                stop_argument = first(argument.names)
            end
            break
        end
        i += 1
    end
    if !stopped
        for level in levels
            _ensure_required(level, command_path, levels)
        end
        for idx in eachindex(command_requirements)
            if command_requirements[idx] && !command_satisfied[idx]
                label = level_labels[idx]
                is_root = level_is_root[idx]
                message = is_root ? "Expected a command" : "Expected a sub-command for $(label)"
                _throw_parse_error(:missing_command, message, command_path, levels; token = label)
            end
        end
    end
    command_copy = copy(command_path)
    stop_name = stop_argument === nothing ? nothing : String(stop_argument)
    return Parsed(command_copy, levels, true, !stopped, nothing, stopped, stop_name)
end

"""
    parse(parser, argv; error_mode=:exit, io=stderr, exit_code=1)

Parse `argv` using `parser`. The `error_mode` keyword controls behaviour on
failure:

  * `:exit` – print the error message to `io` and exit with `exit_code`.
  * `:throw` – rethrow the `ParseError`.
  * `:return` – return a `Parsed` value with `success = false`.
"""
function parse(parser::Parser, argv::Vector{String}; error_mode::Symbol = :exit, io::IO = stderr, exit_code::Integer = 1)
    if error_mode ∉ (:exit, :throw, :return)
        throw(ArgumentError("Unsupported error_mode: $(error_mode)"))
    end
    try
        return _execute_parse(parser, argv)
    catch err
        if err isa ParseError
            parsed = Parsed(err.command, err.levels, false, false, err, err.stopped, err.stop_argument)
            if error_mode === :throw
                throw(err)
            elseif error_mode === :return
                return parsed
            else
                println(io, err.message)
                exit(exit_code)
            end
        else
            throw(err)
        end
    end
end

"""
    parser(argv; kwargs...)

Convenience call overload that allows a `Parser` instance to be invoked like a
function. Accepts any vector of strings and forwards keyword arguments to
`parse`.
"""
function (parser::Parser)(argv::AbstractVector{<:AbstractString}; kwargs...)
    return parse(parser, String.(collect(argv)); kwargs...)
end

"""
    parser(; kwargs...)

Invoke a parser against the global `ARGS`. Primarily useful for scripts.
"""
function (parser::Parser)(; kwargs...)
    return parse(parser, copy(ARGS); kwargs...)
end

"""
    Base.getindex(args::Parsed, name)

Retrieve values from a `Parsed` object. Supports optional `depth` arguments to
disambiguate commands and typed lookups such as `args[name, Int]` or
`args[name, Vector{T}]`. Flags return "0"/"1" strings, while integer lookups
yield occurrence counts.
"""
function Base.getindex(args::Parsed, name::String)
    for idx in Iterators.reverse(eachindex(args.levels))
        level = args.levels[idx]
        position = _lookup_argument(level, name)
        if position !== nothing
            return _single_value(level, position)
        end
    end
    throw(KeyError(name))
end

function Base.getindex(args::Parsed, name::String, depth::Integer)
    if depth < 0 || depth + 1 > length(args.levels)
        throw(ArgumentError("Invalid depth: $(depth)"))
    end
    level = args.levels[depth + 1]
    idx = _lookup_argument(level, name)
    if idx === nothing
        throw(KeyError(name))
    end
    return _single_value(level, idx)
end

"""
    _convert_value(T, value)

Convert stored strings into the requested type. Strings are returned unchanged,
`Bool` recognises common truthy/falsey literals, and all other types delegate to
`Base.parse`.
"""
function _convert_value(::Type{String}, value::String)
    return value
end

function _convert_value(::Type{Bool}, value::String)
    if isempty(value)
        return false
    end
    lower = lowercase(value)
    if lower in ("true", "t", "1", "yes", "on")
        return true
    elseif lower in ("false", "f", "0", "no", "off")
        return false
    else
        throw(ArgumentError("Cannot convert \"$(value)\" to Bool"))
    end
end

function _convert_value(T::Type, value::String)
    try
        return Base.parse(T, value)
    catch
        throw(ArgumentError("Cannot convert \"$(value)\" to $(T)"))
    end
end

function Base.getindex(args::Parsed, name::String, ::Type{T}) where {T}
    value = args[name]
    return _convert_value(T, value)
end

function Base.getindex(args::Parsed, name::String, ::Type{Int})
    level, idx = _find_level_index(args, name)
    if level === nothing
        throw(KeyError(name))
    end
    argument = level.arguments[idx]
    if argument.flag
        return level.counts[idx]
    end
    value = _single_value(level, idx)
    return _convert_value(Int, value)
end

function Base.getindex(args::Parsed, name::String, depth::Integer, ::Type{T}) where {T}
    value = args[name, depth]
    return _convert_value(T, value)
end

function Base.getindex(args::Parsed, name::String, depth::Integer, ::Type{Int})
    if depth < 0 || depth + 1 > length(args.levels)
        throw(ArgumentError("Invalid depth: $(depth)"))
    end
    level = args.levels[depth + 1]
    idx = _lookup_argument(level, name)
    if idx === nothing
        throw(KeyError(name))
    end
    argument = level.arguments[idx]
    if argument.flag
        return level.counts[idx]
    end
    value = _single_value(level, idx)
    return _convert_value(Int, value)
end

function Base.getindex(args::Parsed, name::String, ::Type{Vector{T}}) where {T}
    level, idx = _find_level_index(args, name)
    if level === nothing
        throw(KeyError(name))
    end
    values = _argument_values(level, idx)
    converted = Vector{T}(undef, length(values))
    for (i, value) in enumerate(values)
        converted[i] = _convert_value(T, value)
    end
    return converted
end

function Base.getindex(args::Parsed, name::String, depth::Integer, ::Type{Vector{T}}) where {T}
    if depth < 0 || depth + 1 > length(args.levels)
        throw(ArgumentError("Invalid depth: $(depth)"))
    end
    level = args.levels[depth + 1]
    idx = _lookup_argument(level, name)
    if idx === nothing
        throw(KeyError(name))
    end
    values = _argument_values(level, idx)
    converted = Vector{T}(undef, length(values))
    for (i, value) in enumerate(values)
        converted[i] = _convert_value(T, value)
    end
    return converted
end

function Base.getindex(args::Parsed, name::String, ::typeof(+))
    return args[name, Vector{String}]
end

function Base.getindex(args::Parsed, name::String, depth::Integer, ::typeof(+))
    return args[name, depth, Vector{String}]
end

function Base.getindex(args::Parsed, name::String, ::Type{T}, ::typeof(+)) where {T}
    return args[name, Vector{T}]
end

function Base.getindex(args::Parsed, name::String, depth::Integer, ::Type{T}, ::typeof(+)) where {T}
    return args[name, depth, Vector{T}]
end

end # module
