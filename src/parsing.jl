# This file implements Cliff's command-line parsing workflow and error handling.

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
    positional_after_first::Bool
    positional_consumed::Bool
end

"""
    ParseError <: Exception

Exception raised when parsing fails.

Fields exposed for diagnostics include:

  * `kind::Symbol` – error classification (:missing_required, :invalid_value,
    etc.).
  * `command::Vector{String}` – command path active when the error occurred.
  * `levels::Vector{LevelResult}` – parser state snapshot, useful for tooling.
  * `argument::Union{Nothing, String}` – offending argument name, if any.
  * `token::Union{Nothing, String}` – input token that triggered the error.
  * `stopped::Bool` / `stop_argument::Union{Nothing, String}` – indicate that a
    stop argument halted parsing before completion.
  * `argv_range::Tuple{Int, Int}` – index range (inclusive) in the argument
    list that pinpoints the error location, or `(0, -1)` when unavailable.
  * `token_range::Tuple{Int, Int}` – character range within the triggering
    token for bundled short options, or `(0, -1)` when not applicable.
  * `actual_occurs::Union{Nothing, Int}` – observed occurrence count when
    validating repetition requirements, if known.
  * `program::String` / `argv::Vector{String}` – captured invocation data used
    to render rich error messages.
"""
struct ParseError <: Exception
    kind::Symbol
    command::Vector{String}
    levels::Vector{LevelResult}
    argument::Union{Nothing, String}
    token::Union{Nothing, String}
    stopped::Bool
    stop_argument::Union{Nothing, String}
    argv_range::Tuple{Int, Int}
    token_range::Tuple{Int, Int}
    actual_occurs::Union{Nothing, Int}
    program::String
    argv::Vector{String}
end

struct _ParseTrace
    program::String
    argv::Vector{String}
end

const _EMPTY_RANGE = (0, -1)

@inline function _normalize_range(range::Union{Nothing, Tuple{Int, Int}, UnitRange{Int}})
    if range === nothing
        return _EMPTY_RANGE
    elseif range isa UnitRange{Int}
        return (first(range), last(range))
    else
        return range
    end
end

@inline _normalize_range(range::Tuple{Int, Int}) = range

@inline function _range_from_index(index::Int)
    return index <= 0 ? _EMPTY_RANGE : (index, index)
end

@inline function _quoted(text::AbstractString)
    return "'" * text * "'"
end

function _join_quoted(values::Vector{String})
    return join([_quoted(value) for value in values], ", ")
end

function _argument_from_error(err::ParseError)
    name = err.argument
    if name === nothing
        return nothing
    end
    for level in err.levels
        idx = get(level.argument_lookup, name, 0)
        if idx != 0
            return level.arguments[idx]
        end
    end
    return nothing
end

@inline function _times_phrase(count::Int)
    return count == 1 ? "1 time" : string(count, " times")
end

function _missing_requirement_message(
        quoted_alias::Union{Nothing, String},
        argument::Union{Nothing, Argument},
        actual_occurs::Union{Nothing, Int},
    )
    if argument === nothing
        if quoted_alias === nothing
            return "missing required argument."
        else
            return "missing required argument $(quoted_alias)."
        end
    end
    subject = quoted_alias === nothing ? "argument" : "argument $(quoted_alias)"
    min_occurs = argument.min_occurs
    max_occurs = argument.max_occurs
    expected = if max_occurs == _UNBOUNDED
        "at least $(_times_phrase(min_occurs))"
    elseif min_occurs == max_occurs
        _times_phrase(min_occurs)
    else
        string(min_occurs, "-", max_occurs, " times")
    end
    if actual_occurs === nothing
        return "$(subject) required $(expected)."
    else
        return "$(subject) required $(expected) but was provided $(_times_phrase(actual_occurs))."
    end
end

