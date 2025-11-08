using Test
using Cliff

@testset "Argument construction" begin
    arg = Argument(["--name", "-n"]; default = "guest")
    @test !arg.flag
    @test arg.names == ["--name", "-n"]
    @test arg.default == ["guest"]
    @test arg.has_default
    @test arg.min_occurs == 0
    @test !arg.positional

    flag = Argument("--verbose"; flag = true)
    @test flag.flag
    @test !flag.has_default
    @test flag.default == String[]
    @test flag.flag_value == "1"

    @test_throws ArgumentError Argument("--answer"; flag = true, default = "0")
    @test_throws ArgumentError Argument("value"; flag_value = "on")

    repeat_flag = Argument("--verbose"; flag = true, repeat = true)
    @test repeat_flag.min_occurs == 0
    @test repeat_flag.max_occurs == typemax(Int)

    repeat_values = Argument("item"; repeat = true)
    @test repeat_values.min_occurs == 0
    @test repeat_values.max_occurs == typemax(Int)

    required_repeat_flag = Argument("--debug"; flag = true, required = true, repeat = true)
    @test required_repeat_flag.min_occurs == 1
    @test required_repeat_flag.max_occurs == typemax(Int)

    repeat_range_optional = Argument("range"; repeat = 0:3, required = false)
    @test repeat_range_optional.min_occurs == 0
    @test repeat_range_optional.max_occurs == 3

    repeat_tuple_optional = Argument("tuple"; repeat = (0, 2), required = false)
    @test repeat_tuple_optional.min_occurs == 0
    @test repeat_tuple_optional.max_occurs == 2

    min_repeat_optional = Argument("min"; min_repeat = 0, required = false)
    @test min_repeat_optional.min_occurs == 0

    choice_arg = Argument("mode"; choices = ["fast", "slow"], default = "fast")
    @test choice_arg.choices == ["fast", "slow"]
    @test !choice_arg.has_regex

    regex_arg = Argument("--slug"; regex = r"^[a-z]+$", default = "slug", required = false)
    @test regex_arg.has_regex
    @test regex_arg.regex isa Regex

    stop_arg = Argument("--help"; stop = true)
    @test stop_arg.min_occurs == 0
    @test !stop_arg.required

    auto_help_arg = Argument("--help"; auto_help = true)
    @test auto_help_arg.auto_help
    @test auto_help_arg.flag
    @test auto_help_arg.stop

    numeric_default = Argument("--count"; default = 5)
    @test numeric_default.default == ["5"]

    vector_default = Argument("--numbers"; repeat = true, default = [1, "two", 3.5])
    @test vector_default.default == ["1", "two", "3.5"]

    positional_help = Argument("input")
    @test positional_help.help == ""
    @test positional_help.help_val == "INPUT"

    option_help = Argument(["--output", "-o"])
    @test option_help.help_val == "VAL"

    custom_help = Argument("path"; help = "Select the path.", help_val = "FILE")
    @test custom_help.help == "Select the path."
    @test custom_help.help_val == "FILE"

    valid_flag_choices = Argument("--toggle"; flag = true, choices = ["0", "1"])
    @test valid_flag_choices.flag
    @test valid_flag_choices.flag_value == "1"
    @test_throws ArgumentError Argument("--broken"; flag = true, choices = ["1"])
    @test_throws ArgumentError Argument("--badregex"; flag = true, regex = r"^1$")

    @test_throws ArgumentError Argument("value"; required = false)
    @test_throws ArgumentError Argument("mode"; choices = String[])
    @test_throws ArgumentError Argument("mode"; choices = ["fast"], default = "slow")
    @test_throws ArgumentError Argument(["-help"])
    @test_throws ArgumentError Argument(["--flag", "-ab"])
    @test_throws ArgumentError Argument("--slug"; regex = r"^[a-z]+$", default = "UPPER")
    @test_throws ArgumentError Argument(["--flag", 42])
    @test_throws ArgumentError Argument(42)
    @test_throws ArgumentError Argument(String[])
    @test_throws ArgumentError Argument("neg-min"; min_repeat = -1)
    @test_throws ArgumentError Argument("neg-max"; max_repeat = -1)
    @test_throws ArgumentError Argument("bad-max"; max_repeat = :invalid)
    @test_throws ArgumentError Argument("neg-repeat"; repeat = -1)
    @test_throws ArgumentError Argument("step-repeat"; repeat = 0:2:4)
    @test_throws ArgumentError Argument("decreasing-repeat"; repeat = 2:1)
    @test_throws ArgumentError Argument("float-repeat"; repeat = 0:1:1.5)
    @test_throws ArgumentError Argument("too-many-defaults"; max_repeat = 1, default = ["a", "b"])
