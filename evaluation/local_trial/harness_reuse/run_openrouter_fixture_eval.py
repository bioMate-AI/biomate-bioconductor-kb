"""Bounded real-model evaluation using Hermes registry and synthetic BioMate tools.

This evaluation driver is not the full Hermes AIAgent loop or a production runtime.
Only synthetic fixtures are transmitted. API keys are read from the environment.
"""
import argparse
import hashlib
import json
import os
import signal
from pathlib import Path
import sys
import time
import urllib.error
import urllib.request
import urllib.parse

from fixture_adapter import register_fixture_tools

SYSTEM = '''You are BioMate in an explicitly SYNTHETIC evaluation. Use tools to recover
the task context and full available workflow catalog, construct a complete plan,
validate it, then read the supplied fixture results and write the final report.
Do not claim real scientific execution. Every report must clearly label synthetic
fixture results. Preserve every requested case. Use one execution step per case
for this fixture, with step_key, workflow_name, nextflow_path, dimensions,
depends_on (one-based indices, [] for independent work), and params {}.
The validator requires steps, connections [] and max_parallel (use 2).
Coverage axes come from context; enumerate their full Cartesian product.
Use the documented fixture scoring/selection policy. Repair validation failures
using the tool feedback. Final response: title; input/scope summary; tools and
coverage table; complete results comparison table; recommendation with reasons;
artifact references and limitations. For the peptide task, show five candidates
and explain their selection. Never invent tool results, chemical structures or
biological significance for fixture scores. Do not ask for information already
supplied by the fixture tools.'''


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--hermes-source', type=Path, required=True)
    p.add_argument('--output-dir', type=Path, required=True)
    p.add_argument('--local-base-url', help='Loopback OpenAI-compatible endpoint, e.g. http://127.0.0.1:18000/v1 (SSH tunnel)')
    p.add_argument('--local-reasoning-effort', default='none', help='Local server reasoning setting, recorded in results')
    p.add_argument('--model', default='qwen/qwen3.5-9b')
    p.add_argument('--max-turns', type=int, default=8)
    p.add_argument('--provider', help='Optional explicit OpenRouter provider; disables provider fallback')
    p.add_argument('--schema-mode', choices=['minimal', 'guided'], default='minimal')
    p.add_argument('--case', choices=['compare_all_applicable_tools', 'two_inhibitors_three_targets', 'peptide_shortlist_from_prior_run'])
    p.add_argument('--request-timeout', type=int, default=60)
    p.add_argument('--separate-report-phase', action='store_true')
    args = p.parse_args()
    if not 1 <= args.max_turns <= 12:
        p.error('max-turns must be 1..12')
    if not 1 <= args.request_timeout <= 120:
        p.error('request-timeout must be 1..120 seconds')
    manifest = json.loads(Path(__file__).with_name('upstream-source-manifest.json').read_text())
    upstream = next(r for r in manifest['repositories'] if r['repository'] == 'NousResearch/hermes-agent')
    for name in ('tools/registry.py', 'tools/__init__.py', 'hermes_constants.py'):
        f = next(f for f in upstream['files'] if f['path'] == name)
        if hashlib.sha256((args.hermes_source / name).read_bytes()).hexdigest() != f['sha256']:
            raise ValueError('Pinned source hash mismatch: ' + name)
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(args.hermes_source.resolve()))
    from tools.registry import ToolRegistry
    endpoint = 'https://openrouter.ai/api/v1/chat/completions'
    key = os.environ.get('OPENROUTER_API_KEY')
    if args.local_base_url:
        parsed = urllib.parse.urlsplit(args.local_base_url)
        if parsed.scheme != 'http' or parsed.hostname not in ('127.0.0.1', 'localhost', '::1') or parsed.username or parsed.password or parsed.query or parsed.fragment:
            p.error('local-base-url must be an HTTP loopback endpoint without credentials, query or fragment')
        if args.provider:
            p.error('provider selection is not supported in local mode')
        endpoint = args.local_base_url.rstrip('/') + '/chat/completions'
        key = os.environ.get('BIOMATE_LOCAL_EVAL_API_KEY')
    elif not key:
        raise ValueError('OPENROUTER_API_KEY is required for hosted evaluation')
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            raise urllib.error.HTTPError(req.full_url, code, 'Redirects disabled', headers, fp)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect()) if args.local_base_url else urllib.request.build_opener()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    summary = []
    def request_deadline(_signal, _frame):
        raise TimeoutError('Model request exceeded wall-time budget')
    signal.signal(signal.SIGALRM, request_deadline)
    for case in ('compare_all_applicable_tools', 'two_inhibitors_three_targets', 'peptide_shortlist_from_prior_run'):
        if args.case and case != args.case:
            continue
        registry = ToolRegistry()
        register_fixture_tools(registry, case, include_results=True, guided_schema=args.schema_mode == 'guided')
        tools = [{'type': 'function', 'function': registry.get_schema(n)} for n in registry.get_all_tool_names()]
        messages = [{'role': 'system', 'content': SYSTEM},
                    {'role': 'user', 'content': 'Complete the host-bound task: ' + case + '. Retrieve its context first.'}]
        record = {'case_id': case, 'model': args.model, 'endpoint_mode': 'local' if args.local_base_url else 'openrouter', 'local_reasoning_effort': args.local_reasoning_effort if args.local_base_url else None, 'hermes_revision': upstream['revision'],
                  'schema_mode': args.schema_mode, 'provider_requested': args.provider,
                  'request_timeout': args.request_timeout, 'separate_report_phase': args.separate_report_phase,
                  'fixture_adapter_sha256': hashlib.sha256(Path(__file__).with_name('fixture_adapter.py').read_bytes()).hexdigest(),
                  'scope': 'Real model + actual Hermes registry + synthetic fixtures; evaluation driver, not full AIAgent.',
                  'turns': [], 'final_report': None}
        start = time.monotonic()
        (args.output_dir / (case + '.json')).write_text(json.dumps(record, indent=2) + '\n')
        for turn in range(args.max_turns):
            if time.monotonic() - start > 300:
                record['error'] = 'case_time_budget_exceeded'; break
            body = {'model': args.model, 'messages': messages, 'tools': tools, 'tool_choice': 'auto',
                    'temperature': 0, 'max_tokens': 5000, 'reasoning': {'enabled': False},
                    'provider': {'require_parameters': True}}
            if args.local_base_url:
                body.pop('provider'); body.pop('reasoning')
                body['reasoning_effort'] = args.local_reasoning_effort
            if args.provider:
                body['provider'].update(order=[args.provider], allow_fallbacks=False)
            ready_to_report = any(x['name'] == 'biomate_read_fixture_results' and json.loads(x['result']).get('ok')
                                  for t in record['turns'] for x in t['tool_results'])
            if args.separate_report_phase and ready_to_report:
                body.pop('tools'); body.pop('tool_choice'); body['max_tokens'] = 1800
                body['messages'] = messages + [{'role': 'user', 'content':
                    f'Write only the report for {case}, within 450 words. Use the actual fixture results. '
                    'Do not discuss requirements of other cases. Validation is not execution; these are replayed synthetic results.'}]
            headers = {'Content-Type': 'application/json'}
            if key:
                headers['Authorization'] = 'Bearer ' + key
            req = urllib.request.Request(endpoint, data=json.dumps(body).encode(), headers=headers)
            try:
                signal.alarm(args.request_timeout)
                with opener.open(req, timeout=args.request_timeout) as response:
                    result = json.load(response)
                choice = result['choices'][0]; message = choice['message']
            except urllib.error.HTTPError as exc:
                record['error'] = 'Model endpoint HTTP ' + str(exc.code); break
            except Exception as exc:
                record['error'] = 'Provider response failure: ' + type(exc).__name__; break
            finally:
                signal.alarm(0)
            # Retain content and calls, but not hidden reasoning or provider metadata.
            assistant = {'role': 'assistant', 'content': message.get('content')}
            calls = message.get('tool_calls') or []
            if calls:
                assistant['tool_calls'] = calls
            messages.append(assistant)
            entry = {'turn': turn + 1, 'assistant': assistant, 'finish_reason': choice.get('finish_reason'),
                     'usage': result.get('usage', {}), 'tool_results': []}
            record['turns'].append(entry)
            if choice.get('finish_reason') not in ('stop', 'tool_calls'):
                record['error'] = 'incomplete_model_response'; break
            if not calls:
                record['final_report'] = message.get('content'); break
            for call in calls:
                try:
                    name = call['function']['name']; payload = json.loads(call['function']['arguments'])
                    observation = registry.dispatch(name, payload)
                except (ValueError, KeyError, TypeError):
                    observation = json.dumps({'ok': False, 'error': 'Malformed tool call'})
                entry['tool_results'].append({'tool_call_id': call['id'], 'name': call['function']['name'], 'result': observation})
                messages.append({'role': 'tool', 'tool_call_id': call['id'], 'content': observation})
            (args.output_dir / (case + '.json')).write_text(json.dumps(record, indent=2) + '\n')
        observations = [(x['name'], json.loads(x['result'])) for t in record['turns'] for x in t['tool_results']]
        if not record['final_report'] and not record.get('error'):
            record['error'] = 'turn_budget_exhausted'
        checks = {name: any(n == 'biomate_' + name and o.get('ok') for n, o in observations)
                  for name in ['read_context', 'list_workflows', 'validate_plan', 'read_fixture_results']}
        checks['final_report_present'] = bool(record['final_report'])
        record['mechanical_checks'] = checks
        record['report_review'] = 'pending_human_or_separate_evidence_review'
        record['elapsed_seconds'] = round(time.monotonic() - start, 2)
        (args.output_dir / (case + '.json')).write_text(json.dumps(record, indent=2) + '\n')
        if record['final_report']:
            (args.output_dir / (case + '.md')).write_text(record['final_report'] + '\n')
        summary.append({'case_id': case, 'mechanical_checks': checks, 'error': record.get('error'),
                        'turns': len(record['turns']), 'elapsed_seconds': record['elapsed_seconds']})
        (args.output_dir / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(json.dumps(summary[-1]), flush=True)
    return int(any(not all(s['mechanical_checks'].values()) for s in summary))


if __name__ == '__main__':
    sys.exit(main())
