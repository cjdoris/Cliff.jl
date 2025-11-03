using Test
using Cliff

@testset "Argument construction" begin
    arg = Argument(["--name", "-n"]; default = "guest")
    @test arg.flag == false
    @test arg.names == ["--name", "-n"]
    @test arg.default == ["guest"]
    @test arg.has_default
    @test !arg.positional

    flag = Argument("--verbose"; flag = true)
    @test flag.flag
    @test isempty(flag.default)
end

@testset "Basic parsing" begin
    parser = Parser(
        arguments = [
            Argument("input"; required = true),
            Argument("output"; default = "out.txt")
        ],
        commands = [
            Command("run";
                arguments = [
                    Argument("task"; required = true),
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

    args = parser(["input.txt", "run", "build", "--threads", "4", "--verbose", "fast", "--limit", "20"])

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
        arguments = [Argument("item"; required = true)],
        commands = [
            Command("alpha"; arguments = [Argument("item"; required = true)]),
            Command("beta";
                arguments = [Argument("item"; required = true)],
                commands = [Command("deep"; arguments = [Argument("item"; required = true)])]
            )
        ]
    )

    args = parser(["top", "beta", "middle", "deep", "leaf"])

    @test args["item"] == "leaf"
    @test args["item", 0] == "top"
    @test args["item", 1] == "middle"
    @test args["item", 2] == "leaf"
end

@testset "Command ordering" begin
    parser = Parser(
        arguments = [Argument("input"; required = true)],
        commands = [
            Command("run";
                arguments = [Argument("task"; required = true)],
                commands = [Command("fast")]
            )
        ]
    )

    @test_throws ArgumentError parser(["run"])
    @test_throws ArgumentError parser(["input.txt"])
    @test_throws ArgumentError parser(["input.txt", "run", "fast"])

    args = parser(["input.txt", "run", "build", "fast"])
    @test args.command == ["run", "fast"]
    @test args["input"] == "input.txt"
    @test args["task"] == "build"

    optional = Parser(
        arguments = [Argument("maybe")],
        commands = [Command("go")]
    )

    parsed_optional = optional(["go"])
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

    args = parser(["--count", "5", "--dry-run"])
    @test args["--count", Int] == 5
    @test args["--dry-run", Bool]
    @test args["--dry-run", Vector{String}] == ["true"]

    args2 = parser(["-c", "7"])
    @test args2["-c", String] == "7"
    @test !args2["--dry-run", Bool]
    @test args2["--dry-run", Vector{String}] == ["false"]

    args3 = parser(["--count=8", "--dry-run"])
    @test args3["--count", Int] == 8
    @test args3["--dry-run", Bool]
    @test args3["--dry-run", Vector{String}] == ["true"]

    @test_throws ArgumentError parser(["--count"])
    @test_throws ArgumentError parser(["--unknown", "value"])
end

@testset "Typed retrieval" begin
    parser = Parser(
        arguments = [
            Argument("name"; required = true),
            Argument("--count"; default = "42"),
            Argument("--ratio"; default = "3.14"),
            Argument("--flag"; flag = true),
            Argument("--ints"; max_repeat = :inf),
            Argument("--floats"; max_repeat = :inf)
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
    ])

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

    defaults = parser(["value"])
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
    ])

    @test args["--multi", Vector{String}] == ["one", "two"]
    @test args["--numbers", Vector{Int}] == [10, 20, 30]
    @test args["--numbers", +] == ["10", "20", "30"]
    @test args["--numbers", Int, +] == [10, 20, 30]
    @test args["pos", Vector{String}] == ["posA", "posB"]
    @test args["--flag", Vector{Bool}] == [true, true]
    @test_throws ArgumentError args["--multi"]
    @test_throws ArgumentError args["--flag", Bool]

    @test_throws ArgumentError parser([
        "--multi", "only",
        "--numbers", "1",
        "posA"
    ])
end

@testset "Double dash behaviour" begin
    parser = Parser(
        arguments = [Argument("name"; required = true), Argument("rest")],
        commands = [
            Command("cmd";
                arguments = [Argument("--flag"; flag = true), Argument("value"; required = true)]
            )
        ]
    )

    args = parser(["alpha", "--", "cmd", "--flag", "beta"])
    @test args.command == ["cmd"]
    @test args["--flag", Bool]
    @test args["value"] == "beta"
    @test args["name", 0] == "alpha"

    @test_throws ArgumentError parser(["alpha", "--", "--not-a-command"])
end

@testset "Type conversion errors" begin
    parser = Parser(arguments = [Argument("value"; required = true)])
    args = parser(["abc"])
    @test_throws ArgumentError args["value", Int]
    @test args["value", String] == "abc"
end

@testset "Invalid constructions" begin
    @test_throws ArgumentError Argument("name", "--flag")
    @test_throws ArgumentError Argument("name"; flag = true)
    @test_throws ArgumentError Command("cmd", "cmd")
    @test_throws ArgumentError Parser(arguments = [Argument("a"), Argument("a")])
end