end

@testset "Basic parsing" begin
    parser = Parser([
        Argument("input"),
        Argument("output"; default = "out.txt")
    ], [
        Command("run", [
            Argument("task"),
            Argument(["--threads", "-t"]; default = "1"),
            Argument("--verbose"; flag = true)
        ], [
            Command("fast", [Argument("--limit"; default = "10")])
        ])
    ])

    args = parser(["input.txt", "run", "build", "--threads", "4", "--verbose", "fast", "--limit", "20"]; error_mode = :throw)

    @test args.command == ["run", "fast"]
    @test args["input"] == "input.txt"
    @test args["output"] == "out.txt"
    @test args["task"] == "build"
    @test args["--threads", String] == "4"
    @test args["--threads", Int] == 4
    @test args["--verbose", Bool]
    @test args["--limit"] == "20"
    @test args["--limit", 2, String] == "20"
    @test args["input", 0, String] == "input.txt"
    @test args["input", Vector{String}] == ["input.txt"]
    @test args["--threads", Vector{String}] == ["4"]
    @test args["output", Vector{String}] == String[]
    @test_throws KeyError args["--missing"]
    @test_throws ArgumentError args["--threads", 5]
    @test_throws KeyError args["--threads", 0]
end

@testset "Value validation" begin
    parser = Parser([
        Argument("mode"; choices = ["fast", "slow"]),
        Argument("--name"; regex = r"^[a-z]+$", default = "alpha", required = false),
        Argument("--tag"; choices = ["red", "blue"], repeat = true)
    ])

    args = parser(["fast", "--name", "alpha", "--tag", "red", "--tag", "blue"]; error_mode = :throw)

    @test args["mode"] == "fast"
    @test args["--name"] == "alpha"
    @test args["--tag", Vector{String}] == ["red", "blue"]

    err_choice = try
        parser(["medium"]; error_mode = :throw)
    catch err
        err
    end
    @test err_choice isa ParseError
    @test err_choice.kind == :invalid_value
    @test occursin("fast", sprint(showerror, err_choice))

    err_regex = try
        parser(["fast", "--name", "Alpha"]; error_mode = :throw)
    catch err
        err
    end
    @test err_regex isa ParseError
    @test err_regex.kind == :invalid_value
    @test occursin("pattern", sprint(showerror, err_regex))

    err_tag = try
        parser(["fast", "--tag", "green"]; error_mode = :throw)
    catch err
        err
    end
    @test err_tag isa ParseError
    @test err_tag.kind == :invalid_value
    @test occursin("red", sprint(showerror, err_tag))
end

@testset "Command disambiguation" begin
    parser = Parser([
        Argument("item")
    ], [
        Command("alpha", [Argument("item")]),
        Command("beta", [Argument("item")], [Command("deep", [Argument("item")])])
    ])

    args = parser(["top", "beta", "middle", "deep", "leaf"]; error_mode = :throw)

    @test args["item"] == "leaf"
    @test args["item", 0] == "top"
    @test args["item", 1] == "middle"
    @test args["item", 2] == "leaf"
end

@testset "Command from parser" begin
    nested = Parser([
        Argument("child"),
        Argument("--mode"; default = "slow")
    ], [
        Command("leaf", [Argument("value")])
    ])

    parent = Parser([Command("nested", nested)])

    args = parent(["nested", "alpha", "--mode", "fast", "leaf", "omega"]; error_mode = :throw)

    @test args.command == ["nested", "leaf"]
    @test args["child"] == "alpha"
    @test args["--mode"] == "fast"
    @test args["value"] == "omega"
    @test args.success
    @test args.complete
end

@testset "Command ordering" begin
    parser = Parser([
        Argument("input")
    ], [
        Command("run", [Argument("task")], [Command("fast")])
    ])

    @test_throws ParseError parser(["run"]; error_mode = :throw)
    @test_throws ParseError parser(["input.txt"]; error_mode = :throw)
    @test_throws ParseError parser(["input.txt", "run", "fast"]; error_mode = :throw)

    args = parser(["input.txt", "run", "build", "fast"]; error_mode = :throw)
    @test args.command == ["run", "fast"]
    @test args["input"] == "input.txt"
    @test args["task"] == "build"

    optional = Parser([
        Argument("maybe"; repeat = true)
    ], [
        Command("go")
    ])

    parsed_optional = optional(["go"]; error_mode = :throw)
    @test parsed_optional.command == ["go"]
    @test parsed_optional["maybe", Vector{String}] == String[]
