"""Dependency-aware execution for explicitly submitted workflow plans.

One coordinator owns state. Submit returns an asynchronous run id; poll checks it.
No worker threads mutate the same plan, and recovery never resubmits a recorded id.
Connections and dependencies use the chain API's one-based step numbers.
"""
from datetime import datetime, timezone
import time
from itertools import product


TERMINAL = {'succeeded', 'failed', 'blocked', 'cancelled'}


def validate_plan(steps, connections, max_parallel):
    if not steps or len(steps) > 100:
        raise ValueError('DAG plans require 1–100 steps')
    if type(max_parallel) is not int or not 1 <= max_parallel <= 16:
        raise ValueError('max_parallel must be an integer from 1 to 16')
    deps = []
    for i, step in enumerate(steps, 1):
        ds = step.get('depends_on')
        if not isinstance(ds, list):
            raise ValueError('Every DAG step must declare depends_on (use [] for roots)')
        if any(type(d) is not int or d < 1 or d > len(steps) or d == i for d in ds):
            raise ValueError('Invalid dependency on step %s' % i)
        if not step.get('nextflow_path'):
            raise ValueError('Unresolved workflow on step %s' % i)
        deps.append(set(ds))
    bound_inputs = set()
    for c in connections:
        src, dst = c.get('from_step'), c.get('to_step')
        if any(type(n) is not int or not 1 <= n <= len(steps) for n in (src, dst)):
            raise ValueError('Connection references an unknown step')
        if src not in deps[dst - 1]:
            raise ValueError('Connection source must be an explicit dependency')
        if not c.get('from_output') or not c.get('to_input'):
            raise ValueError('Connections require from_output and to_input')
        key = (dst, c['to_input'])
        if key in bound_inputs or c['to_input'] in (steps[dst - 1].get('params') or {}):
            raise ValueError('Conflicting input binding on step %s: %s' % key)
        bound_inputs.add(key)
    remaining = set(range(1, len(steps) + 1))
    while remaining:
        ready = {n for n in remaining if not deps[n - 1] & remaining}
        if not ready:
            raise ValueError('Dependency cycle in workflow plan')
        remaining -= ready


def validate_coverage(steps, axes):
    """Check the requested Cartesian product before dispatch, not only returned rows."""
    if not axes:
        return
    if not isinstance(axes, dict) or any(not isinstance(v, list) or not v or
        any(not isinstance(x, str) or not x for x in v) or len(set(v)) != len(v) for v in axes.values()):
        raise ValueError('Coverage axes must contain non-empty unique string values')
    size = 1
    for values in axes.values():
        size *= len(values)
    if size > 100:
        raise ValueError('Coverage expands beyond 100 cases; narrow the scope')
    keys = sorted(axes)
    expected = set(product(*(axes[k] for k in keys)))
    actual = set()
    for step in steps:
        dims = step.get('dimensions') or {}
        if not dims:
            continue  # Shared preprocessing / aggregation has no case identity.
        if set(dims) != set(keys):
            raise ValueError('Case dimensions must match all coverage axes')
        actual.add(tuple(dims[k] for k in keys))
    if actual != expected:
        raise ValueError('Incomplete case coverage: missing=%s unexpected=%s' %
                         (sorted(expected - actual), sorted(actual - expected)))


def bind_inputs(state, index, list_files, artifact_value, context_params, format_check=None):
    """Resolve an exact output filename; ambiguity never picks an arbitrary file.

    ``format_check(index, to_input, from_output) -> Optional[str]`` (optional) gates a no-transform
    handoff on file-format compatibility: a truthy message raises ``ValueError`` so ``run_plan`` marks
    the step failed BEFORE launch, matching the sequential path's format gate. A declared ``transform``
    is assumed to convert, so it is skipped.
    """
    params = dict(state['steps'][index].get('params') or {})
    for c in state.get('connections') or []:
        if c['to_step'] != index + 1:
            continue
        source = state['steps'][c['from_step'] - 1]
        files = list_files(source['run_id'])
        matches = [f for f in files if (f.get('filename') or f.get('name')) == c['from_output']]
        matches = {artifact_value(f): f for f in matches if artifact_value(f)}
        if len(matches) != 1:
            raise ValueError('Expected one artifact %r from step %s; found %s' %
                             (c['from_output'], c['from_step'], len(matches)))
        if format_check is not None and not c.get('transform'):
            _fmm = format_check(index, c['to_input'], c['from_output'])
            if _fmm:
                raise ValueError(_fmm)
        params[c['to_input']] = next(iter(matches))
        inherited = context_params(c, source.get('resolved_params') or source.get('params') or {})
        for key, value in inherited.items():
            if key in params and params[key] != value:
                raise ValueError('Conflicting inherited parameter: %s' % key)
            params[key] = value
    return params


