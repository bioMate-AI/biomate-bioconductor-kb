#!/usr/bin/env python3
"""Test runner for Galaxy-unique Nextflow workflows.
Extracts the PYEOF Python block + env vars from each main.nf,
runs them in a temp dir, checks the output JSON for success.
"""

import os, re, subprocess, tempfile, json, sys

PYTHON = "/home/yzhang/biomate/.venv_workflow_test/bin/python3"
NF_BASE = "/home/yzhang/biomate/backend/biomni_workflows/nextflow_nfcore/subworkflows"

# Galaxy-unique workflows to test (have .ga source files)
TARGETS = [
    "molecular_biology/get_coding_sequences",
    "molecular_biology/find_orfs_in_frame",
    "bioengineering/first_order",
    "systems_biology/dimerization_odes",
    "systems_biology/model_protein_dimerization_network",
    "synthetic_biology/analyze_bifurcation_diagram",
    "microbiology/simulate_microbial_population_dynamics",
]

def extract_env_and_python(nf_path):
    """Parse main.nf: extract shell export lines and PYEOF Python block."""
    with open(nf_path) as f:
        content = f.read()

    # Find the script: block (between first """ and PYEOF section)
    # Extract export lines (PARAM_xxx=...)
    export_lines = re.findall(r'^\s*(export PARAM_\w+=".+?")', content, re.MULTILINE)

    # Extract Python block between 'PYEOF' markers
    pyeof_match = re.search(r"python3 << 'PYEOF'\n(.*?)\nPYEOF", content, re.DOTALL)
    if not pyeof_match:
        return None, None
    py_code = pyeof_match.group(1)
    return export_lines, py_code

def get_default_param_value(nf_path, param_name):
    """Extract the default value for a param from the params section."""
    with open(nf_path) as f:
        content = f.read()
    # e.g. params.sequence = 'ATGAAA...'
    m = re.search(rf"params\.{param_name}\s*=\s*'([^']*)'", content)
    if m:
        return m.group(1)
    m = re.search(rf'params\.{param_name}\s*=\s*"([^"]*)"', content)
    if m:
        return m.group(1)
    m = re.search(rf'params\.{param_name}\s*=\s*(\S+)', content)
    if m:
        val = m.group(1)
        if val == 'null':
            return ''
        return val
    return ''

def resolve_exports(export_lines, nf_path):
    """Evaluate export lines to get env var assignments.
    Handles simple ${params.xxx} style, null coalescing, and literal strings.
    """
    env = {}
    for line in export_lines:
        # export PARAM_FOO="VALUE"  — strip to get var name and value
        m = re.match(r'export (PARAM_\w+)="(.*?)"', line.strip())
        if not m:
            continue
        var_name = m.group(1)
        raw_val = m.group(2)

        # Resolve ${params.xxx} or ${(params.x != null ? params.x : params.y)...}
        # For simplicity: find all param references and substitute
        param_refs = re.findall(r'params\.(\w+)', raw_val)
        resolved = raw_val
        for pref in param_refs:
            pval = get_default_param_value(nf_path, pref)
            # Replace in the string (rough substitution)
            resolved = re.sub(rf'\$\{{params\.{pref}[^}}]*\}}', pval, resolved)
            resolved = re.sub(rf'params\.{pref}', f'"{pval}"', resolved)
        # Clean up any remaining Groovy interpolation artefacts
        resolved = re.sub(r'\$\{[^}]+\}', '', resolved)
        resolved = re.sub(r'\?\.toString\(\)', '', resolved)
        resolved = re.sub(r"\?\.replace\('[^']+', '[^']+'\)", '', resolved)
        resolved = re.sub(r" \?: '[^']+'", '', resolved)
        resolved = resolved.strip()
        env[var_name] = resolved
    return env

results = {}

for target in TARGETS:
    nf_path = f"{NF_BASE}/{target}/main.nf"
    workflow_name = target.split('/')[-1]
    print(f"\n{'='*60}")
    print(f"Testing: {target}")

    if not os.path.exists(nf_path):
        results[target] = ("SKIP", "main.nf not found")
        print(f"  SKIP: file not found")
        continue

    export_lines, py_code = extract_env_and_python(nf_path)
    if not py_code:
        results[target] = ("SKIP", "no PYEOF block found")
        print(f"  SKIP: no PYEOF block")
        continue

    env = resolve_exports(export_lines, nf_path)

    with tempfile.TemporaryDirectory() as tmpdir:
        # Write the Python script
        script_path = os.path.join(tmpdir, "run.py")
        with open(script_path, 'w') as f:
            f.write(py_code)

        # Build environment
        run_env = os.environ.copy()
        run_env.update(env)
        # matplotlib non-interactive
        run_env['MPLBACKEND'] = 'Agg'

        try:
            result = subprocess.run(
                [PYTHON, script_path],
                cwd=tmpdir,
                env=run_env,
                capture_output=True,
                text=True,
                timeout=120
            )
        except subprocess.TimeoutExpired:
            results[target] = ("TIMEOUT", "exceeded 120s")
            print(f"  TIMEOUT: exceeded 120s")
            continue

        # Check output
        json_file = os.path.join(tmpdir, f"{workflow_name}_results.json")
        txt_file  = os.path.join(tmpdir, f"{workflow_name}_output.txt")

        if result.returncode != 0:
            stderr_tail = result.stderr[-500:].strip()
            stdout_tail = result.stdout[-200:].strip()
            results[target] = ("FAIL", f"exit {result.returncode}\n  stderr: {stderr_tail}")
            print(f"  FAIL (exit {result.returncode})")
            if stderr_tail:
                print(f"  stderr: {stderr_tail[-300:]}")
            if stdout_tail:
                print(f"  stdout: {stdout_tail[-200:]}")
        elif os.path.exists(json_file):
            with open(json_file) as f:
                data = json.load(f)
            success = data.get('success', False)
            if success:
                # Show snippet of result
                r = data.get('result', '')
                snippet = str(r)[:150] if r else ''
                results[target] = ("PASS", snippet)
                print(f"  PASS ✓  result snippet: {snippet[:120]}")
            else:
                err = data.get('error', 'unknown')
                results[target] = ("FAIL", err)
                print(f"  FAIL: {err}")
        else:
            results[target] = ("FAIL", "no output JSON")
            print(f"  FAIL: no output JSON found")
            print(f"  stderr: {result.stderr[-300:]}")

# Summary
print(f"\n{'='*60}")
print("SUMMARY")
print(f"{'='*60}")
for t, (status, msg) in results.items():
    icon = "✓" if status == "PASS" else ("⚠" if status == "SKIP" else ("⏱" if status == "TIMEOUT" else "✗"))
    print(f"  {icon} {status:7s}  {t}")

pass_count = sum(1 for s, _ in results.values() if s == "PASS")
fail_count = sum(1 for s, _ in results.values() if s == "FAIL")
print(f"\n{pass_count}/{len(results)} passed, {fail_count} failed")