end

@testset "Auto help" begin
    root_help = Argument("--help"; auto_help = true, help = "Show this help and exit.")
    beta_help = Argument("--help"; auto_help = true, help = "Show beta help.")
    parser = Parser([
        root_help
    ], [
        Command("alpha", [Argument("item"; help = "The alpha item.")]; help = "Alpha command."),
        Command("beta", [beta_help], [Command("nested", [Argument("value"; help = "Nested value.")]; help = "Nested command.")]; help = "Beta command."),
        Command("gamma", [Argument("value")]; auto_help = false, help = "Gamma command.")
    ]; help_program = "<program>")

    @test parser.commands[1].auto_help
    @test parser.commands[1].arguments[1].auto_help
    @test parser.commands[1].arguments[1].names == root_help.names
    @test parser.commands[2].arguments[1].names == beta_help.names
    @test parser.commands[2].commands[1].arguments[1].names == beta_help.names
    @test all(!argument.auto_help for argument in parser.commands[3].arguments)

    wrapped = Command("wrapped", parser)
    @test !wrapped.auto_help

    root_result = parser(["--help"]; error_mode = :return)
    @test root_result.stopped
    root_depth = Cliff._find_auto_help_stop_level(root_result.levels, root_result.stop_argument)
    @test root_depth == 1
    io = IOBuffer()
    Cliff._print_basic_help(io, parser, root_result, root_depth)
    output = String(take!(io))
    @test occursin("<program> [options] COMMAND ...", output)
    @test occursin("Options", output)
    @test occursin("--help", output)
    @test occursin("Commands", output)
    @test occursin("alpha", output)
    @test occursin("Show this help and exit.", output)
    @test occursin("Alpha command.", output)

    beta_result = parser(["beta", "--help"]; error_mode = :return)
    @test beta_result.stopped
    beta_depth = Cliff._find_auto_help_stop_level(beta_result.levels, beta_result.stop_argument)
    @test beta_depth == 2
    beta_io = IOBuffer()
    Cliff._print_basic_help(beta_io, parser, beta_result, beta_depth)
    beta_output = String(take!(beta_io))
    @test occursin("<program> beta [options] COMMAND ...", beta_output)
    @test occursin("Options", beta_output)
    @test occursin("Commands", beta_output)
    @test occursin("nested", beta_output)
    @test occursin("Beta command.", beta_output)
    @test occursin("Show beta help.", beta_output)

    nested_result = parser(["beta", "nested", "--help"]; error_mode = :return)
    @test nested_result.stopped
    nested_depth = Cliff._find_auto_help_stop_level(nested_result.levels, nested_result.stop_argument)
    @test nested_depth == 3
    nested_io = IOBuffer()
    Cliff._print_basic_help(nested_io, parser, nested_result, nested_depth)
    nested_output = String(take!(nested_io))
    @test occursin("<program> beta nested [options] VALUE", nested_output)
    @test occursin("Options", nested_output)
    @test occursin("Arguments", nested_output)
    @test occursin("Nested command.", nested_output)
    @test occursin("Nested value.", nested_output)

    return_result = parser(["--help"]; error_mode = :return)
    @test return_result.stopped

    throw_result = parser(["--help"]; error_mode = :throw)
    @test throw_result.stopped
end

@testset "Positional after first" begin
    shell_parser = Parser([Argument("cmd"; repeat = true)]; positional_after_first = true)
    shell_args = shell_parser(["python", "--version"]; error_mode = :throw)
    @test shell_args["cmd", Vector{String}] == ["python", "--version"]

    run_command = Parser([
        Command("run", [Argument("cmd"; repeat = true)]; positional_after_first = true)
    ])

    args_plain = run_command(["run", "python", "--version"]; error_mode = :throw)
    @test args_plain.command == ["run"]
    @test args_plain["cmd", Vector{String}] == ["python", "--version"]

    args_with_double_dash = run_command(["run", "python", "--", "--version"]; error_mode = :throw)
    @test args_with_double_dash["cmd", Vector{String}] == ["python", "--version"]

    args_with_short = run_command(["run", "python", "-c", "print(1)"]; error_mode = :throw)
    @test args_with_short["cmd", Vector{String}] == ["python", "-c", "print(1)"]
