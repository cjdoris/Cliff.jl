# This file defines Cliff's core parser construction types and helpers.

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
  * `default::Vector{String}` – default values expressed as strings.
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
    auto_help::Bool
    help::String
    help_val::String
end

"""
    Command(names, [arguments], [commands])

Describe a command or sub-command with its own `arguments` and nested
`commands`.

Construct with a single `names` argument plus positional collections for the
argument list and nested commands. Set `auto_help = false` to prevent the
command from inheriting auto help flags from its parent.

Public fields:

  * `names::Vector{String}` – aliases recognised for the command.
  * `arguments::Vector{Argument}` – command-scoped arguments.
 * `commands::Vector{Command}` – nested sub-commands.
  * `argument_lookup::Dict{String, Int}` – mapping from argument name to index
    (exposed for introspection, though generally internal).
  * `positional_indices::Vector{Int}` – order of positional arguments.
  * `command_lookup::Dict{String, Int}` – sub-command lookup table.
  * `auto_help::Bool` – whether the command inherits auto help arguments from
    parents.
"""
struct Command
    names::Vector{String}
    arguments::Vector{Argument}
    commands::Vector{Command}
    argument_lookup::Dict{String, Int}
    positional_indices::Vector{Int}
    command_lookup::Dict{String, Int}
    positional_after_first::Bool
    auto_help::Bool
    help::String
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
    positional_after_first::Bool
    help::String
    help_program::String
end

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

function _auto_help_argument(arguments::Vector{Argument})
    for argument in arguments
        if argument.auto_help
            return argument
        end
    end
    return nothing
end

function _construct_command(names::Vector{String}, arguments::Vector{Argument}, commands::Vector{Command}, positional_after_first::Bool, auto_help::Bool, help::String)
    name_vec = Vector{String}(names)
    args_vec = Vector{Argument}(arguments)
    cmds_vec = Vector{Command}(commands)
    argument_lookup = _build_argument_lookup(args_vec)
    positional_indices = _build_positional_indices(args_vec)
    command_lookup = _build_command_lookup(cmds_vec)
    return Command(name_vec, args_vec, cmds_vec, argument_lookup, positional_indices, command_lookup, positional_after_first, auto_help, help)
end

function _construct_parser(arguments::Vector{Argument}, commands::Vector{Command}, positional_after_first::Bool, help::String, help_program::String)
    args_vec = Vector{Argument}(arguments)
    cmds_vec = Vector{Command}(commands)
    argument_lookup = _build_argument_lookup(args_vec)
    positional_indices = _build_positional_indices(args_vec)
    command_lookup = _build_command_lookup(cmds_vec)
    return Parser(args_vec, cmds_vec, argument_lookup, positional_indices, command_lookup, positional_after_first, help, help_program)
end

function _propagate_auto_help_to_commands(commands::Vector{Command}, inherited::Union{Nothing, Argument})
    if isempty(commands)
        return commands, false
    end
    updated = Vector{Command}(undef, length(commands))
    changed = false
    for (idx, command) in enumerate(commands)
        propagated = _propagate_auto_help(command, inherited)
        updated[idx] = propagated
        if propagated !== command
            changed = true
        end
    end
    return changed ? updated : commands, changed
end

function _propagate_auto_help(command::Command, inherited::Union{Nothing, Argument})
    args_vec = command.arguments
    own_auto = _auto_help_argument(args_vec)
    inserted = false
    if own_auto === nothing && inherited !== nothing && command.auto_help
        args_vec = Argument[inherited; args_vec...]
        inserted = true
        own_auto = inherited
    end
    child_inherited = own_auto
    commands_vec, children_changed = _propagate_auto_help_to_commands(command.commands, child_inherited)
    if inserted || children_changed
        final_args = inserted ? args_vec : command.arguments
        final_commands = children_changed ? commands_vec : command.commands
        return _construct_command(command.names, final_args, final_commands, command.positional_after_first, command.auto_help, command.help)
    else
        return command
    end
end

function _propagate_auto_help(parser::Parser)
    auto_help_argument = _auto_help_argument(parser.arguments)
    commands_vec, changed = _propagate_auto_help_to_commands(parser.commands, auto_help_argument)
    if changed
        return _construct_parser(parser.arguments, commands_vec, parser.positional_after_first, parser.help, parser.help_program)
    else
        return parser
    end
end

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

function _repeat_allows_zero_min(repeat, min_repeat)
    if min_repeat !== nothing
        return _normalize_repeat_value(min_repeat, "Minimum occurrences") == 0
    elseif repeat === nothing
        return false
    elseif repeat === true
        return true
    elseif repeat isa Integer
        return repeat == 0
    elseif repeat isa AbstractRange
        first_val = first(repeat)
        return first_val isa Integer && Int(first_val) == 0
    elseif repeat isa Tuple && length(repeat) == 2
        min_spec, _ = repeat
        return _normalize_repeat_value(min_spec, "Minimum occurrences") == 0
    else
        return false
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
             max_repeat=nothing, choices=nothing, regex=nothing,
             auto_help=false)

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
  * `auto_help` – mark the argument as an automatic help flag.

