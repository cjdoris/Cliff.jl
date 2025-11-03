using Test
using Cliff

@testset "Argument construction" begin
    arg = Argument(["--name", "-n"]; default = "guest")
    @test arg.flag == false
    @test arg.names == ["--name", "-n"]
    @test arg.default == ["guest"]
    @test arg.has_default
    @test !arg.positional

    flag = Argument("--verbose"; flag = true, default = "false")
    @test flag.flag
    @test flag.default == ["false"]
    @test flag.has_default
    @test flag.flag_value == "true"

    auto_flag = Argument("--debug"; flag = true)
    @test auto_flag.default == ["false"]
    @test auto_flag.flag_value == "true"

    yes_flag = Argument("--answer"; flag = true, default = "no")
    @test yes_flag.flag_value == "yes"

    upper_flag = Argument("--power"; flag = true, default = "OFF")
    @test upper_flag.flag_value == "ON"

    custom_flag = Argument("--mode"; flag = true, default = "disabled", flag_value = "enabled")
    @test custom_flag.flag_value == "enabled"

    @test_throws ArgumentError Argument("value"; flag_value = "on")

    repeat_flag = Argument("--verbose"; flag = true, repeat = true)
    @test repeat_flag.min_occurs == 0
    @test repeat_flag.max_occurs == typemax(Int)

    required_repeat_flag = Argument("--debug"; flag = true, required = true, repeat = true)
    @test required_repeat_flag.min_occurs == 1
    @test required_repeat_flag.max_occurs == typemax(Int)
end

@testset "Basic parsing" begin
    parser = Parser(
        arguments = [
            Argument("input"),
            Argument("output"; default = "out.txt")
        ],
        commands = [
            Command("run";
                arguments = [
                    Argument("task"),
                    Argument(["--threads", "-t"]; default = "1"),
                    Argument("--verbose"; flag = true)
                ],
                commands = [
                    Command("fast";
                        arguments = [Argument("--limit"; default = "10")]
                    )
                ]
            )
        ]
    )

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

@testset "Command disambiguation" begin
    parser = Parser(
        arguments = [Argument("item")],
        commands = [
            Command("alpha"; arguments = [Argument("item")]),
            Command("beta";
                arguments = [Argument("item")],
                commands = [Command("deep"; arguments = [Argument("item")])]
            )
        ]
    )

    args = parser(["top", "beta", "middle", "deep", "leaf"]; error_mode = :throw)

    @test args["item"] == "leaf"
    @test args["item", 0] == "top"
    @test args["item", 1] == "middle"
    @test args["item", 2] == "leaf"
end

@testset "Command from parser" begin
    nested = Parser(
        arguments = [
            Argument("child"),
            Argument("--mode"; default = "slow")
        ],
        commands = [
            Command("leaf"; arguments = [Argument("value")])
        ],
        usages = ["child usage"]
    )

    parent = Parser(commands = [Command("nested", nested)])

    args = parent(["nested", "alpha", "--mode", "fast", "leaf", "omega"]; error_mode = :throw)

    @test args.command == ["nested", "leaf"]
    @test args["child"] == "alpha"
    @test args["--mode"] == "fast"
    @test args["value"] == "omega"
    @test args.success
    @test args.complete
end

@testset "Command ordering" begin
    parser = Parser(
        arguments = [Argument("input")],
        commands = [
            Command("run";
                arguments = [Argument("task")],
                commands = [Command("fast")]
            )
        ]
    )

    @test_throws ParseError parser(["run"]; error_mode = :throw)
    @test_throws ParseError parser(["input.txt"]; error_mode = :throw)
    @test_throws ParseError parser(["input.txt", "run", "fast"]; error_mode = :throw)

    args = parser(["input.txt", "run", "build", "fast"]; error_mode = :throw)
    @test args.command == ["run", "fast"]
    @test args["input"] == "input.txt"
    @test args["task"] == "build"

    optional = Parser(
        arguments = [Argument("maybe"; required = false)],
        commands = [Command("go")]
    )

    parsed_optional = optional(["go"]; error_mode = :throw)
    @test parsed_optional.command == ["go"]
    @test parsed_optional["maybe", Vector{String}] == String[]
end

