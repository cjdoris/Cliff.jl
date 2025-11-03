# Agent Instructions for Cliff.jl

## Scope
This file applies to the entire repository.

## Coding Guidelines
- Follow the user requirements provided in the root prompt, including maintaining type stability and keeping structs non-parameterized.
- Do not introduce functionality beyond what is explicitly requested.
- Keep `AGENTS.md`, `.gitignore`, `README.md`, and the test suite up to date with changes.
- Respect Julia style conventions (use 4-space indentation, descriptive function names, and avoid unnecessary type assertions).
- Do not auto-generate usage strings from the parser.
- Support `--` to disable option parsing while still allowing sub-command detection.
- Flags should be retrievable via `parsed[Bool, "--flag-name"]`.

## Testing
- Provide and maintain tests in `test/runtests.jl`.
- Tests must cover parsing of positional arguments, options, flags, nested commands, `--` handling, and typed retrieval.

## Tooling
- After any `Pkg` modification, run `Pkg.precompile(strict=true, timing=true)`.