function _excess_occurrence_message(
        quoted_alias::Union{Nothing, String},
        argument::Union{Nothing, Argument},
        actual_occurs::Union{Nothing, Int},
    )
    if argument === nothing
        if quoted_alias === nothing
            return actual_occurs === nothing ? "repeated argument." : "repeated argument provided $(_times_phrase(actual_occurs))."
        else
            return actual_occurs === nothing ? "repeated argument $(quoted_alias)." : "repeated argument $(quoted_alias) provided $(_times_phrase(actual_occurs))."
        end
    end
    subject = quoted_alias === nothing ? "argument" : "argument $(quoted_alias)"
    max_occurs = argument.max_occurs
    expected = if argument.min_occurs <= 1
        "at most $(_times_phrase(max_occurs))"
    elseif argument.min_occurs == max_occurs
        _times_phrase(max_occurs)
    else
        string(argument.min_occurs, "-", max_occurs, " times")
    end
    prefix = argument.min_occurs <= 1 ? "expected" : "required"
    if actual_occurs === nothing
        return "$(subject) $(prefix) $(expected)."
    else
        return "$(subject) $(prefix) $(expected) but was provided $(_times_phrase(actual_occurs))."
    end
end

function _invocation_string(err::ParseError)
    parts = String[]
    if !isempty(err.program)
        push!(parts, err.program)
    end
    append!(parts, err.command)
    if err.argv_range != _EMPTY_RANGE
        idx = clamp(err.argv_range[1], 1, length(err.argv))
        if 1 <= idx <= length(err.argv)
            push!(parts, err.argv[idx])
        end
    elseif !isempty(err.argv)
        append!(parts, err.argv)
    end
    if err.kind === :invalid_value && err.token !== nothing
        if isempty(parts) || parts[end] != err.token
            push!(parts, err.token)
        end
    end
    return isempty(parts) ? "" : join(parts, " ")
end

function _describe_parse_error(err::ParseError)
    argument = _argument_from_error(err)
    alias = err.argument
    token = err.token
    quoted_alias = alias === nothing ? nothing : _quoted(alias)
    quoted_token = token === nothing ? nothing : _quoted(token)
    kind = err.kind
    if kind === :missing_required
        return _missing_requirement_message(quoted_alias, argument, err.actual_occurs)
    elseif kind === :invalid_value
        value_part = quoted_token === nothing ? "invalid value" : "invalid value $(quoted_token)"
        if quoted_alias === nothing
            return string(value_part, ".")
        elseif argument !== nothing && !isempty(argument.choices)
            choices = _join_quoted(argument.choices)
            return "$(value_part) for $(quoted_alias); expected one of $(choices)."
        elseif argument !== nothing && argument.has_regex
            return "$(value_part) for $(quoted_alias); expected to match pattern $(argument.regex)."
        else
            return "$(value_part) for $(quoted_alias)."
        end
    elseif kind === :too_many_occurrences
        return _excess_occurrence_message(quoted_alias, argument, err.actual_occurs)
    elseif kind === :unknown_option || kind === :unsupported_short_option
        subject = quoted_token === nothing ? (quoted_alias === nothing ? "argument" : quoted_alias) : quoted_token
        return "invalid argument $(subject)."
    elseif kind === :invalid_option_usage
        return quoted_alias === nothing ? "invalid option usage." : "positional argument $(quoted_alias) cannot be used as an option."
    elseif kind === :flag_value
        name = quoted_alias !== nothing ? quoted_alias : (quoted_token !== nothing ? quoted_token : "argument")
        return "argument $(name) does not take a value."
    elseif kind === :missing_option_value
        name = quoted_alias !== nothing ? quoted_alias : (quoted_token !== nothing ? quoted_token : "option")
        return "missing value for $(name)."
    elseif kind === :unexpected_positional
        return quoted_token === nothing ? "unexpected positional argument." : "unexpected positional argument $(quoted_token)."
    elseif kind === :missing_command
        return "expected a command."
    elseif kind === :missing_subcommand
        return quoted_token === nothing ? "expected a subcommand." : "expected a subcommand for $(quoted_token)."
    elseif kind === :unknown_command
        if isempty(err.command)
            return quoted_token === nothing ? "invalid command." : "invalid command $(quoted_token)."
        else
            return quoted_token === nothing ? "invalid subcommand." : "invalid subcommand $(quoted_token)."
        end
    else
        return string("parse error of kind ", kind, ".")
    end
end

function _render_parse_error(io::IO, err::ParseError)
    invocation = _invocation_string(err)
    description = _describe_parse_error(err)
    if isempty(invocation)
        print(io, description)
    else
        print(io, "In '", invocation, "', ", description)
    end