@testset "Option handling" begin
    parser = Parser(
        arguments = [
            Argument(["--count", "-c"]; default = "0"),
            Argument("--dry-run"; flag = true)
        ]
    )

    args = parser(["--count", "5", "--dry-run"]; error_mode = :throw)
    @test args["--count", Int] == 5
    @test args["--dry-run", Bool]
    @test args["--dry-run", Vector{String}] == ["true"]
    @test args["--dry-run", Int] == 1

    args2 = parser(["-c", "7"]; error_mode = :throw)
    @test args2["-c", String] == "7"
    @test !args2["--dry-run", Bool]
    @test args2["--dry-run", Vector{String}] == ["false"]
    @test args2["--dry-run", Int] == 0

    args3 = parser(["--count=8", "--dry-run"]; error_mode = :throw)
    @test args3["--count", Int] == 8
    @test args3["--dry-run", Bool]
    @test args3["--dry-run", Vector{String}] == ["true"]

    auto = Parser(arguments = [Argument("--toggle"; flag = true)])
    auto_default = auto(String[]; error_mode = :throw)
    @test !auto_default["--toggle", Bool]
    @test auto_default["--toggle", Vector{String}] == ["false"]
    toggled = auto(["--toggle"]; error_mode = :throw)
    @test toggled["--toggle"] == "true"
    @test toggled["--toggle", Bool]

    yesno = Parser(arguments = [Argument("--answer"; flag = true, default = "no")])
    yesno_default = yesno(String[]; error_mode = :throw)
    @test yesno_default["--answer"] == "no"
    @test !yesno_default["--answer", Bool]
    yesno_on = yesno(["--answer"]; error_mode = :throw)
    @test yesno_on["--answer"] == "yes"
    @test yesno_on["--answer", Bool]

    custom = Parser(arguments = [Argument("--mode"; flag = true, default = "disabled", flag_value = "enabled")])
    custom_args = custom(["--mode"]; error_mode = :throw)
    @test custom_args["--mode"] == "enabled"

    implicit = Parser(arguments = [Argument("--name"; default = String[])])
    implicit_args = implicit(String[]; error_mode = :throw)
    @test implicit_args["--name"] == ""
    @test implicit_args["--name", Vector{String}] == String[]
    @test implicit_args.success
    @test implicit_args.complete

    @test_throws ParseError parser(["--count"]; error_mode = :throw)
    @test_throws ParseError parser(["--unknown", "value"]; error_mode = :throw)

    repeat_parser = Parser(arguments = [Argument(["--verbose", "-v"]; flag = true, repeat = true)])
    repeat_args = repeat_parser(["-vvv", "--verbose"]; error_mode = :throw)
    @test repeat_args["--verbose", Int] == 4
    @test repeat_args["--verbose", Vector{String}] == ["true", "true", "true", "true"]
end

@testset "Stop arguments" begin
    parser = Parser(
        arguments = [
            Argument("input"),
            Argument("--help"; flag = true, stop = true)
        ],
        commands = [
            Command("run";
                arguments = [
                    Argument("task"),
                    Argument("--help"; flag = true, stop = true)
                ],
                commands = [Command("fast")]
            )
        ]
    )

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

@testset "Typed retrieval" begin
    parser = Parser(
        arguments = [
            Argument("name"),
            Argument("--count"; default = "42"),
            Argument("--ratio"; default = "3.14"),
            Argument("--flag"; flag = true),
            Argument("--ints"; max_repeat = :inf, required = false),
            Argument("--floats"; max_repeat = :inf, required = false)
        ]
    )

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

    defaults = parser(["value"]; error_mode = :throw)
    @test defaults["--count", Int] == 42
    @test defaults["--ratio", Float64] == 3.14
    @test !defaults["--flag", Bool]
    @test defaults["--flag", Vector{Bool}] == [false]
    @test defaults["--ints", Vector{Int}] == Int[]
    @test defaults["--floats", Vector{Float64}] == Float64[]
end

@testset "Repeatable arguments" begin
    parser = Parser(
        arguments = [
            Argument("--multi"; repeat = 2:4),
            Argument("--numbers"; min_repeat = 1, max_repeat = :inf),
            Argument("pos"; repeat = 1:3),
            Argument("--flag"; flag = true, max_repeat = :inf)
        ]
    )

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
    parser = Parser(
        arguments = [Argument("name"), Argument("rest"; required = false)],
        commands = [
            Command("cmd";
                arguments = [Argument("--flag"; flag = true), Argument("value")]
            )
        ]
    )

    args = parser(["alpha", "--", "cmd", "--flag", "beta"]; error_mode = :throw)
    @test args.command == ["cmd"]
    @test args["--flag", Bool]
    @test args["value"] == "beta"
    @test args["name", 0] == "alpha"

    @test_throws ParseError parser(["alpha", "--", "--not-a-command"]; error_mode = :throw)
end

@testset "Error modes" begin
    parser = Parser(arguments = [Argument("required")])

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
    parser = Parser(arguments = [Argument("value")])
    args = parser(["abc"]; error_mode = :throw)
    @test_throws ArgumentError args["value", Int]
    @test args["value", String] == "abc"
end

@testset "Invalid constructions" begin
    @test_throws ArgumentError Argument("name", "--flag")
    @test_throws ArgumentError Argument("name"; flag = true)
    @test_throws ArgumentError Command("cmd", "cmd")
    @test_throws ArgumentError Parser(arguments = [Argument("a"), Argument("a")])
end
