#!/usr/bin/env nextflow
/*
 * lab_automation/get_pylabrobot_documentation_liquid
 * Get the documentation for a specific section of the PyLabRobot tutorial.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// No value parameters

process GET_PYLABROBOT_DOCUMENTATION_LIQUID {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("get_pylabrobot_documentation_liquid_results.json"), emit: results
    tuple val(meta), path("get_pylabrobot_documentation_liquid_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    # No value parameters

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import urllib.request
import json
import zipfile
import io
import json
import os

MAX_DOC_CHARS = 50000  # Maximum documentation characters

def auto_convert(val):
    # Auto-convert string to appropriate type
    if val is None or val == '' or val == 'null':
        return None
    # Try bool
    if isinstance(val, str) and val.lower() in ('true', 'false'):
        return val.lower() == 'true'
    # Try JSON for lists and dicts
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass
    # Try int
    try:
        if isinstance(val, str) and '.' not in val:
            return int(val)
    except ValueError:
        pass
    # Try float
    try:
        return float(val)
    except ValueError:
        pass
    # Return as string
    return val

def _load_pylabrobot_tutorial_content(section: str) -> str:
    '''Load PLR tutorial/docs text from multiple sources with graceful fallback.

    Precedence:
      1) Docs from installed pylabrobot package (docs/user_guide/...)
      2) Introspect installed package (pylabrobot)
    '''
    docs: list[str] = []

    # 1) Fetch from GitHub repo zip (pinned commit by default)
    repo = "PyLabRobot/pylabrobot"
    ref = "106aef9c8699ceb826d8c9c894eba304a082f24d"

    gh_docs = _collect_docs_from_github_zip(repo=repo, ref=ref, section=section)

    if gh_docs and isinstance(gh_docs[0], tuple):
        if section == "liquid":
            formatted = _format_liquid_user_guide(gh_docs)  # returns single string
            if formatted:
                docs.append(formatted)
        else:
            # Concatenate texts in stable order
            docs.append("\\n\\n".join(text for _, text in gh_docs if text))
    else:
        docs.extend(gh_docs)

    if not docs:
        return ""

    text = "\\n\\n".join([d for d in docs if d])
    if len(text) > MAX_DOC_CHARS:
        text = text[:_MAX_DOC_CHARS]
    return text

def _collect_docs_from_github_zip(repo: str, ref: str, section: str) -> list[tuple[str, str]] | list[str]:
    '''Download GitHub repo zip and extract user_guide docs for the section.

    Uses:
      - docs/user_guide/00_liquid-handling for section == "liquid"
      - docs/user_guide/01_material-handling for section == "material"
    '''
    if not repo:
        return []

    # Try commit zip first if ref looks like a commit SHA, then branch, then tag
    url = f"https://github.com/{repo}/archive/{ref}.zip"

    data = None
    try:
        with urllib.request.urlopen(url, timeout=20) as resp:
            data = resp.read()
    except Exception:
        return []

    # Restrict to specific subfolders by section
    if section == "liquid":
        # Only the Hamilton STAR(let) folder for now
        target_subdir = "docs/user_guide/00_liquid-handling/hamilton-star"
    else:
        target_subdir = "docs/user_guide/01_material-handling"
    target_subdir = target_subdir.lower()

    collected_named: list[tuple[str, str]] = []
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            # Select relevant names within target_subdir
            candidate_names = []
            for name in zf.namelist():
                lower = name.lower()
                if target_subdir not in lower:
                    continue
                if lower.endswith("/"):
                    continue
                if not (
                    lower.endswith(".md")
                    or lower.endswith(".rst")
                    or lower.endswith(".txt")
                    or lower.endswith(".ipynb")
                ):
                    continue
                candidate_names.append(name)

            # Deterministic order; for liquid, ensure basic.ipynb first
            if section == "liquid":
                candidate_names.sort(key=lambda n: (0 if n.lower().endswith("basic.ipynb") else 1, n.lower()))
            else:
                candidate_names.sort(key=lambda n: n.lower())

            for name in candidate_names:
                lower = name.lower()
                try:
                    with zf.open(name) as f:
                        content_bytes = f.read()
                        if lower.endswith(".ipynb"):
                            try:
                                nb = json.loads(content_bytes.decode("utf-8"))
                            except Exception:
                                continue
                            cells = nb.get("cells") or nb.get("worksheets", [{}])[0].get("cells", [])
                            parts = []
                            for c in cells:
                                ctype = c.get("cell_type") or c.get("type")
                                src = c.get("source") or c.get("input") or []
                                if isinstance(src, list):
                                    src = "".join(src)
                                if not isinstance(src, str):
                                    continue
                                if ctype == "markdown":
                                    parts.append(src)
                                elif ctype == "code":
                                    keep_lines = []
                                    for line in src.splitlines():
                                        l = line.strip()
                                        if l.startswith("#"):
                                            continue
                                        if "pylabrobot" in l and ("import " in l or "from " in l):
                                            keep_lines.append(l)
                                    if keep_lines:
                                        parts.append("Code refs:\\n" + "\\n".join(keep_lines[:20]))
                                if sum(len(p) for p in parts) > 5000:
                                    break
                            text = "\\n\\n".join(parts)
                        else:
                            try:
                                text = content_bytes.decode("utf-8")
                            except Exception:
                                text = str(content_bytes)
                        if text:
                            collected_named.append((lower, text[:5000]))
                except Exception:
                    continue
    except Exception:
        return []

    return collected_named

def _format_liquid_user_guide(named_docs: list[tuple[str, str]]) -> str:
    '''Assemble liquid-handling docs into a curated order with headings.

    named_docs: list of (filename_lower, text) from GitHub.
    Returns a single formatted string.
    '''
    sections = [
        (
            "Getting started with liquid handling on a Hamilton STAR(let)",
            ["/hamilton-star/", "basic.ipynb", "basic", "getting-started"],
        ),
        ("iSWAP Module", ["iswap"]),
        ("Liquid level detection on Hamilton STAR(let)", ["liquid-level", "lld", "level_detection", "level-detection"]),
        ("Z-probing", ["z-probing", "z_probing", "z-probing", "zprobing", "z-prob"]),
        ("Foil", ["foil"]),
        ("Using the 96 head", ["96", "head", "mca", "96-head", "head-96"]),
        (
            "Using “Hamilton Liquid Classes” with Pylabrobot",
            ["liquid-classes", "liquid_classes", "hamilton-liquid-classes"],
        ),
    ]

    used: set[int] = set()
    out_parts: list[str] = []

    def pick_first(keywords: list[str]) -> str:
        for idx, (fname, text) in enumerate(named_docs):
            if idx in used:
                continue
            if any(k in fname for k in keywords):
                used.add(idx)
                return text
        return ""

    for heading, keywords in sections:
        text = pick_first(keywords)
        if text:
            out_parts.append(f"## {heading}\\n\\n{text}")

    # Append any remaining docs not matched, to avoid losing content
    for idx, (fname, text) in enumerate(named_docs):
        if idx not in used and text:
            # Derive a nice title from filename
            leaf = fname.rsplit("/", 1)[-1]
            title = leaf.replace("_", " ").replace("-", " ")
            title = title.rsplit(".", 1)[0].strip().title()
            out_parts.append(f"## {title}\\n\\n{text}")

    return "\\n\\n".join(out_parts)

def get_pylabrobot_documentation_liquid() -> str:
    '''Get the documentation for a specific section of the PyLabRobot tutorial.'''
    tutorial_content = '''Notes:
- Use hamilton_96_tiprack_1000uL_filter instead of HTF (deprecated). Note the capital L in uL.
- Use Cor_96_wellplate_360ul_Fb instead of Corning_96_wellplate_360ul_Fb.
- You must name all your plates, tip racks, and carriers.
- Assign labware into carriers via slot assignment (tip_car[0] = tiprack). Assign plates to rails using lh.deck.assign_child_resource(plate_car, rails=14).
- Rails must be between -4 and 32.
- Make sure most liquid handling operations are done with async/await.
- There are some methods that are not async, including lh.summary(). Do not use await for these methods.
- When picking up tips with multiple channels, use a flat list of tips. Do not use a list of lists. '''

    tutorial_content += _load_pylabrobot_tutorial_content("liquid")

    return tutorial_content

# Execute the function
try:
    result = get_pylabrobot_documentation_liquid(

    )
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# Save results
output_data = {
    "success": success,
    "function": "get_pylabrobot_documentation_liquid",
    "domain": "lab_automation",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("get_pylabrobot_documentation_liquid_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("get_pylabrobot_documentation_liquid_output.txt", "w") as f:
    f.write("Biomni: Get Pylabrobot Documentation Liquid" + NL)
    f.write("=" * 60 + NL + NL)
    if success:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, dict):
            for key, value in result.items():
                f.write(f"{key}: {value}" + NL)
        else:
            f.write(str(result))
    else:
        f.write(f"ERROR: {error_msg}" + NL)

if not success:
    exit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biomni_function: "get_pylabrobot_documentation_liquid"
    END_VERSIONS
    """
}

workflow GET_PYLABROBOT_DOCUMENTATION_LIQUID_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GET_PYLABROBOT_DOCUMENTATION_LIQUID(ch_input)

    emit:
    results = GET_PYLABROBOT_DOCUMENTATION_LIQUID.out.results
    output = GET_PYLABROBOT_DOCUMENTATION_LIQUID.out.output
    versions = GET_PYLABROBOT_DOCUMENTATION_LIQUID.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GET_PYLABROBOT_DOCUMENTATION_LIQUID_WORKFLOW(ch_input)

    GET_PYLABROBOT_DOCUMENTATION_LIQUID_WORKFLOW.out.output.view { "Output: $it" }
}