end

function Base.showerror(io::IO, err::ParseError)
    _render_parse_error(io, err)
end

function _throw_parse_error(trace::_ParseTrace, kind::Symbol, command_path::Vector{String}, levels::Vector{LevelResult};
        argument::Union{Nothing, AbstractString} = nothing,
        token::Union{Nothing, AbstractString} = nothing,
        stopped::Bool = false,
        stop_argument::Union{Nothing, AbstractString} = nothing,
        argv_range::Union{Nothing, Tuple{Int, Int}, UnitRange{Int}} = nothing,
        token_range::Union{Nothing, Tuple{Int, Int}, UnitRange{Int}} = nothing,
        actual_occurs::Union{Nothing, Int} = nothing)
    arg_name = argument === nothing ? nothing : String(argument)
    token_name = token === nothing ? nothing : String(token)
    stop_name = stop_argument === nothing ? nothing : String(stop_argument)
    range_tuple = _normalize_range(argv_range)
    token_tuple = _normalize_range(token_range)
    throw(ParseError(
        kind,
        copy(command_path),
        copy(levels),
        arg_name,
        token_name,
        stopped,
        stop_name,
        range_tuple,
        token_tuple,
        actual_occurs,
        trace.program,
        copy(trace.argv),
    ))
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
    _init_level(arguments, lookup, positional_indices, positional_after_first)

Create a fresh `LevelResult` for a parser level. Called when entering the root
parser and whenever a sub-command is activated. The `positional_after_first`
flag records whether the level should treat subsequent tokens as positional
after consuming the first positional argument.
"""
function _init_level(arguments::Vector{Argument}, lookup::Dict{String, Int}, positional_indices::Vector{Int}, positional_after_first::Bool)
    values = [String[] for _ in arguments]
    counts = fill(0, length(arguments))
    return LevelResult(arguments, lookup, positional_indices, values, counts, positional_after_first, false)
end

"""
    _ensure_required(trace, level, command_path, levels)

Verify that required arguments at a given level have been satisfied. Invoked
after parsing completes (unless halted by a stop argument).
"""
function _ensure_required(trace::_ParseTrace, level::LevelResult, command_path::Vector{String}, levels::Vector{LevelResult})
    for (idx, argument) in enumerate(level.arguments)
        provided = level.counts[idx]
        default_count = (!argument.required && provided == 0) ? length(argument.default) : 0
        total = provided + default_count
        if total < argument.min_occurs
            used_name = first(argument.names)
            _throw_parse_error(
                trace,
                :missing_required,
                command_path,
                levels;
                argument = used_name,
                actual_occurs = total,
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
    _validate_argument_value(trace, argument, value, command_path, levels, argv_index, token_range, alias)

Check `value` against `choices` and `regex` constraints, throwing a `ParseError`
when validation fails. Called for every stored value.
"""
function _validate_argument_value(
        trace::_ParseTrace,
        argument::Argument,
        value::String,
        command_path::Vector{String},
        levels::Vector{LevelResult},
        argv_index::Int,
        token_range::Tuple{Int, Int},
        alias::Union{Nothing, String},
    )
    used_name = alias === nothing ? first(argument.names) : alias
    if !isempty(argument.choices) && !(value in argument.choices)
        valid = join(argument.choices, ", ")
        _throw_parse_error(
            trace,
            :invalid_value,
            command_path,
            levels;
            argument = used_name,
            token = value,
            argv_range = _range_from_index(argv_index),
            token_range = token_range,
        )
    end
    if argument.has_regex && match(argument.regex, value) === nothing
        _throw_parse_error(
            trace,
            :invalid_value,
            command_path,
            levels;
            argument = used_name,
            token = value,
            argv_range = _range_from_index(argv_index),
            token_range = token_range,
        )
    end
    return nothing
end

