#!/usr/bin/env python3
"""Parse an nf-core / Nextflow subworkflow main.nf into a real dependency DAG.
Node = process/subworkflow invocation. Edge = channel output -> input data flow
(from `PROC(OTHER.out.x)` and `ch = OTHER.out.x; PROC(ch)` wiring).
Versions plumbing (`.out.versions`, `ch_versions`) is NOT a data-flow edge -> excluded.
No fabrication: if a file yields <2 invoked processes or no derivable wiring, return None.
"""
import re, sys, json

CALL = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)\s*\(')
ASSIGN = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$', re.S)
OUT_REF = re.compile(r'\b([A-Z][A-Z0-9_]*)\s*\.\s*out\b')
VAR_TOK = re.compile(r'\b([a-z_][A-Za-z0-9_]*)\b')


def read_processes(text):
    """Return {PROC_NAME: {'in':[names], 'out':[emit names]}} for process defs in file."""
    procs = {}
    for m in re.finditer(r'\bprocess\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{', text):
        name = m.group(1)
        body = _block_after(text, m.end() - 1)
        ins, outs = [], []
        # input block
        im = re.search(r'\binput:\s*(.*?)(?:\boutput:|\bscript:|\bexec:|\bshell:|\bwhen:|\Z)', body, re.S)
        if im:
            for line in im.group(1).splitlines():
                line = line.strip()
                if not line or line.startswith('//'):
                    continue
                # last identifier in path(x) / val(x) / tuple ...
                ids = re.findall(r'(?:path|val|tuple|env|stdin|file)\s*\(?\s*([A-Za-z_][A-Za-z0-9_]*)', line)
                if ids:
                    ins.append(ids[-1])
        om = re.search(r'\boutput:\s*(.*?)(?:\bscript:|\bexec:|\bshell:|\bwhen:|\binput:|\Z)', body, re.S)
        if om:
            for em in re.finditer(r'emit:\s*([A-Za-z_][A-Za-z0-9_]*)', om.group(1)):
                outs.append(em.group(1))
        procs[name] = {'in': ins, 'out': outs}
    return procs


def read_includes(text):
    """included subworkflow/module names (callable, uppercase convention)."""
    names = set()
    for m in re.finditer(r'include\s*\{([^}]*)\}', text):
        for part in m.group(1).split(';'):
            part = part.strip()
            if not part:
                continue
            # handle `A as B`
            nm = part.split(' as ')[-1].strip()
            names.add(nm)
    return names


def _block_after(text, brace_idx):
    """Return substring of the balanced {..} block starting at brace_idx (index of '{')."""
    depth = 0
    for i in range(brace_idx, len(text)):
        c = text[i]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return text[brace_idx + 1:i]
    return text[brace_idx + 1:]


def named_workflow_main(text):
    """Return (wf_name, main_block_text, take_names, header_doc) for the first NAMED workflow."""
    for m in re.finditer(r'\bworkflow\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{', text):
        name = m.group(1)
        body = _block_after(text, m.end() - 1)
        # main section
        mm = re.search(r'\bmain:\s*(.*?)(?:\bemit:|\Z)', body, re.S)
        main = mm.group(1) if mm else body
        tk = re.search(r'\btake:\s*(.*?)(?:\bmain:|\Z)', body, re.S)
        takes = []
        if tk:
            for line in tk.group(1).splitlines():
                line = line.strip()
                if line and not line.startswith('//'):
                    tok = re.match(r'([A-Za-z_][A-Za-z0-9_]*)', line)
                    if tok:
                        takes.append(tok.group(1))
        return name, main, takes, body
    return None, None, None, None


def split_statements(block):
    """Split a main block into statements at newlines where paren/bracket depth==0."""
    stmts, cur, depth = [], [], 0
    for ch in block:
        if ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth = max(0, depth - 1)
        if ch == '\n' and depth == 0:
            s = ''.join(cur).strip()
            if s:
                stmts.append(s)
            cur = []
        else:
            cur.append(ch)
    s = ''.join(cur).strip()
    if s:
        stmts.append(s)
    return stmts


def parse_dag(text):
    procs = read_processes(text)
    includes = read_includes(text)
    callable_names = set(procs) | includes
    wf_name, main, takes, body = named_workflow_main(text)
    if not main:
        return None
    take_set = set(takes or [])
    var_src = {t: set() for t in take_set}  # channel var -> set of source proc names (empty=external root)
    order = []          # invoked proc names in order
    deps = {}           # proc -> set(dep proc)
    invoked_outvar = {} # proc -> True (its .out usable)

    for stmt in split_statements(main):
        stmt = stmt.strip().rstrip(';')
        if not stmt or stmt.startswith('//'):
            continue
        assign = ASSIGN.match(stmt)
        lhs = None
        rhs = stmt
        if assign and not CALL.match(stmt):
            # pure assignment like  ch_x = PROC.out.y  (but not  PROC(...) )
            lhs, rhs = assign.group(1), assign.group(2)

        # find invoked callable in this statement (a known process/subworkflow call)
        call = CALL.match(stmt)
        invoked = None
        if call and call.group(1) in callable_names:
            invoked = call.group(1)
        elif assign:
            # RHS may itself be a call: ch = PROC(args)
            rc = CALL.match(rhs)
            if rc and rc.group(1) in callable_names:
                invoked = rc.group(1)

        # resolve dependency sources referenced in this statement (exclude versions)
        srcs = set()
        scope = rhs if lhs else stmt
        # .out refs (skip ones immediately followed by .versions)
        for om in OUT_REF.finditer(scope):
            pname = om.group(1)
            tail = scope[om.end():om.end() + 20]
            if re.match(r'\s*\.\s*versions', tail):
                continue
            if pname in callable_names:
                srcs.add(pname)
        # channel-var refs resolving to prior processes
        for vm in VAR_TOK.finditer(scope):
            v = vm.group(1)
            if v in var_src and v != lhs:
                srcs |= {s for s in var_src[v]}
        # exclude the versions accumulator
        srcs.discard('ch_versions')

        if invoked:
            if invoked not in deps:
                order.append(invoked)
                deps[invoked] = set()
            deps[invoked] |= {s for s in srcs if s != invoked}
            invoked_outvar[invoked] = True
            if lhs:
                var_src[lhs] = {invoked}
        elif lhs:
            # ch var assigned from other channels/processes
            if 'version' in lhs.lower():
                var_src[lhs] = set()  # versions accumulator, inert
            else:
                var_src[lhs] = set(srcs)

    # keep only processes we actually have as nodes
    nodes = [p for p in order]
    if len(nodes) < 2:
        return None
    # filter deps to known nodes
    for p in nodes:
        deps[p] = {d for d in deps[p] if d in deps}
    return {'wf_name': wf_name, 'nodes': nodes, 'deps': deps,
            'procs': procs, 'takes': list(take_set), 'header': body}


if __name__ == '__main__':
    import glob
    files = sys.argv[1:] or glob.glob(
        '/Users/kky/biomate-review/backend/biomni_workflows/nextflow_nfcore/subworkflows/**/main.nf',
        recursive=True)
    stats = {'parsed': 0, 'skip': 0, 'parallel': 0, 'sequential': 0, 'mixed': 0}
    samples = []
    for f in files:
        try:
            txt = open(f).read()
        except Exception:
            continue
        d = parse_dag(txt)
        if not d:
            stats['skip'] += 1
            continue
        stats['parsed'] += 1
        order_idx = {n: i + 1 for i, n in enumerate(d['nodes'])}
        depcounts = []
        for n in d['nodes']:
            depcounts.append(len(d['deps'][n]))
        if all(c == 0 for c in depcounts):
            s = 'parallel'
        elif all(c > 0 for c in depcounts[1:]):
            s = 'sequential'
        else:
            s = 'mixed'
        stats[s] += 1
        if len(samples) < 4 and s in ('parallel', 'mixed'):
            samples.append((f.split('subworkflows/')[-1], d['nodes'],
                            {n: sorted(order_idx[x] for x in d['deps'][n]) for n in d['nodes']}, s))
    print(json.dumps(stats, indent=2))
    for s in samples:
        print('---', s[0], s[3]); print('  nodes:', s[1]); print('  deps :', s[2])