def coverage_report(state):
    """Execution coverage only. Artifact presence does not establish scientific validity."""
    rows = [{
        'step': i + 1, 'workflow': s.get('workflow_name') or s.get('nextflow_path'),
        'dimensions': s.get('dimensions') or {}, 'status': s.get('status', 'pending'),
        'run_id': s.get('run_id'), 'depends_on': s.get('depends_on'),
        'parameters': s.get('resolved_params', s.get('params', {})),
        'artifacts': s.get('output_files') or [], 'error': s.get('error'),
    } for i, s in enumerate(state['steps'])]
    success = sum(r['status'] == 'succeeded' for r in rows)
    return {'expected': len(rows), 'succeeded': success,
            'complete': bool(rows) and success == len(rows), 'rows': rows,
            'coverage_axes': state.get('coverage_axes') or {},
            'scope': 'Execution coverage and provenance; scientific comparison requires validated result metrics.'}


def run_plan(state, submit, poll, save, resolve, sleep=time.sleep, clock=time.time,
             poll_interval=5, timeout=3600):
    """Run independent branches even after another fails; block its descendants.

    Persist `submitting` before dispatch. If a process dies in the dispatch/receipt
    window, recovery marks it failed for reconciliation instead of duplicating spend.
    """
    steps = state['steps']
    validate_coverage(steps, state.get('coverage_axes'))
    validate_plan(steps, state.get('connections') or [], state.get('max_parallel', 4))
    for s in steps:
        if s.get('status') == 'submitting':
            s.update(status='failed', error='Submission receipt missing; reconcile before retrying')
    while True:
        state['last_heartbeat'] = datetime.now(timezone.utc).isoformat()
        for s in steps:
            if s.get('status') != 'running':
                continue
            if not s.get('run_id'):
                s.update(status='failed', error='Running step has no run receipt')
                continue
            try:
                result = poll(s['run_id'])
                status = result.get('status')
                if status in TERMINAL:
                    s.update(status=status, output_files=result.get('output_files') or [],
                             error=result.get('error'), completed_at=datetime.now(timezone.utc).isoformat())
                    continue
            except Exception as exc:
                s['poll_error'] = str(exc)
            if clock() - s.get('submitted_at_epoch', clock()) >= timeout:
                s.update(status='failed', error='Polling timeout; run may still be active; reconcile before retrying')
        for s in steps:
            if s.get('status', 'pending') == 'pending' and any(
                steps[d - 1].get('status') in {'failed', 'blocked', 'cancelled'} for d in s['depends_on']
            ):
                s.update(status='blocked', error='An upstream dependency did not succeed')
        slots = state.get('max_parallel', 4) - sum(s.get('status') == 'running' for s in steps)
        for i, s in enumerate(steps):
            if slots <= 0:
                break
            if s.get('status', 'pending') != 'pending' or not all(
                steps[d - 1].get('status') == 'succeeded' for d in s['depends_on']
            ):
                continue
            try:
                params = resolve(state, i)
                s.update(status='submitting', resolved_params=params)
                save(state)
                run_id = submit(s, params)
                if not run_id:
                    raise ValueError('Executor returned no run id')
                s.update(status='running', run_id=run_id, submitted_at_epoch=clock(),
                         started_at=datetime.now(timezone.utc).isoformat())
                slots -= 1
            except Exception as exc:
                s.update(status='failed', error=str(exc))
            save(state)
        state['report'] = coverage_report(state)
        if all(s.get('status') in TERMINAL for s in steps):
            state['status'] = 'succeeded' if state['report']['complete'] else 'failed'
            state['completed_at'] = datetime.now(timezone.utc).isoformat()
            save(state)
            return
        save(state)
        sleep(poll_interval)
