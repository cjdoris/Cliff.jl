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
    @test args[String, "--threads"] == "4"
    @test args[Int, "--threads"] == 4
    @test args[Bool, "--verbose"]
    @test args["--limit"] == "20"
    @test args[String, "--limit", 2] == "20"
    @test args[String, "input", 0] == "input.txt"
    @test args[Vector{String}, "input"] == ["input.txt"]
    @test args[Vector{String}, "--threads"] == ["4"]
    @test args[Vector{String}, "output"] == ["out.txt"]
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

@testset "Option handling" begin
    parser = Parser(
        arguments = [
            Argument(["--count", "-c"]; default = "0"),
            Argument("--dry-run"; flag = true)
        ]
    )

    args = parser(["--count", "5", "--dry-run"])
    @test args[Int, "--count"] == 5
    @test args[Bool, "--dry-run"]
    @test args[Vector{String}, "--dry-run"] == ["true"]

    args2 = parser(["-c", "7"])
    @test args2[String, "-c"] == "7"
    @test !args2[Bool, "--dry-run"]
    @test args2[Vector{String}, "--dry-run"] == ["false"]

    args3 = parser(["--count=8", "--dry-run"])
    @test args3[Int, "--count"] == 8
    @test args3[Bool, "--dry-run"]
    @test args3[Vector{String}, "--dry-run"] == ["true"]

    @test_throws ArgumentError parser(["--count"])
    @test_throws ArgumentError parser(["--unknown", "value"])
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

    @test args[Vector{String}, "--multi"] == ["one", "two"]
    @test args[Vector{Int}, "--numbers"] == [10, 20, 30]
    @test args[+, "--numbers"] == ["10", "20", "30"]
    @test args[Int, +, "--numbers"] == [10, 20, 30]
    @test args[Vector{String}, "pos"] == ["posA", "posB"]
    @test args[Vector{Bool}, "--flag"] == [true, true]
    @test_throws ArgumentError args["--multi"]
    @test_throws ArgumentError args[Bool, "--flag"]

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
    @test args[Bool, "--flag"]
    @test args["value"] == "beta"
    @test args["name", 0] == "alpha"

    positional_args = parser(["alpha", "--", "--not-a-command"])
    @test positional_args["rest"] == "--not-a-command"
end

@testset "Type conversion errors" begin
    parser = Parser(arguments = [Argument("value"; required = true)])
    args = parser(["abc"])
    @test_throws ArgumentError args[Int, "value"]
    @test args[String, "value"] == "abc"
end

@testset "Invalid constructions" begin
    @test_throws ArgumentError Argument("name", "--flag")
    @test_throws ArgumentError Argument("name"; flag = true)
    @test_throws ArgumentError Command("cmd", "cmd")
    @test_throws ArgumentError Parser(arguments = [Argument("a"), Argument("a")])
end
