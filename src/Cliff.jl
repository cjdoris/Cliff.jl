module Cliff

export Argument, Command, Parser, Parsed

"""Represents an argument (positional, option, or flag)."""
struct Argument
    names::Vector{String}
    required::Bool
    flag::Bool
    has_default::Bool
    default::Vector{String}
    positional::Bool
    min_occurs::Int
    max_occurs::Int
end

"""Represents a command with its own arguments and sub-commands."""
struct Command
    names::Vector{String}
    arguments::Vector{Argument}
    commands::Vector{Command}
    usages::Vector{String}
    argument_lookup::Dict{String, Int}
    positional_indices::Vector{Int}
    command_lookup::Dict{String, Int}
end

"""Top-level parser."""
struct Parser
    name::String
    arguments::Vector{Argument}
    commands::Vector{Command}
    usages::Vector{String}
    argument_lookup::Dict{String, Int}
    positional_indices::Vector{Int}
    command_lookup::Dict{String, Int}
end

mutable struct LevelResult
    arguments::Vector{Argument}
    argument_lookup::Dict{String, Int}
    positional_indices::Vector{Int}
    values::Vector{Vector{String}}
    counts::Vector{Int}
end

"""Parsed result returned by running a parser."""
struct Parsed
    command::Vector{String}
    levels::Vector{LevelResult}
end

# Internal helpers

function _collect_names(names...)
    collected = String[]
    seen = Dict{String, Bool}()
    for name in names
        if name isa AbstractString
            _push_name!(collected, seen, String(name))
        elseif name isa AbstractVector{<:AbstractString}
            for item in name
                _push_name!(collected, seen, String(item))
            end
        else
            throw(ArgumentError("Argument names must be strings"))
        end
    end
    if isempty(collected)
        throw(ArgumentError("At least one name must be provided"))
    end
    return collected
end

function _push_name!(collected::Vector{String}, seen::Dict{String, Bool}, name::String)
    if haskey(seen, name)
        throw(ArgumentError("Duplicate name: $(name)"))
    end
    push!(collected, name)
    seen[name] = true
    return nothing
end

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

function _build_positional_indices(arguments::Vector{Argument})
    indices = Int[]
    for (idx, argument) in enumerate(arguments)
        if argument.positional
            push!(indices, idx)
        end
    end
    return indices
end

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

function _normalize_repeat_value(value, name::String)
    if !(value isa Integer) || value < 0
        throw(ArgumentError("$(name) must be a non-negative integer"))
    end
    return Int(value)
end

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

function _determine_occurrences(required::Bool, repeat, min_repeat, max_repeat)
    min_occurs = required ? 1 : 0
    max_occurs = 1
    if repeat !== nothing && (min_repeat !== nothing || max_repeat !== nothing)
        throw(ArgumentError("Cannot specify repeat together with min_repeat or max_repeat"))
    end
    if repeat !== nothing
        min_occurs, max_occurs = _normalize_repeat_spec(repeat)
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

function Argument(names...; required::Bool = false, default = nothing, flag::Bool = false, repeat = nothing, min_repeat = nothing, max_repeat = nothing)
    collected = _collect_names(names...)
    positional = any(!startswith(name, "-") for name in collected)
    option = any(startswith(name, "-") for name in collected)
    if positional && option
        throw(ArgumentError("An argument cannot mix positional and option names"))
    end
    if flag && positional
        throw(ArgumentError("Flags must use option-style names"))
    end
    has_default = default !== nothing
    default_values = String[]
    if has_default
        if default isa AbstractVector
            default_values = String.(default)
        else
            push!(default_values, string(default))
        end
    end
    min_occurs, max_occurs = _determine_occurrences(required, repeat, min_repeat, max_repeat)
    if has_default && max_occurs != _UNBOUNDED && length(default_values) > max_occurs
        throw(ArgumentError("Default value count exceeds maximum occurrences"))
    end
    return Argument(collected, min_occurs > 0, flag, has_default, default_values, positional, min_occurs, max_occurs)
end

function Command(names...; arguments = Argument[], commands = Command[], usages = String[])
    collected = _collect_names(names...)
    args_vec = Vector{Argument}(arguments)
    cmds_vec = Vector{Command}(commands)
    usages_vec = String.(usages)
    argument_lookup = _build_argument_lookup(args_vec)
    positional_indices = _build_positional_indices(args_vec)
    command_lookup = _build_command_lookup(cmds_vec)
    return Command(collected, args_vec, cmds_vec, usages_vec, argument_lookup, positional_indices, command_lookup)
end

function Parser(; name::AbstractString = "", arguments = Argument[], commands = Command[], usages = String[])
    args_vec = Vector{Argument}(arguments)
    cmds_vec = Vector{Command}(commands)
    usages_vec = String.(usages)
    argument_lookup = _build_argument_lookup(args_vec)
    positional_indices = _build_positional_indices(args_vec)
    command_lookup = _build_command_lookup(cmds_vec)
    return Parser(String(name), args_vec, cmds_vec, usages_vec, argument_lookup, positional_indices, command_lookup)
end

function _init_level(arguments::Vector{Argument}, lookup::Dict{String, Int}, positional_indices::Vector{Int})
    values = [String[] for _ in arguments]
    counts = fill(0, length(arguments))
    return LevelResult(arguments, lookup, positional_indices, values, counts)
end

function _ensure_required(level::LevelResult)
    for (idx, argument) in enumerate(level.arguments)
        provided = level.counts[idx]
        default_count = (argument.has_default && provided == 0) ? length(argument.default) : 0
        total = provided + default_count
        if total < argument.min_occurs
            throw(ArgumentError("Missing required argument: $(first(argument.names))"))
        end
    end
