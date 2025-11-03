module Cliff

export Argument, Command, Parser, Parsed

"""Represents an argument (positional, option, or flag)."""
struct Argument
    names::Vector{String}
    required::Bool
    flag::Bool
    has_default::Bool
    default::String
    positional::Bool
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
    values::Vector{String}
    provided::BitVector
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

function Argument(names...; required::Bool = false, default = nothing, flag::Bool = false)
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
    default_value = has_default ? string(default) : ""
    if flag
        default_value = has_default ? string(default) : "false"
    end
    return Argument(collected, required, flag, has_default, default_value, positional)
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

function _initial_values(arguments::Vector{Argument})
    values = String[]
    provided = BitVector(undef, length(arguments))
    fill!(provided, false)
    for argument in arguments
        if argument.flag
            push!(values, argument.has_default ? argument.default : "false")
        elseif argument.has_default
            push!(values, argument.default)
        else
            push!(values, "")
        end
    end
    return values, provided
end

function _init_level(arguments::Vector{Argument}, lookup::Dict{String, Int}, positional_indices::Vector{Int})
    values, provided = _initial_values(arguments)
    return LevelResult(arguments, lookup, positional_indices, values, provided)
end

function _ensure_required(level::LevelResult)
    for (idx, argument) in enumerate(level.arguments)
        if argument.required && !level.provided[idx] && !argument.has_default
            throw(ArgumentError("Missing required argument: $(first(argument.names))"))
        end
    end
end

function _lookup_argument(level::LevelResult, name::String)
    idx = get(level.argument_lookup, name, 0)
    return idx == 0 ? nothing : idx
end

function _set_value!(level::LevelResult, idx::Int, value::String)
    level.values[idx] = value
    level.provided[idx] = true
    return nothing
end

function _set_flag!(level::LevelResult, idx::Int)
    _set_value!(level, idx, "true")
end

function _next_positional_index(level::LevelResult, cursor::Int)
    if cursor > length(level.positional_indices)
        return nothing
    end
    return level.positional_indices[cursor]
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
    while i <= length(argv)
        token = argv[i]
        if allow_options && token == "--"
            allow_options = false
            i += 1
            continue
        end
        level = levels[end]
        cmd_idx = get(current.command_lookup, token, 0)
        if cmd_idx != 0
            current = current.commands[cmd_idx]
            push!(command_path, token)
            push!(levels, _init_level(current.arguments, current.argument_lookup, current.positional_indices))
            push!(positional_cursors, 1)
            allow_options = true
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
        positional_index = _next_positional_index(level, positional_cursors[end])
        if positional_index === nothing
            throw(ArgumentError("Unexpected positional argument: $(token)"))
        end
        argument = level.arguments[positional_index]
        _set_value!(level, positional_index, token)
        positional_cursors[end] += 1
        i += 1
    end
    for level in levels
        _ensure_required(level)
    end
    return Parsed(command_path, levels)
end

function (parser::Parser)(argv::AbstractVector{<:AbstractString})
    return parse(parser, String.(collect(argv)))
end

function (parser::Parser)()
    return parse(parser, copy(ARGS))
end

function Base.getindex(parsed::Parsed, name::String)
    for idx in Iterators.reverse(eachindex(parsed.levels))
        level = parsed.levels[idx]
        position = _lookup_argument(level, name)
        if position !== nothing
            return level.values[position]
        end
    end
    throw(KeyError(name))
end

function Base.getindex(parsed::Parsed, name::String, depth::Integer)
    if depth < 0 || depth + 1 > length(parsed.levels)
        throw(ArgumentError("Invalid depth: $(depth)"))
    end
    level = parsed.levels[depth + 1]
    idx = _lookup_argument(level, name)
    if idx === nothing
        throw(KeyError(name))
    end
    return level.values[idx]
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

function Base.getindex(parsed::Parsed, ::Type{T}, name::String) where {T}
    value = parsed[name]
    return _convert_value(T, value)
end

function Base.getindex(parsed::Parsed, ::Type{T}, name::String, depth::Integer) where {T}
    value = parsed[name, depth]
    return _convert_value(T, value)
end

end # module
