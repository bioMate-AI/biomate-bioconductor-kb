"""Exercise actual pinned Hermes registry code with BioMate's read-only adapter.

Usage: python3 smoke_hermes_registry.py --hermes-source /path/to/pinned/source
No model is called; this is a component integration smoke test, not an agent eval.
"""
import argparse
import copy
import hashlib
import json
import sys
from pathlib import Path

from fixture_adapter import example_plan, register_fixture_tools


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--hermes-source', required=True, type=Path)
    args = parser.parse_args()
    manifest = json.loads(Path(__file__).with_name('upstream-source-manifest.json').read_text())
    upstream = next(r for r in manifest['repositories'] if r['repository'] == 'NousResearch/hermes-agent')
    required = ['tools/registry.py', 'tools/__init__.py', 'hermes_constants.py']
    for name in required:
        entry = next(f for f in upstream['files'] if f['path'] == name)
        actual = hashlib.sha256((args.hermes_source / name).read_bytes()).hexdigest()
        if actual != entry['sha256']:
            raise ValueError(f'Pinned source hash mismatch: {name}')

    # Enforce no network or subprocess execution during this component experiment.
    def no_external_execution(event, _args):
        if event in ('socket.connect', 'socket.getaddrinfo', 'subprocess.Popen', 'os.system'):
            raise RuntimeError('External execution is disabled in the registry smoke test')
    sys.addaudithook(no_external_execution)
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(args.hermes_source.resolve()))
    from tools.registry import ToolRegistry

    checks = []
    for case in ('compare_all_applicable_tools', 'two_inhibitors_three_targets', 'peptide_shortlist_from_prior_run'):
        registry = ToolRegistry()
        register_fixture_tools(registry, case)
        def call(name, payload):
            return json.loads(registry.dispatch('biomate_' + name, payload))
        def check(name, passed):
            checks.append({'case_id': case, 'check': name, 'passed': bool(passed)})
        check('only_three_readonly_tools', set(registry.get_all_tool_names()) ==
              {'biomate_read_context', 'biomate_list_workflows', 'biomate_validate_plan'})
        check('context_bound_to_case', call('read_context', {})['result']['case_id'] == case)
        check('catalog_exhaustion_explicit', call('list_workflows', {})['result']['next_page'] is None)
        plan = example_plan(case)
        result = call('validate_plan', plan)
        check('complete_plan_accepted_without_execution', result['ok'] and not result['result']['execution_authorized'])
        broken = copy.deepcopy(plan); broken['steps'].pop()
        check('missing_case_rejected', not call('validate_plan', broken)['ok'])
        broken = copy.deepcopy(plan); broken['steps'][0]['nextflow_path'] = 'not_available.nf'
        check('unavailable_workflow_rejected', not call('validate_plan', broken)['ok'])
        broken = copy.deepcopy(plan); broken['steps'][0]['depends_on'] = [2]; broken['steps'][1]['depends_on'] = [1]
        check('cycle_rejected', not call('validate_plan', broken)['ok'])
        broken = copy.deepcopy(plan); broken['coverage_axes'] = {}
        check('model_cannot_shrink_expected_scope', not call('validate_plan', broken)['ok'])
        check('context_cannot_be_overridden', not call('read_context', {'case_id': 'other'})['ok'])
        check('submission_tool_absent', 'error' in call('submit_plan', plan))
    failed = sum(not c['passed'] for c in checks)
    print(json.dumps({'scope': 'Actual Hermes registry + synthetic BioMate tools + provisional graph validator; no model or scientific execution.',
                      'hermes_revision': upstream['revision'], 'total': len(checks), 'failed': failed,
                      'passed': len(checks) - failed, 'checks': checks}, indent=2))
    return bool(failed)


if __name__ == '__main__':
    sys.exit(main())
