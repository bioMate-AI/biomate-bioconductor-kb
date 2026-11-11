"""Read-only evaluation tools for a Hermes registry. No production API or job submission.

All workflow paths and candidate IDs below are synthetic contract fixtures.
The graph validators are reused from BioMate's provisional DAG increment.
"""
import copy
import importlib.util
import json
from itertools import product
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SELECTION_POLICIES = {
    'compare_all_applicable_tools': 'Compare all three methods by fixture score, lower preferred. Recommend the lowest-scoring method; no top-five shortlist.',
    'two_inhibitors_three_targets': 'Compare both inhibitors for EACH of the three targets in a 2-by-3 matrix. Lower fixture score is preferred. Do not select or exclude pairs and do not produce a top-five shortlist.',
    'peptide_shortlist_from_prior_run': 'Sum the two fixture scores per candidate; lower is preferred; select five candidates and explain the excluded candidate.',
}
spec = importlib.util.spec_from_file_location('biomate_fixture_dag', ROOT / 'backend/lib/galaxy/chain/dag.py')
dag = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dag)


def fixture(case_id):
    if case_id == 'compare_all_applicable_tools':
        axes = {'method': ['method_a', 'method_b', 'method_c']}
        tools = [dict(workflow_name=m, nextflow_path=f'fixture/{m}.nf') for m in axes['method']]
        request = 'Compare all applicable methods using the supplied synthetic dataset.'
    elif case_id == 'two_inhibitors_three_targets':
        axes = {'inhibitor': ['inhibitor_a', 'inhibitor_b'], 'target': ['target_a', 'target_b', 'target_c']}
        tools = [dict(workflow_name='pair_evaluation', nextflow_path='fixture/pair_evaluation.nf')]
        request = 'Compare the two inhibitors against all three targets using the supplied synthetic evidence.'
    elif case_id == 'peptide_shortlist_from_prior_run':
        axes = {'candidate': [f'candidate_{i}' for i in range(1, 7)], 'method': ['property_a', 'property_b']}
        tools = [dict(workflow_name=m, nextflow_path=f'fixture/{m}.nf') for m in axes['method']]
        request = 'Recover the prior synthetic designs, evaluate all available property methods and recommend five.'
    else:
        raise ValueError('Unknown fixture case')
    return {'case_id': case_id, 'synthetic': True, 'request': request, 'coverage_axes': axes,
            'workflows': tools, 'source_ref': f'fixture:{case_id}',
            'scope_note': 'Contract fixture only; names and IDs are not scientific tools or predictions.'}


def example_plan(case_id):
    data = fixture(case_id)
    axes = data['coverage_axes']
    steps = []
    for values in product(*axes.values()):
        dims = dict(zip(axes, values))
        workflow = next((w for w in data['workflows'] if w['workflow_name'] == dims.get('method')),
                        data['workflows'][0])
        steps.append({**workflow, 'step_key': ':'.join(values), 'depends_on': [],
                      'dimensions': dims, 'params': {}})
    return {'steps': steps, 'connections': [], 'max_parallel': 2}