end

@testset "Option handling" begin
    parser = Parser([
        Argument(["--count", "-c"]; default = "0"),
        Argument("--dry-run"; flag = true)
    ])

    args = parser(["--count", "5", "--dry-run"]; error_mode = :throw)
    @test args["--count", Int] == 5
    @test args["--dry-run", Bool]
    @test args["--dry-run", Vector{String}] == ["1"]
    @test args["--dry-run", Int] == 1

    args2 = parser(["-c", "7"]; error_mode = :throw)
    @test args2["-c", String] == "7"
    @test !args2["--dry-run", Bool]
    @test args2["--dry-run", Vector{String}] == String[]
    @test args2["--dry-run", Int] == 0
    @test args2["--dry-run"] == "0"

    args3 = parser(["--count=8", "--dry-run"]; error_mode = :throw)
    @test args3["--count", Int] == 8
    @test args3["--dry-run", Bool]
    @test args3["--dry-run", Vector{String}] == ["1"]

    args4 = parser(["-c=9"]; error_mode = :throw)
    @test args4["--count"] == "=9"
    @test_throws ArgumentError args4["--count", Int]

    @test_throws ParseError parser(["-c"]; error_mode = :throw)
    @test_throws ParseError parser(["--dry-run=true"]; error_mode = :throw)

    short_flags = Parser([
        Argument(["--alpha", "-a"]; flag = true),
        Argument(["--beta", "-b"])
    ])
    @test_throws ParseError short_flags(["-a=1"]; error_mode = :throw)
    @test_throws ParseError short_flags(["-ab"]; error_mode = :throw)
    @test_throws ParseError short_flags(["-az"]; error_mode = :throw)

    auto = Parser([Argument("--toggle"; flag = true)])
    auto_default = auto(String[]; error_mode = :throw)
    @test auto_default["--toggle"] == "0"
    @test !auto_default["--toggle", Bool]
    @test auto_default["--toggle", Vector{String}] == String[]
    toggled = auto(["--toggle"]; error_mode = :throw)
    @test toggled["--toggle"] == "1"
    @test toggled["--toggle", Bool]
    @test toggled["--toggle", Vector{String}] == ["1"]

    implicit = Parser([Argument("--name"; default = String[])])
    implicit_args = implicit(String[]; error_mode = :throw)
    @test_throws ArgumentError implicit_args["--name"]
    @test implicit_args["--name", Vector{String}] == String[]
    @test implicit_args["--name", Union{String, Nothing}] === nothing
    @test implicit_args["--name", String, -] === nothing
    @test implicit_args["--name", -] === nothing
    @test implicit_args.success
    @test implicit_args.complete

    @test_throws ParseError parser(["--count"]; error_mode = :throw)
    @test_throws ParseError parser(["--unknown", "value"]; error_mode = :throw)

    repeat_parser = Parser([Argument(["--verbose", "-v"]; flag = true, repeat = true)])
    repeat_args = repeat_parser(["-vvv", "--verbose"]; error_mode = :throw)
    @test repeat_args["--verbose", Int] == 4
    @test repeat_args["--verbose", Vector{String}] == ["1", "1", "1", "1"]
end

@testset "Stop arguments" begin
    parser = Parser([
        Argument("input"),
        Argument("--help"; flag = true, stop = true)
    ], [
        Command("run", [
            Argument("task"),
            Argument("--help"; flag = true, stop = true)
        ], [Command("fast")])
    ])

    help_root = parser(["--help"]; error_mode = :return)
    @test help_root.success
    @test help_root.stopped
    @test !help_root.complete
    @test help_root.stop_argument == "--help"
    @test help_root.command == String[]
    @test help_root["--help", Bool]

    help_sub = parser(["input.txt", "run", "--help"]; error_mode = :return)
    @test help_sub.success
    @test help_sub.stopped
    @test !help_sub.complete
    @test help_sub.stop_argument == "--help"
    @test help_sub.command == ["run"]
    @test help_sub["input"] == "input.txt"
    @test help_sub["--help", Bool]

    stop_positional = Parser([
        Argument("item"; stop = true)
    ])
    stop_result = stop_positional(["value"]; error_mode = :return)
    @test stop_result.stopped
    @test stop_result.stop_argument == "item"
end

