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

    choice_arg = Argument("mode"; choices = ["fast", "slow"], default = "fast")
    @test choice_arg.choices == ["fast", "slow"]
    @test !choice_arg.has_regex

    regex_arg = Argument("--slug"; regex = r"^[a-z]+$", default = "slug", required = false)
    @test regex_arg.has_regex
    @test regex_arg.regex isa Regex

    stop_arg = Argument("--help"; stop = true)
    @test stop_arg.min_occurs == 0
    @test !stop_arg.required

    numeric_default = Argument("--count"; default = 5)
    @test numeric_default.default == ["5"]

    vector_default = Argument("--numbers"; repeat = true, default = [1, "two", 3.5])
    @test vector_default.default == ["1", "two", "3.5"]

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
    @test args["output", Vector{String}] == ["out.txt"]
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
    @test occursin("fast", err_choice.message)

    err_regex = try
        parser(["fast", "--name", "Alpha"]; error_mode = :throw)
    catch err
        err
    end
    @test err_regex isa ParseError
    @test err_regex.kind == :invalid_value
    @test occursin("pattern", err_regex.message)

    err_tag = try
        parser(["fast", "--tag", "green"]; error_mode = :throw)
    catch err
        err
    end
    @test err_tag isa ParseError
    @test err_tag.kind == :invalid_value
    @test occursin("red", err_tag.message)
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
    @test implicit_args["--name"] == ""
    @test implicit_args["--name", Vector{String}] == String[]
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
    @test args["--preset", Vector{Int}] == [1, 2, 3]

    defaults = parser(["value"]; error_mode = :throw)
    @test defaults["--count", Int] == 42
    @test defaults["--ratio", Float64] == 3.14
    @test !defaults["--flag", Bool]
    @test defaults["--flag", Vector{Bool}] == Bool[]
    @test defaults["--ints", Vector{Int}] == Int[]
    @test defaults["--floats", Vector{Float64}] == Float64[]
    @test defaults["--preset", Vector{Int}] == [1, 2, 3]
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
    @test occursin("Missing required argument", result.error.message)

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
    @test occursin("Missing required argument", err_fail)
end
