using PrecompileTools

PrecompileTools.@compile_workload begin
    root_arguments = [
        Argument("input"),
        Argument("extra"; repeat = true),
        Argument(["--count", "-c"]; default = "1"),
        Argument("--tag"; repeat = true),
        Argument("--mode"; choices = ["fast", "slow"], default = "fast"),
        Argument("--name"; regex = r"^[a-z]+$", default = "guest"),
        Argument("--verbose"; flag = true),
        Argument("--help"; flag = true, stop = true),
    ]

    run_command = Command(["run", "execute"], [
        Argument("task"),
        Argument("--threads"; default = "4"),
        Argument("--debug"; flag = true),
        Argument("--level"; repeat = true, default = ["info"]),
    ], [
        Command("fast", [Argument("--limit"; default = "10")]),
        Command("slow", [Argument("--delay"; default = "5")]),
    ])

    build_command = Command(["build", "compile"], [
        Argument("target"),
        Argument("--release"; flag = true),
        Argument("--opt"; choices = ["O0", "O2", "O3"], default = "O2"),
    ])

    parser = Parser(root_arguments, [run_command, build_command])

    argv_nested = [
        "project.txt",
        "chapter1",
        "--count", "4",
        "--tag", "alpha",
        "--tag", "beta",
        "--mode", "slow",
        "--name", "cli",
        "--verbose",
        "run", "task-name",
        "--threads", "8",
        "--debug",
        "--level", "warn",
        "--level", "error",
        "fast",
        "--limit", "3",
    ]

    argv_build = [
        "docs.md",
        "--tag", "guide",
        "build", "tutorial",
        "--release",
        "--opt", "O3",
    ]

    argv_dashdash = [
        "data.csv",
        "run",
        "task",
        "--",
        "fast",
    ]

    nested_args = parser(copy(argv_nested))
    nested_args["input"]
    nested_args["extra", Vector{String}]
    nested_args["extra", 0, Vector{String}]
    nested_args["--count"]
    nested_args["--count", Int]
    nested_args["--count", 0, Int]
    nested_args["--mode"]
    nested_args["--mode", 0, String]
    nested_args["--name"]
    nested_args["--verbose", Bool]
    nested_args["--verbose", Int]
    nested_args["--verbose", 0, Int]
    nested_args["--tag", Vector{String}]
    nested_args["--tag", +]
    nested_args["--tag", 0, Vector{String}]
    nested_args["task", 1]
    nested_args["task", 1, String]
    nested_args["--threads"]
    nested_args["--threads", 1, Int]
    nested_args["--debug", 1, Bool]
    nested_args["--level", 1, Vector{String}]
    nested_args["--limit", 2]
    nested_args["--limit", 2, Int]
    nested_args.command
    nested_args.success
    nested_args.complete
    nested_args.stopped
    nested_args.stop_argument

    build_args = parser(copy(argv_build))
    build_args.command
    build_args["input"]
    build_args["--tag", Vector{String}]
    build_args["target", 1]
    build_args["--release", 1, Bool]
    build_args["--release", 1, Int]
    build_args["--opt", 1]
    build_args["--opt", 1, String]

    stop_args = parser(["--help"])
    stop_args.stopped
    stop_args.complete
    stop_args.stop_argument
    stop_args["--help", Bool]
    stop_args["--help", Int]

    dashdash_args = parser(copy(argv_dashdash))
    dashdash_args.command
    dashdash_args["input"]
    dashdash_args["extra", Vector{String}]
    dashdash_args["task", 1]
    dashdash_args["--threads", 1, Int]
    dashdash_args["--level", 1, Vector{String}]
    dashdash_args["--debug", 1, Bool]
    dashdash_args["--mode"]

    failure = parse(parser, String[]; error_mode = :return)
    failure.success
    failure.complete
    failure.error
    failure.command
end