@testset "Unicode options" begin
    parser = Parser([Argument(["--animal", "-🐾"])])
    args = parser(["-🐾🦊"]; error_mode = :throw)
    @test args["--animal"] == "🦊"

    args_eq = parser(["-🐾=🦊"]; error_mode = :throw)
    @test args_eq["--animal"] == "=🦊"
    @test_throws ArgumentError args_eq["--animal", Int]

    flag_parser = Parser([Argument(["--loud", "-✓"]; flag = true, repeat = true)])
    loud = flag_parser(["-✓✓"]; error_mode = :throw)
    @test loud["--loud", Int] == 2
    @test loud["--loud", Vector{String}] == ["1", "1"]
end

@testset "Typed retrieval" begin
    parser = Parser([
        Argument("name"),
        Argument("--count"; default = "42"),
        Argument("--ratio"; default = "3.14"),
        Argument("--flag"; flag = true),
        Argument("--ints"; repeat = true),
        Argument("--floats"; repeat = true),
        Argument("--preset"; repeat = true, default = [1, 2, 3])
    ])

    args = parser([
        "value",
        "--count", "7",
        "--ratio", "2.5",
        "--flag",
        "--ints", "1",
        "--ints", "2",
        "--floats", "0.5",
        "--floats", "1.5"
    ]; error_mode = :throw)

    @test args["name", String] == "value"
    @test args["--count", Int] == 7
    @test args["--ratio", Float64] == 2.5
    @test args["--ratio", String] == "2.5"
    @test args["--flag", Bool]
    @test args["--flag", Vector{Bool}] == [true]
    @test args["--ints", Vector{Int}] == [1, 2]
    @test args["--ints", Int, +] == [1, 2]
    @test args["--floats", Vector{Float64}] == [0.5, 1.5]
    @test args["--floats", Float64, +] == [0.5, 1.5]
    @test args["--preset", Vector{Int}] == Int[]
    @test args["--ratio", Union{String, Nothing}] == "2.5"
    @test args["--ratio", Float64, -] == 2.5
    @test args["--flag", -] == "1"
    @test args["--flag", Bool, -] == true
    @test_throws ArgumentError args["--ints", Union{String, Nothing}]

    defaults = parser(["value"]; error_mode = :throw)
    @test defaults["--count", Int] == 42
    @test defaults["--ratio", Float64] == 3.14
    @test !defaults["--flag", Bool]
    @test defaults["--flag", Vector{Bool}] == Bool[]
    @test defaults["--ints", Vector{Int}] == Int[]
    @test defaults["--floats", Vector{Float64}] == Float64[]
    @test defaults["--preset", Vector{Int}] == Int[]
    @test defaults["--ratio", Union{String, Nothing}] == "3.14"
    @test defaults["--count", Int, -] == 42
    @test defaults["--flag", Union{String, Nothing}] == "0"
    @test defaults["--flag", Bool, -] == false
    @test defaults["--flag", -] == "0"
    @test_throws ArgumentError defaults["--floats", Float64, -]
end

@testset "Optional option defaults" begin
    parser = Parser([
        Argument("--opt"),
        Argument("--flag"; flag = true)
    ])

    args = parser(String[]; error_mode = :throw)
    @test args["--opt", Vector{String}] == String[]
    @test !args["--flag", Bool]
    @test args["--flag", Vector{String}] == String[]
    @test args["--flag", Union{String, Nothing}] == "0"
    @test args["--flag", Bool, -] == false
    @test args["--flag", -] == "0"
    @test args["--opt", Union{String, Nothing}] === nothing
    @test args["--opt", -] === nothing
    @test_throws ArgumentError args["--opt"]
    @test_throws ArgumentError args["--opt", Int]
end

@testset "Repeatable arguments" begin
    parser = Parser([
        Argument("--multi"; repeat = 2:4),
        Argument("--numbers"; min_repeat = 1, max_repeat = :inf),
        Argument("pos"; repeat = 1:3),
        Argument("--flag"; flag = true, max_repeat = :inf)
    ])

    args = parser([
        "--multi", "one",
        "--multi", "two",
        "--numbers", "10",
        "--numbers", "20",
        "--numbers", "30",
        "posA", "posB",
        "--flag", "--flag"
    ]; error_mode = :throw)

    @test args["--multi", Vector{String}] == ["one", "two"]
    @test args["--numbers", Vector{Int}] == [10, 20, 30]
    @test args["--numbers", +] == ["10", "20", "30"]
    @test args["--numbers", Int, +] == [10, 20, 30]
    @test args["pos", Vector{String}] == ["posA", "posB"]
    @test args["--flag", Vector{Bool}] == [true, true]
    @test_throws ArgumentError args["--multi"]
    @test_throws ArgumentError args["--flag", Bool]

    @test_throws ParseError parser([
        "--multi", "only",
        "--numbers", "1",
        "posA"
    ]; error_mode = :throw)
