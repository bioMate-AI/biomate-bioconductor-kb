#!/usr/bin/env python3
"""Build tasks.jsonl for the nextflow_coding execution-graded benchmark.

12 tasks: 4 convert / 4 fix / 4 write. All SMALL and tool-free: the reference
solutions use only coreutils (echo/cat/printf/wc/sort/tr/head) so they parse
(Tier A), stub-run (Tier B) and really run (Tier C) in any environment that has
nextflow + Java, with NO bioinformatics binaries.

Each record:
  id, kind ("convert"|"fix"|"write"), prompt,
  source_lang + source   (convert only: the script to port)
  broken_nf + bug        (fix only: the broken .nf and a 1-line bug description)
  expected_contract:
     tierB_stub : bool   -- a correct solution must stub-run cleanly
     runnable   : bool   -- Tier C eligible (real run + output-file contract)
     outputs    : [ {glob, contains:[substr,...]} ]  -- Tier C file contract

Run: python3 build_tasks.py  ->  writes tasks.jsonl
"""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))

DSL2_NOTE = ("Write a complete, self-contained Nextflow DSL2 script (start with "
             "`nextflow.enable.dsl=2`, define process block(s) with input:/output:/script:, "
             "and an entry `workflow {}`). Use ONLY coreutils (echo/cat/printf/wc/sort/tr/head) "
             "in script blocks — no bioinformatics tools. Output ONLY the .nf file content, no prose, "
             "no markdown fences.")

TASKS = []

# ----------------------------------------------------------------------------
# CONVERT (4) — port an existing script to a Nextflow DSL2 process/workflow
# ----------------------------------------------------------------------------
TASKS.append({
    "id": "convert_bash_greeting",
    "kind": "convert",
    "source_lang": "bash",
    "source": (
        "#!/usr/bin/env bash\n"
        "# Takes a name and writes a greeting file.\n"
        'NAME="$1"\n'
        'echo "Hello, ${NAME}!" > greeting.txt\n'
    ),
    "prompt": (
        "Convert this bash script into a Nextflow DSL2 pipeline. The process must take the "
        "name as a `val` input and write the greeting to `greeting.txt` as a `path` output. "
        "The entry workflow must run the process on the single value `BioMate`, so the pipeline "
        "produces a greeting.txt containing exactly `Hello, BioMate!`.\n\n" + DSL2_NOTE
    ),
    "expected_contract": {
        "tierB_stub": True, "runnable": True,
        "outputs": [{"glob": "greeting.txt", "contains": ["Hello, BioMate!"]}],
    },
})

TASKS.append({
    "id": "convert_bash_wordcount",
    "kind": "convert",
    "source_lang": "bash",
    "source": (
        "#!/usr/bin/env bash\n"
        "# Count the words in a sentence.\n"
        'echo "the quick brown fox" | wc -w > wordcount.txt\n'
    ),
    "prompt": (
        "Convert this bash script into a Nextflow DSL2 pipeline. The process must take a sentence "
        "as a `val` input, count its words with `wc -w`, and write the count to `wordcount.txt`. "
        "The entry workflow must run the process on the sentence `the quick brown fox`, so "
        "wordcount.txt contains `4`.\n\n" + DSL2_NOTE
    ),
    "expected_contract": {
        "tierB_stub": True, "runnable": True,
        "outputs": [{"glob": "wordcount.txt", "contains": ["4"]}],
    },
})

TASKS.append({
    "id": "convert_python_sort",
    "kind": "convert",
    "source_lang": "python",
    "source": (
        "#!/usr/bin/env python3\n"
        "lines = ['banana', 'apple', 'cherry']\n"
        "with open('sorted.txt', 'w') as fh:\n"
        "    for l in sorted(lines):\n"
        "        fh.write(l + '\\n')\n"
    ),
    "prompt": (
        "Port this Python script to a Nextflow DSL2 pipeline. A single process must emit the three "
        "fruits `banana`, `apple`, `cherry` in alphabetical order into `sorted.txt` (use the "
        "coreutils `sort` command in the script block, not Python). So sorted.txt must start with "
        "`apple` and also contain `banana` and `cherry`.\n\n" + DSL2_NOTE
    ),
    "expected_contract": {
        "tierB_stub": True, "runnable": True,
        "outputs": [{"glob": "sorted.txt", "contains": ["apple", "banana", "cherry"]}],
    },
})

