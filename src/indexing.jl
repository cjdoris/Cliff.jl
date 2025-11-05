# This file provides indexing and retrieval utilities for Parsed results.

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