end

@testset "Repeat helpers" begin
    @test Cliff._repeat_allows_zero_min(true, nothing)
    @test Cliff._repeat_allows_zero_min(0, nothing)
    @test Cliff._repeat_allows_zero_min(0:3, nothing)
    @test Cliff._repeat_allows_zero_min((0, 2), nothing)
    @test !Cliff._repeat_allows_zero_min(nothing, nothing)
    @test !Cliff._repeat_allows_zero_min(1:3, nothing)

    @test Cliff._normalize_repeat_spec(2) == (2, 2)
    @test_throws ArgumentError Cliff._normalize_repeat_spec(-1)
    @test_throws ArgumentError Cliff._normalize_repeat_spec(0:2:4)
    @test_throws ArgumentError Cliff._normalize_repeat_spec(2:1)
    @test_throws ArgumentError Cliff._normalize_repeat_spec(0:1:1.5)
    @test Cliff._normalize_repeat_spec((0, :inf)) == (0, typemax(Int))
    @test Cliff._normalize_repeat_spec((1, nothing)) == (1, typemax(Int))
    @test_throws ArgumentError Cliff._normalize_repeat_spec(:invalid)
end

@testset "Indexing errors" begin
    parser = Parser([
        Argument("root"),
        Argument("--root-flag"; flag = true)
    ], [
        Command("child", [
            Argument("value"),
            Argument("--opt"; default = "alpha"),
            Argument("--flag"; flag = true)
        ])
    ])

    args = parser(["root", "child", "beta", "--flag"]; error_mode = :throw)

    @test_throws KeyError args["--unknown"]
    @test_throws ArgumentError args["root", -1]
    @test_throws KeyError args["--opt", 0]
    @test_throws ArgumentError args["--opt", Bool]
    @test_throws KeyError args["--missing", Int]
    @test_throws ArgumentError args["value", 5, Int]
    @test_throws KeyError args["--opt", 0, Int]
    @test args["--flag", Int] == 1
    @test_throws KeyError args["--missing", Vector{String}]
    @test_throws ArgumentError args["value", 5, Vector{String}]
    @test_throws KeyError args["--opt", 0, Vector{String}]
    @test args["value", Vector{String}] == ["beta"]
    @test args["value", 1, String, +] == ["beta"]
end

@testset "Parsing edge cases" begin
    parser = Parser([Argument("--name")])
    args = parser(["--name", "first", "--name", "second"]; error_mode = :throw)
    @test args["--name"] == "second"

    limited = Parser([Argument("--item"; repeat = 1:2)])
    @test_throws ParseError limited(["--item", "one", "--item", "two", "--item", "three"]; error_mode = :throw)

    positional = Parser([Argument("value")])
    @test_throws ParseError positional(["one", "two"]; error_mode = :throw)

    unknown_short = Parser([Argument(["--verbose", "-v"]; flag = true)])
    @test_throws ParseError unknown_short(["-v", "-x"]; error_mode = :throw)

    inline_short_flag = Parser([Argument(["--quiet", "-q"]; flag = true)])
    @test_throws ParseError inline_short_flag(["-q=1"]; error_mode = :throw)

    bundle_non_flag = Parser([
        Argument(["--alpha", "-a"]; flag = true),
        Argument(["--beta", "-b"])
    ])
    @test_throws ParseError bundle_non_flag(["-ab"]; error_mode = :throw)

    bundle_unknown = Parser([Argument(["--alpha", "-a"]; flag = true)])
    @test_throws ParseError bundle_unknown(["-az"]; error_mode = :throw)

    long_unknown = Parser([Argument("--flag"; flag = true)])
    @test_throws ParseError long_unknown(["--unknown"]; error_mode = :throw)

    long_missing_value = Parser([Argument("--value")])
    @test_throws ParseError long_missing_value(["--value"]; error_mode = :throw)

    positional_stop = Parser([Argument("item"; stop = true)])
    stop_args = positional_stop(["item"]; error_mode = :throw)
    @test stop_args.stopped
    @test stop_args.stop_argument == "item"

end