TASKS.append({
    "id": "convert_snakemake_chain",
    "kind": "convert",
    "source_lang": "snakemake",
    "source": (
        'rule all:\n'
        '    input: "upper.txt"\n\n'
        'rule make_seed:\n'
        '    output: "seed.txt"\n'
        '    shell: "echo hello > {output}"\n\n'
        'rule to_upper:\n'
        '    input: "seed.txt"\n'
        '    output: "upper.txt"\n'
        "    shell: \"tr 'a-z' 'A-Z' < {input} > {output}\"\n"
    ),
    "prompt": (
        "Convert this two-rule Snakemake workflow into a Nextflow DSL2 pipeline with TWO chained "
        "processes. The first process writes `hello` into `seed.txt`; the second process takes that "
        "file as a `path` input, upper-cases it with `tr 'a-z' 'A-Z'`, and writes `upper.txt`. "
        "Wire the first process's output channel into the second so the final upper.txt contains "
        "`HELLO`.\n\n" + DSL2_NOTE
    ),
    "expected_contract": {
        "tierB_stub": True, "runnable": True,
        "outputs": [{"glob": "upper.txt", "contains": ["HELLO"]}],
    },
})

# ----------------------------------------------------------------------------
# FIX (4) — repair a specific real bug in a broken .nf
# ----------------------------------------------------------------------------
TASKS.append({
    "id": "fix_dsl1_dsl2_mix",
    "kind": "fix",
    "bug": "Declares `nextflow.enable.dsl=1` while using DSL2 `workflow {}` + process-call syntax; "
           "modern Nextflow rejects DSL1. Fix: set dsl=2. (Caught at Tier A / -preview.)",
    "broken_nf": (
        "#!/usr/bin/env nextflow\n"
        "nextflow.enable.dsl=1\n\n"
        "process GREET {\n"
        '    output:\n'
        '    path "g.txt"\n'
        '    script:\n'
        '    """\n'
        '    echo "ready" > g.txt\n'
        '    """\n'
        "}\n\n"
        "workflow {\n"
        "    GREET()\n"
        "}\n"
    ),
    "prompt": (
        "This Nextflow script fails to run. Identify and fix the bug so it parses and runs, "
        "producing g.txt containing `ready`. Change as little as possible. "
        "Output ONLY the corrected .nf content, no prose, no markdown fences."
    ),
    "expected_contract": {
        "tierB_stub": True, "runnable": True,
        "outputs": [{"glob": "g.txt", "contains": ["ready"]}],
    },
})

TASKS.append({
    "id": "fix_missing_output_emit",
    "kind": "fix",
    "bug": "Downstream process reads `MAKE.out.seed` but MAKE's output has no `emit: seed` name. "
           "Fix: add `, emit: seed` (or reference `.out`). (Passes Tier A; caught at Tier B / -stub-run.)",
    "broken_nf": (
        "#!/usr/bin/env nextflow\n"
        "nextflow.enable.dsl=2\n\n"
        "process MAKE {\n"
        "    output:\n"
        '    path "seed.txt"\n'
        "    script:\n"
        '    """\n'
        '    echo hello > seed.txt\n'
        '    """\n'
        "}\n\n"
        "process UPPER {\n"
        "    input:\n"
        "    path f\n"
        "    output:\n"
        '    path "upper.txt", emit: upper\n'
        "    script:\n"
        '    """\n'
        "    tr 'a-z' 'A-Z' < $f > upper.txt\n"
        '    """\n'
        "}\n\n"
        "workflow {\n"
        "    MAKE()\n"
        "    UPPER(MAKE.out.seed)\n"
        "}\n"
    ),
    "prompt": (
        "This Nextflow script parses but fails when run: the workflow references an output emit name "
        "that the upstream process never declares. Fix the wiring so the pipeline runs and produces "
        "upper.txt containing `HELLO`. Change as little as possible. "
        "Output ONLY the corrected .nf content, no prose, no markdown fences."
    ),
    "expected_contract": {
        "tierB_stub": True, "runnable": True,
        "outputs": [{"glob": "upper.txt", "contains": ["HELLO"]}],
    },
})

TASKS.append({
    "id": "fix_channel_cardinality",
    "kind": "fix",
    "bug": "Process TWO declares 2 input channels (val a; val b) but the workflow calls it with 1 "
           "argument. Fix: pass both inputs. (Caught at Tier A / -preview.)",
    "broken_nf": (
        "#!/usr/bin/env nextflow\n"
        "nextflow.enable.dsl=2\n\n"
        "process TWO {\n"
        "    input:\n"
        "    val a\n"
        "    val b\n"
        "    output:\n"
        '    path "pair.txt"\n'
        "    script:\n"
        '    """\n'
        '    echo "$a $b" > pair.txt\n'
        '    """\n'
        "}\n\n"
        "workflow {\n"
        "    TWO(Channel.of('left'))\n"
        "}\n"
    ),
    "prompt": (
        "This Nextflow script fails because the process input-channel cardinality does not match how "
        "the workflow invokes it. Fix it so the pipeline runs and produces pair.txt containing "
        "`left right`. Change as little as possible. "
        "Output ONLY the corrected .nf content, no prose, no markdown fences."
    ),
    "expected_contract": {
        "tierB_stub": True, "runnable": True,
        "outputs": [{"glob": "pair.txt", "contains": ["left right"]}],
    },
})