"""
    _set_value!(trace, level, idx, value, command_path, levels, argv_index, token_range, alias)

Store a value for the argument at `idx`, performing validation and respecting
occurrence limits. Returns `true` when a stop argument halts parsing.
"""
function _set_value!(
        trace::_ParseTrace,
        level::LevelResult,
        idx::Int,
        value::String,
        command_path::Vector{String},
        levels::Vector{LevelResult},
        argv_index::Int,
        token_range::Tuple{Int, Int},
        alias::Union{Nothing, String},
    )
    argument = level.arguments[idx]
    count = level.counts[idx]
    used_name = alias === nothing ? first(argument.names) : alias
    _validate_argument_value(trace, argument, value, command_path, levels, argv_index, token_range, used_name)
    if argument.max_occurs == 1 && count == 1
        level.values[idx][1] = value
        return argument.stop
    elseif argument.max_occurs != _UNBOUNDED && count >= argument.max_occurs
        _throw_parse_error(
            trace,
            :too_many_occurrences,
            command_path,
            levels;
            argument = used_name,
            argv_range = _range_from_index(argv_index),
            token_range = token_range,
            actual_occurs = count + 1,
        )
    end
    push!(level.values[idx], value)
    level.counts[idx] = count + 1
    return argument.stop
end

"""
    _set_flag!(level, idx, command_path, levels)

Specialised wrapper around `_set_value!` for flags. Stores an empty string and
returns whether parsing should stop.
"""
function _set_flag!(
        trace::_ParseTrace,
        level::LevelResult,
        idx::Int,
        command_path::Vector{String},
        levels::Vector{LevelResult},
        argv_index::Int,
        token_range::Tuple{Int, Int},
        alias::Union{Nothing, String},
    )
    return _set_value!(trace, level, idx, "", command_path, levels, argv_index, token_range, alias)
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
            default_count = (!argument.required && provided == 0) ? length(argument.default) : 0
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
    _consume_option!(trace, levels, argv, i, token, command_path)

Handle a long option token (e.g. `--name` or `--name=value`). Consumes any
associated value, updates the active level, and returns the next index plus an
optional stop-argument name.
"""
function _consume_option!(
        trace::_ParseTrace,
        levels::Vector{LevelResult},
        argv::Vector{String},
        i::Int,
        token::String,
        command_path::Vector{String},
    )
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
        range = (firstindex(token), eq_index === nothing ? lastindex(token) : prevind(token, eq_index))
        _throw_parse_error(
            trace,
            :unknown_option,
            command_path,
            levels;
            token = name,
            argv_range = (i, i),
            token_range = range,
        )
    end
    argument = level.arguments[idx]
    if argument.positional
        _throw_parse_error(
            trace,
            :invalid_option_usage,
            command_path,
            levels;
            argument = name,
            token = name,
            argv_range = (i, i),
            token_range = (firstindex(token), lastindex(token)),
        )
    end
    if argument.flag
        if inline_value !== nothing
            _throw_parse_error(
                trace,
                :flag_value,
                command_path,
                levels;
                argument = name,
                token = token,
                argv_range = (i, i),
                token_range = (firstindex(token), lastindex(token)),
            )
        end
        triggered = _set_flag!(trace, level, idx, command_path, levels, i, (firstindex(token), lastindex(token)), name)
        stop_name = triggered ? name : nothing
        return i + 1, stop_name
    end
    if inline_value !== nothing
        triggered = _set_value!(trace, level, idx, inline_value, command_path, levels, i, (firstindex(token), lastindex(token)), name)
        stop_name = triggered ? name : nothing
        return i + 1, stop_name
    end
    next_index = i + 1
    if next_index > length(argv)
        _throw_parse_error(
            trace,
            :missing_option_value,
            command_path,
            levels;
            argument = name,
            token = name,
            argv_range = (i, i),
            token_range = (firstindex(token), lastindex(token)),
        )
    end
    triggered = _set_value!(trace, level, idx, argv[next_index], command_path, levels, i, (firstindex(token), lastindex(token)), name)
    stop_name = triggered ? name : nothing
    return next_index + 1, stop_name
end

"""
    _consume_short_option!(trace, levels, argv, i, token, command_path)

