#!/usr/bin/env julia
using Cliff

subtools = Parser(
    arguments = [
        Argument("--tool"; choices = ["hammer", "saw", "wrench"], default = "hammer"),
        Argument("--list"; flag = true, default = "no", flag_value = "yes")
    ],
    commands = [
        Command("set";
            arguments = [
                Argument("key"),
                Argument("value")
            ]
        )
    ]
)

parser = Parser(
    name = "example",
    arguments = [
        Argument("target"),
        Argument(["--count", "-c"]; default = "1"),
        Argument("--tag"; repeat = true),
        Argument("--help"; flag = true, stop = true),
        Argument("--verbose"; flag = true),
        Argument("--profile"; choices = ["debug", "release"], default = "debug"),
        Argument("--label"; regex = r"^[a-z0-9_-]+$", default = String[])
    ],
    commands = [
        Command("run";
            arguments = [
                Argument("mode"),
                Argument(["--threads", "-t"]; default = "4"),
                Argument("--repeat"; repeat = 1:3, choices = ["once", "twice", "thrice"]),
                Argument("--dry-run"; flag = true),
                Argument("--help"; flag = true, stop = true)
            ],
            commands = [
                Command("fast";
                    arguments = [
                        Argument("--limit"; default = "10"),
                        Argument("--extra"; repeat = true)
                    ]
                ),
                Command("slow";
                    arguments = [
                        Argument("--interval"; default = "5")
                    ]
                )
            ]
        ),
        Command("tools", subtools)
    ]
)

args = parser(error_mode = :return)

function describe_level(io::IO, args::Parsed, depth::Int, root_label::String)
    level = args.levels[depth]
    label = depth == 1 ? root_label : args.command[depth - 1]
    println(io, "level $(depth - 1) ($(label)):")
    for argument in level.arguments
        name = argument.names[1]
        values = args[name, depth - 1, Vector{String}]
        line = "  $(name): $(repr(values))"
        if argument.flag && argument.max_occurs == 1
            line *= " (bool=$(args[name, depth - 1, Bool]))"
        end
        println(io, line)
    end
end

println("success: $(args.success)")
println("complete: $(args.complete)")
println("stopped: $(args.stopped)")
println("stop argument: $(args.stop_argument === nothing ? "(none)" : args.stop_argument)")
if args.error !== nothing
    println("error kind: $(args.error.kind)")
    println("error message: $(args.error.message)")
end

println("command path: $(args.command)")
for depth in eachindex(args.levels)
    describe_level(stdout, args, depth, parser.name == "" ? "root" : parser.name)
end

println("count as Int: ", args["--count", Int])
println("tags: ", repr(args["--tag", Vector{String}]))
println("profile: ", args["--profile"])

label_values = args["--label", Vector{String}]
println("label: ", isempty(label_values) ? "(none)" : label_values[1])

if args.success && !isempty(args.command)
    if args.command[1] == "run"
        println("threads (Int): ", args["--threads", Int])
    elseif args.command[1] == "tools"
        println("tool: ", args["--tool"])
    end
end
