#!/usr/bin/env julia
using Cliff

subtools = Parser([
    Argument("--tool"; choices = ["hammer", "saw", "wrench"], default = ["hammer"]),
    Argument("--list"; flag = true)
], [
    Command("set", [
        Argument("key"),
        Argument("value")
    ])
])

parser = Parser([
    Argument("target"),
    Argument(["--count", "-c"]; default = ["1"]),
    Argument("--tag"; repeat = true),
    Argument("--help"; flag = true, stop = true),
    Argument("--verbose"; flag = true),
    Argument("--profile"; choices = ["debug", "release"], default = ["debug"]),
    Argument("--label"; regex = r"^[a-z0-9_-]+$", default = String[])
], [
    Command("run", [
        Argument("mode"),
        Argument(["--threads", "-t"]; default = ["4"]),
        Argument("--repeat"; repeat = 1:3, choices = ["once", "twice", "thrice"]),
        Argument("--dry-run"; flag = true),
        Argument("--help"; flag = true, stop = true)
    ], [
        Command("fast", [
            Argument("--limit"; default = ["10"]),
            Argument("--extra"; repeat = true)
        ]),
        Command("slow", [
            Argument("--interval"; default = ["5"])
        ])
    ]),
    Command("tools", subtools)
])

args = parser(error_mode = :return)

if !args.success
    if args.error !== nothing
        println(stderr, sprint(showerror, args.error))
    else
        println(stderr, "Failed to parse arguments")
    end
    exit(1)
end

@show args.command

help_hits = args["--help", 0, Int]
@show help_hits
help_hits > 0 && exit(0)

@show args["target"]
@show args["--count", Int]
@show args["--tag", Vector{String}]
@show args["--verbose", Bool]
@show args["--profile"]
@show args["--label", Vector{String}]

if !isempty(args.command)
    if args.command[1] == "run"
        @show args["mode", 1]
        @show args["--threads", 1, Int]
        @show args["--repeat", 1, +]
        @show args["--dry-run", 1, Bool]
        if length(args.command) > 1
            if args.command[2] == "fast"
                @show args["--limit", 2, Int]
                @show args["--extra", 2, +]
            elseif args.command[2] == "slow"
                @show args["--interval", 2, Int]
            end
        end
    elseif args.command[1] == "tools"
        @show args["--tool", 1]
        @show args["--list", 1, Bool]
        if length(args.command) > 1 && args.command[2] == "set"
            @show args["key", 2]
            @show args["value", 2]
        end
    end
end