Process short options (tokens beginning with a single `-`). Supports bundled
flags (e.g. `-vvv`), inline values (e.g. `-n3`), and treats forms such as
`-x=3` as the option `-x` with value `"=3"`.
"""
function _consume_short_option!(
        trace::_ParseTrace,
        levels::Vector{LevelResult},
        argv::Vector{String},
        i::Int,
        token::String,
        command_path::Vector{String},
    )
    level = levels[end]
    eq_index = findfirst(==('='), token)
    if eq_index !== nothing
        name_end = prevind(token, eq_index)
        name = token[firstindex(token):name_end]
        idx = _lookup_argument(level, name)
        if idx === nothing
            _throw_parse_error(
                trace,
                :unknown_option,
                command_path,
                levels;
                token = name,
                argv_range = (i, i),
                token_range = (firstindex(token), name_end),
            )
        end
        argument = level.arguments[idx]
        if argument.flag
            _throw_parse_error(
                trace,
                :flag_value,
                command_path,
                levels;
                argument = name,
                token = token,
                argv_range = (i, i),
                token_range = (firstindex(token), lastindex(token)),
            )
        end
        value = token[eq_index:end]
        triggered = _set_value!(trace, level, idx, value, command_path, levels, i, (firstindex(token), name_end), name)
        stop_name = triggered ? name : nothing
        return i + 1, stop_name
    end
    dash_index = firstindex(token)
    char_index = nextind(token, dash_index)
    if char_index > lastindex(token)
        _throw_parse_error(
            trace,
            :unknown_option,
            command_path,
            levels;
            token = token,
            argv_range = (i, i),
            token_range = (firstindex(token), lastindex(token)),
        )
    end
    next_index = nextind(token, char_index)
    name = token[dash_index:prevind(token, next_index)]
    idx = _lookup_argument(level, name)
    if idx === nothing
        _throw_parse_error(
            trace,
            :unknown_option,
            command_path,
            levels;
            token = name,
            argv_range = (i, i),
            token_range = (dash_index, prevind(token, next_index)),
        )
    end
    argument = level.arguments[idx]
    if next_index > lastindex(token)
        if argument.flag
            triggered = _set_flag!(trace, level, idx, command_path, levels, i, (dash_index, prevind(token, next_index)), name)
            stop_name = triggered ? name : nothing
            return i + 1, stop_name
        end
        next_arg_index = i + 1
        if next_arg_index > length(argv)
            _throw_parse_error(
                trace,
                :missing_option_value,
                command_path,
                levels;
                argument = name,
                token = name,
                argv_range = (i, i),
                token_range = (dash_index, prevind(token, next_index)),
            )
        end
        triggered = _set_value!(
            trace,
            level,
            idx,
            argv[next_arg_index],
            command_path,
            levels,
            i,
            (dash_index, prevind(token, next_index)),
            name,
        )
        stop_name = triggered ? name : nothing
        return next_arg_index + 1, stop_name
    end
    if argument.flag
        stop_name = nothing
        triggered = _set_flag!(trace, level, idx, command_path, levels, i, (dash_index, prevind(token, next_index)), name)
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
                _throw_parse_error(
                    trace,
                    :unknown_option,
                    command_path,
                    levels;
                    token = rest_name,
                    argv_range = (i, i),
                    token_range = (rest_index, prevind(token, char_end)),
                )
            end
            rest_argument = level.arguments[rest_idx]
            if !rest_argument.flag
                _throw_parse_error(
                    trace,
                    :unsupported_short_option,
                    command_path,
                    levels;
                    argument = rest_name,
                    token = rest_name,
                    argv_range = (i, i),
                    token_range = (rest_index, prevind(token, char_end)),
                )
            end
            triggered = _set_flag!(trace, level, rest_idx, command_path, levels, i, (rest_index, prevind(token, char_end)), rest_name)
            if triggered
                stop_name = rest_name
            end
            rest_index = char_end
        end
        return i + 1, stop_name
    end
    value = token[next_index:end]
    triggered = _set_value!(trace, level, idx, value, command_path, levels, i, (dash_index, prevind(token, next_index)), name)
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
    trace = _ParseTrace(_help_program_placeholder(parser), copy(argv))
    levels = LevelResult[]
    push!(levels, _init_level(parser.arguments, parser.argument_lookup, parser.positional_indices, parser.positional_after_first))
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
        level = levels[end]
        positional_lock = level.positional_after_first && level.positional_consumed
        if allow_options && token == "--"
            allow_options = false
            i += 1
            continue
        end
        cmd_idx = positional_lock ? 0 : get(current.command_lookup, token, 0)
        if cmd_idx != 0 && !_has_outstanding_required(level)
            command_satisfied[end] = true
            next_command = current.commands[cmd_idx]
            current = next_command
            push!(command_path, token)
            push!(levels, _init_level(next_command.arguments, next_command.argument_lookup, next_command.positional_indices, next_command.positional_after_first))
            push!(positional_cursors, 1)
            allow_options = true
            push!(command_requirements, !isempty(next_command.commands))
            push!(command_satisfied, false)
            push!(level_labels, token)
            push!(level_is_root, false)
            i += 1
            continue
        end
        positional_lock = level.positional_after_first && level.positional_consumed
        if allow_options && !positional_lock && startswith(token, "--") && token != "--"
            i, stop_name = _consume_option!(trace, levels, argv, i, token, command_path)
            if stop_name !== nothing
                stopped = true
                if stop_argument === nothing
                    stop_argument = stop_name
                end
                break
            end
            continue
        elseif allow_options && !positional_lock && startswith(token, "-") && token != "-"
            i, stop_name = _consume_short_option!(trace, levels, argv, i, token, command_path)
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
            if !isempty(current.commands) && !_has_outstanding_required(level)
                _throw_parse_error(
                    trace,
                    :unknown_command,
                    command_path,
                    levels;
                    token = token,
                    argv_range = (i, i),
                    token_range = (firstindex(token), lastindex(token)),
                )
            end
            _throw_parse_error(
                trace,
                :unexpected_positional,
                command_path,
                levels;
                token = token,
                argv_range = (i, i),
                token_range = (firstindex(token), lastindex(token)),
            )
        end
        argument = level.arguments[positional_index]
        triggered = _set_value!(trace, level, positional_index, token, command_path, levels, i, (firstindex(token), lastindex(token)), first(argument.names))
        if level.positional_after_first && !level.positional_consumed
            level.positional_consumed = true
        end
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
            _ensure_required(trace, level, command_path, levels)
        end
        for idx in eachindex(command_requirements)
            if command_requirements[idx] && !command_satisfied[idx]
                label = level_labels[idx]
                is_root = level_is_root[idx]
                kind = is_root ? :missing_command : :missing_subcommand
                _throw_parse_error(
                    trace,
                    kind,
                    command_path,
                    levels;
                    token = label,
                    argv_range = _EMPTY_RANGE,
                )
            end
        end
    end
    command_copy = copy(command_path)
    stop_name = stop_argument === nothing ? nothing : String(stop_argument)
    return Parsed(command_copy, levels, true, !stopped, nothing, stopped, stop_name)
end

function _find_auto_help_stop_level(levels::Vector{LevelResult}, stop_argument::Union{Nothing, String})
    if stop_argument === nothing
        return nothing
    end
    for (level_idx, level) in enumerate(levels)
        for (arg_idx, argument) in enumerate(level.arguments)
            if argument.auto_help && (stop_argument in argument.names) && level.counts[arg_idx] > 0
                return level_idx
            end
        end
    end
    return nothing
end

function _help_program_placeholder(parser::Parser)
    if !isempty(parser.help_program)
        return parser.help_program
    end
    program_file = nothing
    if isdefined(Base, :PROGRAM_FILE)
        raw_file = getfield(Base, :PROGRAM_FILE)
        if raw_file isa AbstractString && !isempty(raw_file)
            program_file = Base.basename(String(raw_file))
        end
    end
    program_name = nothing
    if isdefined(Base, :PROGRAM_NAME)
        raw_name = getfield(Base, :PROGRAM_NAME)
        if raw_name isa AbstractString && !isempty(raw_name)
            program_name = Base.basename(String(raw_name))
        end
    end
    if program_name === nothing
        cmd = Base.julia_cmd()
        if !isempty(cmd.exec)
            exec = cmd.exec[1]
            if exec isa AbstractString && !isempty(exec)
                program_name = Base.basename(String(exec))
            end
        end
    end
    if program_name !== nothing && program_file !== nothing
        return string(program_name, ' ', program_file)
    elseif program_name !== nothing
        return program_name
    elseif program_file !== nothing
        return program_file
    else
        return "<program>"
    end
end

function _resolve_help_target(parser::Parser, command_path::Vector{String}, depth::Int)
    usage = String[_help_program_placeholder(parser)]
    if depth <= 1
        return parser, usage
    end
    current = parser
    limit = min(depth - 1, length(command_path))
    for idx in 1:limit
        name = command_path[idx]
        cmd_idx = get(current.command_lookup, name, 0)
        if cmd_idx == 0
            return current, usage
        end
        command = current.commands[cmd_idx]
        push!(usage, first(command.names))
        if idx == depth - 1
            return command, usage
        end
        current = command
    end
    return current, usage
end

function _usage_segments(target::Union{Parser, Command}, usage_path::Vector{String})
    segments = copy(usage_path)
    if any(!argument.positional for argument in target.arguments)
        push!(segments, "[options]")
    end
    for argument in target.arguments
        if argument.positional
            push!(segments, argument.help_val)
        end
    end
    if !isempty(target.commands)
        push!(segments, "COMMAND ...")
    end
    return segments
end

function _parsed_help(text::String)
    return isempty(text) ? nothing : Markdown.parse(text)
end

function _append_help_blocks!(blocks::Vector{Any}, text::String)
    help_md = _parsed_help(text)
    if help_md !== nothing
        append!(blocks, help_md.content)
    end
    return nothing
end

function _inline_code_list(strings::Vector{String})
    nodes = Any[]
    for (idx, value) in enumerate(strings)
        push!(nodes, Markdown.Code("", value))
        if idx < length(strings)
            push!(nodes, ", ")
        end
    end
    return nodes
end

function _option_display_names(argument::Argument)
    if argument.flag
        return argument.names
    else
        return [string(name, " ", argument.help_val) for name in argument.names]
    end
end

function _option_inline_nodes(argument::Argument)
    return _inline_code_list(_option_display_names(argument))
end

function _positional_inline_nodes(argument::Argument)
    return Any[Markdown.Code("", argument.help_val)]
end

function _command_section_blocks(commands::Vector{Command})
    entries = Any[]
    for command in commands
        push!(entries, Markdown.Paragraph(_inline_code_list(command.names)))
        help_md = _parsed_help(command.help)
        if help_md !== nothing
            push!(entries, Markdown.BlockQuote(help_md.content))
        end
    end
    if isempty(entries)
        return Any[]
    end
    return vcat(Any[Markdown.Header("Commands", 2)], entries)
end

function _argument_section_blocks(arguments::Vector{Argument}, predicate::Function, title::String, inline_builder::Function)
    entries = Any[]
    for argument in arguments
        if predicate(argument)
            push!(entries, Markdown.Paragraph(inline_builder(argument)))
            help_md = _parsed_help(argument.help)
            if help_md !== nothing
                push!(entries, Markdown.BlockQuote(help_md.content))
            end
        end
    end
    if isempty(entries)
        return Any[]
    end
    return vcat(Any[Markdown.Header(title, 2)], entries)
end

function _print_basic_help(io::IO, parser::Parser, parsed::Parsed, depth::Int)
    target, usage_path = _resolve_help_target(parser, parsed.command, depth)
    usage_line = join(_usage_segments(target, usage_path), " ")
    content = Any[]
    push!(content, Markdown.Paragraph([Markdown.Code("", usage_line)]))
    _append_help_blocks!(content, target.help)
    append!(content, _command_section_blocks(target.commands))
    append!(content, _argument_section_blocks(target.arguments, argument -> argument.positional, "Arguments", _positional_inline_nodes))
    append!(content, _argument_section_blocks(target.arguments, argument -> !argument.positional, "Options", _option_inline_nodes))
    md = Markdown.MD(content)
    show(io, MIME"text/plain"(), md)
    println(io)
    return nothing
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
        result = _execute_parse(parser, argv)
        if result.stopped
            depth = _find_auto_help_stop_level(result.levels, result.stop_argument)
            if depth !== nothing && error_mode === :exit
                _print_basic_help(io, parser, result, depth)
                exit(0)
            end
        end
        return result
    catch err
        if err isa ParseError
            parsed = Parsed(err.command, err.levels, false, false, err, err.stopped, err.stop_argument)
            if error_mode === :throw
                throw(err)
            elseif error_mode === :return
                return parsed
            else
                _render_parse_error(io, err)
                println(io)
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