Flags cannot customise defaults or `flag_value`; they always behave like
booleans with string representations "0"/"1". Other arguments accept a vector
of default strings whose entries seed the collected value list – each
occurrence replaces the corresponding position and additional occurrences are
appended. This keeps scalar and vector retrieval consistent while letting
defaults satisfy repetition bounds. Internally this constructor validates
combinations and prepares lookup tables consumed by `Parser`.
"""
function Argument(names; required::Union{Bool, Nothing} = nothing, default = nothing, flag::Bool = false, flag_value = nothing, stop::Bool = false, repeat = nothing, min_repeat = nothing, max_repeat = nothing, choices = nothing, regex = nothing, auto_help::Bool = false, help::AbstractString = "", help_val::Union{Nothing, AbstractString} = nothing)
    collected = _collect_names(names)
    positional = any(!startswith(name, "-") for name in collected)
    option = any(startswith(name, "-") for name in collected)
    if positional && option
        throw(ArgumentError("An argument cannot mix positional and option names"))
    end
    if auto_help
        flag = true
        stop = true
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
    default_length = length(default_values)
    computed_flag_value = flag ? "1" : ""
    repeat_implies_optional = _repeat_allows_zero_min(repeat, min_repeat)
    has_sensible_default = (default_length > 0) || flag || repeat_implies_optional || stop
    if positional && required === false && !has_sensible_default
        throw(ArgumentError("required=false is only supported when the argument is optional by default"))
    end
    if required === nothing
        required_flag = positional ? !has_sensible_default : false
    else
        required_flag = required
    end
    min_occurs, max_occurs = _determine_occurrences(required_flag, repeat, min_repeat, max_repeat)
    if default_length > 0
        if max_occurs != _UNBOUNDED && default_length > max_occurs
            throw(ArgumentError("Default value count exceeds maximum occurrences"))
        end
        if default_length < min_occurs
            throw(ArgumentError("Default value count below minimum occurrences"))
        end
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
    help_string = String(help)
    default_help_val = positional ? uppercase(first(collected)) : "VAL"
    help_val_string = help_val === nothing ? default_help_val : String(help_val)
    return Argument(collected, min_occurs > 0, flag, stop, has_default, default_values, positional, min_occurs, max_occurs, computed_flag_value, choice_values, has_regex, regex_obj, auto_help, help_string, help_val_string)
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
function Command(names, arguments::Vector{Argument}, commands::Vector{Command}; positional_after_first::Bool = false, auto_help::Bool = true, help::AbstractString = "")
    collected = _collect_names(names)
    help_str = String(help)
    base = _construct_command(collected, arguments, commands, positional_after_first, auto_help, help_str)
    return _propagate_auto_help(base, nothing)
end

Command(names, arguments::Vector{Argument}; positional_after_first::Bool = false, auto_help::Bool = true, help::AbstractString = "") =
    Command(names, arguments, Command[]; positional_after_first = positional_after_first, auto_help = auto_help, help = help)
Command(names, commands::Vector{Command}; positional_after_first::Bool = false, auto_help::Bool = true, help::AbstractString = "") =
    Command(names, Argument[], commands; positional_after_first = positional_after_first, auto_help = auto_help, help = help)
Command(names; positional_after_first::Bool = false, auto_help::Bool = true, help::AbstractString = "") =
    Command(names, Argument[]; positional_after_first = positional_after_first, auto_help = auto_help, help = help)

"""
    Command(name::AbstractString, nested::Parser)

Wrap an existing parser so it can be mounted as a sub-command. The nested
parser's arguments and commands are copied into the resulting `Command`.
"""
function Command(name::AbstractString, nested::Parser; positional_after_first::Bool = false)
    return Command(name, nested.arguments, nested.commands; positional_after_first = positional_after_first, auto_help = false, help = nested.help)
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
function Parser(arguments::Vector{Argument}, commands::Vector{Command}; positional_after_first::Bool = false, help::AbstractString = "", help_program::AbstractString = "")
    base = _construct_parser(arguments, commands, positional_after_first, String(help), String(help_program))
    return _propagate_auto_help(base)
end

Parser(arguments::Vector{Argument}; positional_after_first::Bool = false, help::AbstractString = "", help_program::AbstractString = "") =
    Parser(arguments, Command[]; positional_after_first = positional_after_first, help = help, help_program = help_program)
Parser(commands::Vector{Command}; positional_after_first::Bool = false, help::AbstractString = "", help_program::AbstractString = "") =
    Parser(Argument[], commands; positional_after_first = positional_after_first, help = help, help_program = help_program)
Parser(; positional_after_first::Bool = false, help::AbstractString = "", help_program::AbstractString = "") =
    Parser(Argument[]; positional_after_first = positional_after_first, help = help, help_program = help_program)