@testset "Error message rendering" begin
    function error_message(parser::Parser, argv::Vector{String})
        try
            parser(argv; error_mode = :throw)
            @test false
            return ""
        catch err
            @test err isa ParseError
            return sprint(showerror, err)
        end
    end

    default_parser = Parser([Argument("--flag"; flag = true)]; help_program = "julia script.jl")
    @test error_message(default_parser, ["--unknown"]) ==
          "In 'julia script.jl --unknown', invalid argument '--unknown'."

    required_parser = Parser([Argument("--input"; required = true)]; help_program = "program")
    @test error_message(required_parser, String[]) ==
          "In 'program', argument '--input' required 1 time but was provided 0 times."

    triple_parser = Parser([Argument("--triple"; repeat = 3)]; help_program = "program")
    @test error_message(triple_parser, String[]) ==
          "In 'program', argument '--triple' required 3 times but was provided 0 times."
    @test error_message(triple_parser, [
        "--triple", "one",
        "--triple", "two",
        "--triple", "three",
        "--triple", "four",
    ]) == "In 'program --triple', argument '--triple' required 3 times but was provided 4 times."

    range_parser = Parser([Argument("--range"; repeat = 2:4)]; help_program = "program")
    @test error_message(range_parser, ["--range", "one"]) ==
          "In 'program --range one', argument '--range' required 2-4 times but was provided 1 time."
    @test error_message(range_parser, [
        "--range", "one",
        "--range", "two",
        "--range", "three",
        "--range", "four",
        "--range", "five",
    ]) == "In 'program --range', argument '--range' required 2-4 times but was provided 5 times."

    atleast_parser = Parser([Argument("--multi"; repeat = (2, nothing))]; help_program = "program")
    @test error_message(atleast_parser, ["--multi", "one"]) ==
          "In 'program --multi one', argument '--multi' required at least 2 times but was provided 1 time."

    choices_parser = Parser([Argument("--mode"; choices = ["fast", "slow"])]; help_program = "program")
    @test error_message(choices_parser, ["--mode", "medium"]) ==
          "In 'program --mode medium', invalid value 'medium' for '--mode'; expected one of 'fast', 'slow'."

    regex_parser = Parser([Argument("--name"; regex = r"^[a-z]+$")]; help_program = "program")
    regex_expected = "In 'program --name 123', invalid value '123' for '--name'; expected to match pattern r\"^[a-z]+\$\"."
    @test error_message(regex_parser, ["--name", "123"]) == regex_expected

    missing_value = Parser([Argument("--value")]; help_program = "program")
    @test error_message(missing_value, ["--value"]) ==
          "In 'program --value', missing value for '--value'."

    short_flag_value = Parser([Argument(["--quiet", "-q"]; flag = true)]; help_program = "program")
    @test error_message(short_flag_value, ["-q=1"]) ==
          "In 'program -q=1', argument '-q' does not take a value."

    unexpected_positional = Parser([Argument("--flag"; flag = true)]; help_program = "program")
    @test error_message(unexpected_positional, ["value"]) ==
          "In 'program value', unexpected positional argument 'value'."

    command_parser = Parser(Argument[], Command[Command("status")]; help_program = "program")
    @test error_message(command_parser, String[]) ==
          "In 'program', expected a command."
    @test error_message(command_parser, ["bogus"]) ==
          "In 'program bogus', invalid command 'bogus'."

    remote_parser = Parser(Argument[], Command[Command("remote", Command[Command("add")])]; help_program = "git")
    @test error_message(remote_parser, ["remote"]) ==
          "In 'git remote remote', expected a subcommand for 'remote'."

    git_parser = Parser(
        [Argument("--help"; flag = true)],
        [
            Command("status"),
            Command("remote", Command[Command("add"), Command("remove")]),
            Command("commit", [Argument(["--message", "-m"])])
        ];
        help_program = "git",
    )

    @test error_message(git_parser, ["status", "--foo"]) == "In 'git status --foo', invalid argument '--foo'."
    @test error_message(git_parser, ["remote", "odd"]) == "In 'git remote odd', invalid subcommand 'odd'."
    @test error_message(git_parser, ["commit", "-m"]) == "In 'git commit -m', missing value for '-m'."
    @test error_message(git_parser, ["--help=foo"]) == "In 'git --help=foo', argument '--help' does not take a value."

    commit_repeat = Parser(
        Command[Command("commit", [Argument(["--message", "-m"]; flag = true, repeat = 0:2)])];
        help_program = "git",
    )
    @test error_message(commit_repeat, ["commit", "-m", "-m", "-m"]) ==
          "In 'git commit -m', argument '-m' expected at most 2 times but was provided 3 times."

    script_parser = Parser([
        Argument(["--exit", "-x"]; flag = true, repeat = 0:2),
        Argument(["--alpha", "-a"]; flag = true),
        Argument(["--beta", "-b"])
    ]; help_program = "script.jl")
    @test error_message(script_parser, ["-xxx"]) ==
          "In 'script.jl -xxx', argument '-x' expected at most 2 times but was provided 3 times."
    @test error_message(script_parser, ["-ab"]) == "In 'script.jl -ab', invalid argument '-b'."