def register_fixture_tools(registry, case_id, include_results=False, guided_schema=False):
    """Bind one server-selected case. The model cannot switch case or select an owner."""
    data = fixture(case_id)
    allowed = {(w['workflow_name'], w['nextflow_path']) for w in data['workflows']}
    validation = {'passed': False}

    def handle(operation, args):
        try:
            if not isinstance(args, dict):
                raise ValueError('Arguments must be an object')
            if operation == 'read_context':
                if args:
                    raise ValueError('read_context takes no arguments')
                result = copy.deepcopy(data)
            elif operation == 'list_workflows':
                if args:
                    raise ValueError('list_workflows takes no arguments')
                result = {'workflows': copy.deepcopy(data['workflows']), 'next_page': None, 'exhaustive_fixture': True}
            elif operation == 'read_fixture_results':
                if args or not validation['passed']:
                    raise ValueError('Validate the complete plan before reading fixture results; no arguments accepted')
                rows = []
                for i, step in enumerate(example_plan(case_id)['steps']):
                    rows.append({'case_id': step['step_key'], **step['dimensions'],
                                 'fixture_score': i + 1, 'artifact_ref': 'fixture:result:' + step['step_key']})
                result = {'execution_status': 'fixture_replay_not_execution', 'rows': rows,
                          'score_definition': 'Synthetic dimensionless fixture score; lower is preferred. No biological meaning.',
                          'selection_policy': SELECTION_POLICIES[case_id],
                          'recommended_candidate_ids': ['candidate_1', 'candidate_2', 'candidate_3', 'candidate_4', 'candidate_5']
                          if case_id == 'peptide_shortlist_from_prior_run' else []}
            else:
                validation['passed'] = False
                if set(args) != {'steps', 'connections', 'max_parallel'}:
                    raise ValueError('Expected steps, connections and max_parallel only')
                steps = args['steps']
                if not isinstance(steps, list) or any(not isinstance(s, dict) for s in steps):
                    raise ValueError('steps must be an array of objects')
                keys = [s.get('step_key') for s in steps]
                if any(not isinstance(k, str) or not k for k in keys) or len(set(keys)) != len(keys):
                    raise ValueError('Expected unique stable step keys')
                if any((s.get('workflow_name'), s.get('nextflow_path')) not in allowed for s in steps):
                    raise ValueError('Workflow is outside the bound fixture catalog')
                dag.validate_plan(steps, args['connections'], args['max_parallel'])
                # Expected coverage comes from host data, never a model-supplied denominator.
                dag.validate_coverage(steps, data['coverage_axes'])
                validation['passed'] = True
                result = {'valid': True, 'step_count': len(steps), 'execution_authorized': False,
                          'validation_scope': 'Structural graph and frozen fixture coverage only'}
            return json.dumps({'ok': True, 'case_id': case_id, 'synthetic': True, 'result': result})
        except (ValueError, TypeError, KeyError, AttributeError) as exc:
            return json.dumps({'ok': False, 'case_id': case_id, 'error': str(exc)})

    operations = ['read_context', 'list_workflows', 'validate_plan']
    if include_results:
        operations.append('read_fixture_results')
    for operation in operations:
        parameters = {'type': 'object', 'properties': {}, 'additionalProperties': False}
        if operation == 'validate_plan':
            parameters.update(properties={'steps': {'type': 'array', 'items': {'type': 'object'}},
                                          'connections': {'type': 'array', 'items': {'type': 'object'}},
                                          'max_parallel': {'type': 'integer', 'minimum': 1, 'maximum': 16}},
                              required=['steps', 'connections', 'max_parallel'])
            if guided_schema:
                parameters['properties']['steps']['items'] = {
                    'type': 'object',
                    'required': ['step_key', 'workflow_name', 'nextflow_path', 'dimensions', 'depends_on', 'params'],
                    'additionalProperties': False,
                    'properties': {
                        'step_key': {'type': 'string', 'description': 'Unique stable case key.'},
                        'workflow_name': {'type': 'string', 'enum': [w['workflow_name'] for w in data['workflows']]},
                        'nextflow_path': {'type': 'string', 'enum': [w['nextflow_path'] for w in data['workflows']]},
                        'dimensions': {'type': 'object', 'description': 'One named value per axis, e.g. {"method":"method_a"}; never an array.',
                                       'required': list(data['coverage_axes']), 'additionalProperties': False,
                                       'properties': {k: {'type': 'string', 'enum': v} for k, v in data['coverage_axes'].items()}},
                        'depends_on': {'type': 'array', 'items': {'type': 'integer'}, 'description': '[] for independent fixture cases.'},
                        'params': {'type': 'object', 'properties': {}, 'additionalProperties': False},
                    },
                }
        name = 'biomate_' + operation
        descriptions = {
            'read_context': 'First recover the host-bound request, source and exact coverage axes.',
            'list_workflows': 'List the complete fixture workflow catalog before constructing the plan.',
            'validate_plan': 'Validate every requested case. Expand coverage_axes into the full Cartesian product. Fix errors before continuing.',
            'read_fixture_results': 'Only call after validate_plan returns ok=true. Returns synthetic rows and the selection policy for the final report.',
        }
        registry.register(name=name, toolset='biomate_fixture',
                          schema={'name': name, 'description': descriptions[operation] if guided_schema else f'{operation} for a read-only synthetic BioMate evaluation case.',
                                  'parameters': parameters},
                          handler=lambda args, op=operation: handle(op, args))
