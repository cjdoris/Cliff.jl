using Test
using Cliff

@testset "Argument construction" begin
    arg = Argument(["--name", "-n"]; default = "guest")
    @test arg.flag == false
    @test arg.names == ["--name", "-n"]
    @test arg.default == "guest"
    @test arg.has_default
    @test !arg.positional

    flag = Argument("--verbose"; flag = true)
    @test flag.flag
    @test flag.default == "false"
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

    parsed = parser(["input.txt", "run", "build", "--threads", "4", "--verbose", "fast", "--limit", "20"])

    @test parsed.command == ["run", "fast"]
    @test parsed["input"] == "input.txt"
    @test parsed["output"] == "out.txt"
    @test parsed["task"] == "build"
    @test parsed[String, "--threads"] == "4"
    @test parsed[Int, "--threads"] == 4
    @test parsed[Bool, "--verbose"]
    @test parsed["--limit"] == "20"
    @test parsed[String, "--limit", 2] == "20"
    @test parsed[String, "input", 0] == "input.txt"
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

    parsed = parser(["top", "beta", "middle", "deep", "leaf"])

    @test parsed["item"] == "leaf"
    @test parsed["item", 0] == "top"
    @test parsed["item", 1] == "middle"
    @test parsed["item", 2] == "leaf"
end

@testset "Option handling" begin
    parser = Parser(
        arguments = [
            Argument(["--count", "-c"]; default = "0"),
            Argument("--dry-run"; flag = true)
        ]
    )

    parsed = parser(["--count", "5", "--dry-run"])
    @test parsed[Int, "--count"] == 5
    @test parsed[Bool, "--dry-run"]

    parsed2 = parser(["-c", "7"])
    @test parsed2[String, "-c"] == "7"
    @test !parsed2[Bool, "--dry-run"]

    @test_throws ArgumentError parser(["--count"])
    @test_throws ArgumentError parser(["--unknown", "value"])
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

    parsed = parser(["alpha", "--", "cmd", "--flag", "beta"])
    @test parsed.command == ["cmd"]
    @test parsed[Bool, "--flag"]
    @test parsed["value"] == "beta"
    @test parsed["name", 0] == "alpha"

    parsed_positional = parser(["alpha", "--", "--not-a-command"])
    @test parsed_positional["rest"] == "--not-a-command"
end

@testset "Type conversion errors" begin
    parser = Parser(arguments = [Argument("value"; required = true)])
    parsed = parser(["abc"])
    @test_throws ArgumentError parsed[Int, "value"]
    @test parsed[String, "value"] == "abc"
end

@testset "Invalid constructions" begin
    @test_throws ArgumentError Argument("name", "--flag")
    @test_throws ArgumentError Argument("name"; flag = true)
    @test_throws ArgumentError Command("cmd", "cmd")
    @test_throws ArgumentError Parser(arguments = [Argument("a"), Argument("a")])
end
