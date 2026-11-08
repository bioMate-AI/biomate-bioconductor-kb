"""Resume reporting from a completed fixture tool trace; preserve the original run.

Separate report phase: tools disabled, bounded output, same frozen observations.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import urllib.request

from run_openrouter_fixture_eval import SYSTEM
from fixture_adapter import SELECTION_POLICIES


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('trace', type=Path)
    p.add_argument('--timeout', type=int, default=60)
    p.add_argument('--output-tag', default='report_phase')
    p.add_argument('--scoped-context', action='store_true')
    args = p.parse_args()
    if not 1 <= args.timeout <= 120 or not args.output_tag.replace('_', '').isalnum():
        p.error('timeout must be 1..120 and output tag must be alphanumeric/underscore')
    record = json.loads(args.trace.read_text())
    if not record.get('mechanical_checks', {}).get('read_fixture_results'):
        raise ValueError('Cannot report without validated fixture results')
    messages = [{'role': 'system', 'content': SYSTEM},
                {'role': 'user', 'content': 'Complete the host-bound task: ' + record['case_id'] + '. Retrieve its context first.'}]
    for turn in record['turns']:
        messages.append(turn['assistant'])
        for result in turn['tool_results']:
            messages.append({'role': 'tool', 'tool_call_id': result['tool_call_id'], 'content': result['result']})
    messages.append({'role': 'user', 'content': 'Now write only the final report for ' + record['case_id'] +
                     ' from these supplied results. Keep it within 450 words, with the required tables and recommendation. '
                     'Clearly label synthetic fixture data. Do not discuss requirements of other tasks. Plan validation is not execution.'})
    if args.scoped_context:
        evidence = {}
        for turn in record['turns']:
            for observation in turn['tool_results']:
                value = json.loads(observation['result'])
                if value.get('ok') and observation['name'] in ('biomate_read_context', 'biomate_list_workflows', 'biomate_read_fixture_results'):
                    evidence[observation['name']] = value['result']
        # Correct only the task policy; retain every original row, score and source reference.
        rows = evidence['biomate_read_fixture_results']
        rows['selection_policy'] = SELECTION_POLICIES[record['case_id']]
        messages = [{'role': 'system', 'content':
            'You are BioMate writing a report from synthetic fixture evidence. No real scientific execution occurred. '
            'Follow only this task selection policy. Within 450 words include a title, scope, tools/coverage, '
            'complete comparison table, recommendation with reasons, artifact references and limitations. '
            'Preserve all scores and identities. Do not invent measurements or biological interpretations.'},
            {'role': 'user', 'content': json.dumps(evidence)}]
    provider = record.get('provider_requested') or 'DeepInfra'
    body = {'model': record['model'], 'messages': messages, 'temperature': 0, 'max_tokens': 1800,
            'reasoning': {'enabled': False}, 'provider': {'order': [provider], 'allow_fallbacks': False}}
    # No tools are offered in the final report phase.
    req = urllib.request.Request('https://openrouter.ai/api/v1/chat/completions', data=json.dumps(body).encode(),
        headers={'Authorization': 'Bearer ' + os.environ['OPENROUTER_API_KEY'], 'Content-Type': 'application/json'})
    def deadline(_s, _f):
        raise TimeoutError('Report phase exceeded deadline')
    signal.signal(signal.SIGALRM, deadline); signal.alarm(args.timeout)
    result = {'source_trace': args.trace.name, 'phase': 'separate_bounded_report_no_tools', 'success': False,
              'timeout': args.timeout, 'scoped_context': args.scoped_context, 'model': record['model'],
              'final_instruction': messages[-1]['content'], 'system_instruction': messages[0]['content']}
    try:
        with urllib.request.urlopen(req, timeout=args.timeout) as response:
            completion = json.load(response)
        choice = completion['choices'][0]
        result.update(finish_reason=choice.get('finish_reason'), usage=completion.get('usage'),
                      report=choice['message'].get('content'))
        result['success'] = choice.get('finish_reason') == 'stop' and bool(result['report']) and not choice['message'].get('tool_calls')
    except Exception as exc:
        result['error'] = type(exc).__name__
    finally:
        signal.alarm(0)
    out = args.trace.with_name(args.trace.stem + '_' + args.output_tag + '.json')
    out.write_text(json.dumps(result, indent=2) + '\n')
    if result['success']:
        out.with_suffix('.md').write_text(result['report'] + '\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ('report', 'usage', 'final_instruction', 'system_instruction')}), flush=True)


if __name__ == '__main__':
    main()