end

function _lookup_argument(level::LevelResult, name::String)
    idx = get(level.argument_lookup, name, 0)
    return idx == 0 ? nothing : idx
end

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

function _argument_values(level::LevelResult, idx::Int)
    argument = level.arguments[idx]
    stored = level.values[idx]
    if !isempty(stored)
        return copy(stored)
    elseif argument.has_default
        return copy(argument.default)
    elseif argument.flag
        return String["false"]
    else
        return String[]
    end
end

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
        return "false"
    else
        return ""
    end
end

function _set_value!(level::LevelResult, idx::Int, value::String)
    argument = level.arguments[idx]
    count = level.counts[idx]
    if argument.max_occurs == 1 && count == 1
        level.values[idx][1] = value
        return nothing
    elseif argument.max_occurs != _UNBOUNDED && count >= argument.max_occurs
        throw(ArgumentError("Argument $(first(argument.names)) cannot be provided more than $(argument.max_occurs) times"))
    end
    push!(level.values[idx], value)
    level.counts[idx] = count + 1
    return nothing
end

function _set_flag!(level::LevelResult, idx::Int)
    _set_value!(level, idx, "true")
end

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

function _consume_option!(levels::Vector{LevelResult}, argv::Vector{String}, i::Int, token::String)
    level = levels[end]
    eq_index = findfirst(==('='), token)
    name = token
    inline_value = nothing
    if eq_index !== nothing
        name = token[1:eq_index - 1]
        inline_value = token[eq_index + 1:end]
    end
    idx = _lookup_argument(level, name)
    if idx === nothing
        throw(ArgumentError("Unknown option: $(name)"))
    end
    argument = level.arguments[idx]
    if argument.positional
        throw(ArgumentError("Positional argument $(first(argument.names)) cannot be used as an option"))
    end
    if argument.flag
        if inline_value !== nothing
            throw(ArgumentError("Flag $(name) does not accept a value"))
        end
        _set_flag!(level, idx)
        return i + 1
    end
    if inline_value !== nothing
        _set_value!(level, idx, inline_value)
        return i + 1
    end
    next_index = i + 1
    if next_index > length(argv)
        throw(ArgumentError("Option $(name) requires a value"))
    end
    _set_value!(level, idx, argv[next_index])
    return next_index + 1
end

function _consume_short_option!(levels::Vector{LevelResult}, argv::Vector{String}, i::Int, token::String)
    level = levels[end]
    if length(token) == 2
        name = token
        idx = _lookup_argument(level, name)
        if idx === nothing
            throw(ArgumentError("Unknown option: $(name)"))
        end
        argument = level.arguments[idx]
        if argument.flag
            _set_flag!(level, idx)
            return i + 1
        end
        next_index = i + 1
        if next_index > length(argv)
            throw(ArgumentError("Option $(name) requires a value"))
        end
        _set_value!(level, idx, argv[next_index])
        return next_index + 1
    end
    eq_index = findfirst(==('='), token)
    if eq_index === nothing
        throw(ArgumentError("Unsupported short option bundle: $(token)"))
    end
    name = token[1:eq_index - 1]
    value = token[eq_index + 1:end]
    idx = _lookup_argument(level, name)
    if idx === nothing
        throw(ArgumentError("Unknown option: $(name)"))
    end
    argument = level.arguments[idx]
    if argument.flag
        throw(ArgumentError("Flag $(name) does not accept a value"))
    end
    _set_value!(level, idx, value)
    return i + 1
end

function parse(parser::Parser, argv::Vector{String})
    levels = LevelResult[]
    push!(levels, _init_level(parser.arguments, parser.argument_lookup, parser.positional_indices))
    positional_cursors = Int[1]
    command_path = String[]
    current = parser
    i = 1
    allow_options = true
    command_requirements = Bool[!isempty(parser.commands)]
    command_satisfied = Bool[false]
    level_labels = String[parser.name == "" ? "parser" : parser.name]
    level_is_root = Bool[true]
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
            i = _consume_option!(levels, argv, i, token)
            continue
        elseif allow_options && startswith(token, "-") && token != "-"
            i = _consume_short_option!(levels, argv, i, token)
            continue
        end
        positional_index, cursor_position = _next_positional_index(level, positional_cursors[end])
        if positional_index === nothing
            throw(ArgumentError("Unexpected positional argument: $(token)"))
        end
        argument = level.arguments[positional_index]
        _set_value!(level, positional_index, token)
        if argument.max_occurs != _UNBOUNDED && level.counts[positional_index] >= argument.max_occurs
            positional_cursors[end] = cursor_position + 1
        else
            positional_cursors[end] = cursor_position
        end
        i += 1
    end
    for level in levels
        _ensure_required(level)
    end
    for idx in eachindex(command_requirements)
        if command_requirements[idx] && !command_satisfied[idx]
            label = level_labels[idx]
            is_root = level_is_root[idx]
            message = is_root ? "Expected a command" : "Expected a sub-command for $(label)"
            throw(ArgumentError(message))
        end
    end
    return Parsed(command_path, levels)
end

function (parser::Parser)(argv::AbstractVector{<:AbstractString})
    return parse(parser, String.(collect(argv)))
end

function (parser::Parser)()
    return parse(parser, copy(ARGS))
end

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

_convert_value(::Type{String}, value::String) = value

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

function Base.getindex(args::Parsed, name::String, depth::Integer, ::Type{T}) where {T}
    value = args[name, depth]
    return _convert_value(T, value)
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