end

@testset "Double dash behaviour" begin
    parser = Parser([
        Argument("name"),
        Argument("rest"; repeat = true)
    ], [
        Command("cmd", [
            Argument("--flag"; flag = true),
            Argument("value")
        ])
    ])

    args = parser(["alpha", "--", "cmd", "--flag", "beta"]; error_mode = :throw)
    @test args.command == ["cmd"]
    @test args["--flag", Bool]
    @test args["value"] == "beta"
    @test args["name", 0] == "alpha"

    @test_throws ParseError parser(["alpha", "--", "--not-a-command"]; error_mode = :throw)
end

@testset "Error modes" begin
    parser = Parser([Argument("required")])

    @test_throws ParseError parser(String[]; error_mode = :throw)

    result = parser(String[]; error_mode = :return)
    @test !result.success
    @test !result.complete
    @test !result.stopped
    @test result.error isa ParseError
    @test result.error.kind == :missing_required
    @test result.error.argument == "required"
    @test result.command == String[]
    @test result.stop_argument === nothing
    @test result.error.command == String[]
    error_string = lowercase(sprint(showerror, result.error))
    @test occursin("required 1 time", error_string)
    @test occursin("provided 0 times", error_string)

    success = parser(["value"]; error_mode = :return)
    @test success.success
    @test success.complete

    @test_throws ArgumentError parser(String[]; error_mode = :invalid)
end

@testset "Type conversion errors" begin
    parser = Parser([Argument("value")])
    args = parser(["abc"]; error_mode = :throw)
    @test_throws ArgumentError args["value", Int]
    @test args["value", String] == "abc"
end

@testset "Invalid constructions" begin
    @test_throws ArgumentError Argument(["name", "--flag"])
    @test_throws ArgumentError Argument("name"; flag = true)
    @test_throws ArgumentError Command(["cmd", "cmd"])
    @test_throws ArgumentError Parser([Argument("a"), Argument("a")])
    @test_throws ArgumentError Command("parent", Argument[], [Command("dup"), Command("dup")])
end

@testset "Example script" begin
    example = joinpath(@__DIR__, "..", "examples", "example.jl")
    project = joinpath(@__DIR__, "..")
    function run_example(args::Vector{String})
        stdout = IOBuffer()
        stderr = IOBuffer()
        base = Base.julia_cmd()
        exec = vcat(base.exec, ["--project=$(project)", example], args)
        cmd = base.env === nothing ? Cmd(exec) : Cmd(exec; env = base.env)
        pipeline_cmd = pipeline(cmd; stdout = stdout, stderr = stderr)
        ok = success(pipeline_cmd)
        return ok, String(take!(stdout)), String(take!(stderr))
    end

    ok, out, err = run_example(["project", "--count", "2", "--tag", "demo", "--verbose", "run", "quick", "--threads", "6", "--repeat", "once", "--dry-run", "fast", "--limit", "5", "--extra", "alpha"])
    @test ok
    @test occursin("args.command = [\"run\", \"fast\"]", out)
    @test occursin("help_hits = 0", out)
    @test occursin("args[\"target\"] = \"project\"", out)
    @test occursin("args[\"--verbose\", Bool] = true", out)
    @test isempty(err)

    ok_help, out_help, err_help = run_example(["--help"])
    @test ok_help
    @test occursin("args.command = String[]", out_help)
    @test occursin("help_hits = 1", out_help)
    @test isempty(err_help)

    ok_fail, out_fail, err_fail = run_example(String[])
    @test !ok_fail
    @test isempty(out_fail)
    err_fail_lower = lowercase(err_fail)
    @test occursin("required 1 time", err_fail_lower)
    @test occursin("provided 0 times", err_fail_lower)
end
