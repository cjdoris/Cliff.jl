# This file provides indexing and retrieval utilities for Parsed results.

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
    elseif !argument.required
        return copy(argument.default)
    else
        return String[]
    end
end

"""
    _resolve_level(args, depth)

Validate and return the `LevelResult` for `depth`, using zero-based indexing to
mirror the public API. Raises an `ArgumentError` when the depth is invalid.
"""
function _resolve_level(args::Parsed, depth::Integer)
    if depth < 0 || depth >= length(args.levels)
        throw(ArgumentError("Invalid depth: $(depth)"))
    end
    return args.levels[depth + 1]
end

"""
    _resolve_depth(args, name)

Locate the depth where `name` is defined, searching from the innermost level to
the outermost. Throws `KeyError` if the argument is unknown.
"""
function _resolve_depth(args::Parsed, name::String)
    for (depth, level) in Iterators.reverse(enumerate(args.levels))
        if _lookup_argument(level, name) !== nothing
            return depth - 1
        end
    end
    throw(KeyError(name))
end

function _single_string(level::LevelResult, idx::Int, values::Vector{String})
    argument = level.arguments[idx]
    if argument.max_occurs != 1
        throw(ArgumentError("Argument $(first(argument.names)) accepts multiple values; use args[name, Vector] instead"))
    end
    if isempty(values)
        throw(ArgumentError("Argument $(first(argument.names)) was not provided"))
    end
    return values[1]
end

function _convert_argument(::Type{String}, level::LevelResult, idx::Int, values::Vector{String})
    return _single_string(level, idx, values)
end

function _convert_argument(::Type{Union{T, Nothing}}, level::LevelResult, idx::Int, values::Vector{String}) where {T}
    argument = level.arguments[idx]
    if argument.max_occurs != 1
        throw(ArgumentError("Argument $(first(argument.names)) accepts multiple values; use args[name, Vector] instead"))
    end
    if isempty(values)
        return nothing
    end
    if argument.flag && T === Bool
        return true
    end
    return _convert_value(T, values[1])
end

function _convert_argument(::Type{Bool}, level::LevelResult, idx::Int, values::Vector{String})
    argument = level.arguments[idx]
    if argument.flag
        if argument.max_occurs != 1
            throw(ArgumentError("Argument $(first(argument.names)) accepts multiple values; use args[name, Vector] instead"))
        end
        return !isempty(values)
    end
    string_value = _single_string(level, idx, values)
    return _convert_value(Bool, string_value)
end

function _convert_argument(::Type{Int}, level::LevelResult, idx::Int, values::Vector{String})
    argument = level.arguments[idx]
    if argument.flag
        return level.counts[idx]
    end
    string_value = _single_string(level, idx, values)
    return _convert_value(Int, string_value)
end

function _convert_argument(::Type{Vector{T}}, level::LevelResult, idx::Int, values::Vector{String}) where {T}
    argument = level.arguments[idx]
    if argument.flag && T === Bool
        return fill(true, length(values))
    end
    converted = Vector{T}(undef, length(values))
    for (i, value) in enumerate(values)
        converted[i] = _convert_value(T, value)
    end
    return converted
end

function _convert_argument(::Type{T}, level::LevelResult, idx::Int, values::Vector{String}) where {T}
    string_value = _single_string(level, idx, values)
    return _convert_value(T, string_value)
end

"""
    Base.getindex(args::Parsed, name)

Retrieve values from a `Parsed` object. Supports optional `depth` arguments to
disambiguate commands and typed lookups such as `args[name, Int]` or
`args[name, Vector{T}]`. Flags store empty strings for each occurrence, while
integer lookups yield occurrence counts.
"""
Base.getindex(args::Parsed, name::String) = args[name, String]

Base.getindex(args::Parsed, name::String, depth::Integer) = args[name, depth, String]

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
    depth = _resolve_depth(args, name)
    return args[name, depth, T]
end

function Base.getindex(args::Parsed, name::String, depth::Integer, ::Type{T}) where {T}
    level = _resolve_level(args, depth)
    idx = _lookup_argument(level, name)
    if idx === nothing
        throw(KeyError(name))
    end
    values = _argument_values(level, idx)
    return _convert_argument(T, level, idx, values)
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

function Base.getindex(args::Parsed, name::String, ::typeof(-))
    return args[name, Union{String, Nothing}]
end

function Base.getindex(args::Parsed, name::String, depth::Integer, ::typeof(-))
    return args[name, depth, Union{String, Nothing}]
end

function Base.getindex(args::Parsed, name::String, ::Type{T}, ::typeof(-)) where {T}
    return args[name, Union{T, Nothing}]
end

function Base.getindex(args::Parsed, name::String, depth::Integer, ::Type{T}, ::typeof(-)) where {T}
    return args[name, depth, Union{T, Nothing}]
end