TASKS.append({
    "id": "fix_bad_process_invocation",
    "kind": "fix",
    "bug": "Workflow calls an undefined process `GREET_USER()`; the defined process is `GREET`. "
           "Fix: call the correct name. (Caught at Tier A / -preview.)",
    "broken_nf": (
        "#!/usr/bin/env nextflow\n"
        "nextflow.enable.dsl=2\n\n"
        "process GREET {\n"
        "    output:\n"
        '    path "hi.txt"\n'
        "    script:\n"
        '    """\n'
        '    echo "hi there" > hi.txt\n'
        '    """\n'
        "}\n\n"
        "workflow {\n"
        "    GREET_USER()\n"
        "}\n"
    ),
    "prompt": (
        "This Nextflow script fails because the workflow invokes a process that is not defined. "
        "Fix it so the pipeline runs and produces hi.txt containing `hi there`. Change as little as "
        "possible. Output ONLY the corrected .nf content, no prose, no markdown fences."
    ),
    "expected_contract": {
        "tierB_stub": True, "runnable": True,
        "outputs": [{"glob": "hi.txt", "contains": ["hi there"]}],
    },
})

# ----------------------------------------------------------------------------
# WRITE (4) — author a minimal pipeline from a spec
# ----------------------------------------------------------------------------
TASKS.append({
    "id": "write_status_pipeline",
    "kind": "write",
    "prompt": (
        "Write a minimal Nextflow DSL2 pipeline with a single process named STATUS that writes the "
        "literal text `pipeline-ok` into a file `status.txt` (a `path` output). The entry workflow "
        "runs STATUS once.\n\n" + DSL2_NOTE
    ),
    "expected_contract": {
        "tierB_stub": True, "runnable": True,
        "outputs": [{"glob": "status.txt", "contains": ["pipeline-ok"]}],
    },
})

TASKS.append({
    "id": "write_two_step_count",
    "kind": "write",
    "prompt": (
        "Write a Nextflow DSL2 pipeline with two chained processes. GENERATE writes the numbers 1 "
        "through 5, one per line, into `nums.txt`. SUMMARIZE takes nums.txt as a `path` input, counts "
        "its lines with `wc -l`, and writes just the count into `count.txt`. Wire GENERATE's output "
        "channel into SUMMARIZE so count.txt contains `5`.\n\n" + DSL2_NOTE
    ),
    "expected_contract": {
        "tierB_stub": True, "runnable": True,
        "outputs": [{"glob": "count.txt", "contains": ["5"]}],
    },
})

TASKS.append({
    "id": "write_fanout_collect",
    "kind": "write",
    "prompt": (
        "Write a Nextflow DSL2 pipeline that fans out over three values. Process TAG takes each of the "
        "values `a`, `b`, `c` (as a `val` input, driven by `Channel.of('a','b','c')`) and writes a file "
        "`${v}.tag` whose content is `tag:${v}`. Process COLLECT gathers ALL of TAG's output files "
        "(use `.collect()`), concatenates them with `cat`, and writes `all.txt`. The final all.txt must "
        "contain `tag:a`, `tag:b`, and `tag:c`.\n\n" + DSL2_NOTE
    ),
    "expected_contract": {
        "tierB_stub": True, "runnable": True,
        "outputs": [{"glob": "all.txt", "contains": ["tag:a", "tag:b", "tag:c"]}],
    },
})

TASKS.append({
    "id": "write_param_default",
    "kind": "write",
    "prompt": (
        "Write a Nextflow DSL2 pipeline that uses a pipeline parameter. Declare `params.greeting = 'hi'`. "
        "A single process MESSAGE must write `${params.greeting}, world` into `msg.txt`. With the default "
        "parameter value, msg.txt must contain `hi, world`.\n\n" + DSL2_NOTE
    ),
    "expected_contract": {
        "tierB_stub": True, "runnable": True,
        "outputs": [{"glob": "msg.txt", "contains": ["hi, world"]}],
    },
})

# ----------------------------------------------------------------------------
def main():
    out = os.path.join(HERE, "tasks.jsonl")
    kinds = {}
    with open(out, "w") as f:
        for t in TASKS:
            kinds[t["kind"]] = kinds.get(t["kind"], 0) + 1
            f.write(json.dumps(t) + "\n")
    print(f"wrote {out}: {len(TASKS)} tasks {kinds}")

if __name__ == "__main__":
    main()
