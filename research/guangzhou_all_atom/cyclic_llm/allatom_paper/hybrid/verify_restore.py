"""EC2-only, read-only real-model checkpoint restore diagnostic (not M1).

Requires externally pinned checkpoint and single-file base-model hashes. Does not
resume training, modify checkpoints, fetch weights, or certify scientific gates.
"""
import argparse
import io
import json
import math
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


def assert_finite(value, path='state'):
    import torch
    if torch.is_tensor(value):
        if not bool(torch.isfinite(value).all()):
            raise ValueError('nonfinite checkpoint tensor: ' + path)
    elif isinstance(value, dict):
        for key, item in value.items():
            assert_finite(item, path + '.' + str(key))
    elif isinstance(value, (tuple, list)):
        for i, item in enumerate(value):
            assert_finite(item, path + '.' + str(i))
    elif isinstance(value, float) and not math.isfinite(value):
        raise ValueError('nonfinite checkpoint scalar: ' + path)


def assert_equal(expected, actual, path='state'):
    import torch
    if torch.is_tensor(expected):
        if not torch.is_tensor(actual) or expected.dtype != actual.dtype or not torch.equal(expected.cpu(), actual.cpu()):
            raise ValueError('restore tensor mismatch: ' + path)
    elif isinstance(expected, dict):
        if not isinstance(actual, dict) or expected.keys() != actual.keys():
            raise ValueError('restore keys mismatch: ' + path)
        for key in expected:
            assert_equal(expected[key], actual[key], path + '.' + str(key))
    elif isinstance(expected, (tuple, list)):
        if type(expected) is not type(actual) or len(expected) != len(actual):
            raise ValueError('restore sequence mismatch: ' + path)
        for i, (left, right) in enumerate(zip(expected, actual)):
            assert_equal(left, right, path + '.' + str(i))
    elif type(expected) is not type(actual) or expected != actual:
        raise ValueError('restore value mismatch: ' + path)


def validate_state(state):
    """Require evidence of a completed finite optimizer update, not empty state."""
    if not isinstance(state, dict):
        raise ValueError('checkpoint must be a state dictionary')
    required = {'adapter', 'optimizer', 'steps', 'extra_state', 'rng_cpu',
                'rng_cuda', 'knowledge_config', 'sampling_config'}
    if not required <= state.keys():
        raise ValueError('checkpoint missing required state')
    if type(state['steps']) is not int or state['steps'] < 1:
        raise ValueError('checkpoint has no completed optimizer update')
    if not state['adapter'] or not state['optimizer'].get('state'):
        raise ValueError('empty adapter or optimizer state')
    assert_finite(state)
    import torch
    steps = []
    for item in state['optimizer']['state'].values():
        step = item.get('step')
        if torch.is_tensor(step):
            if step.numel() != 1:
                raise ValueError('optimizer step must be scalar')
            step = step.item()
        if isinstance(step, bool) or not isinstance(step, (int, float)) or step != state['steps']:
            raise ValueError('optimizer step disagrees with completed update count')
        steps.append(step)
    return steps


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--model-dir', required=True)
    p.add_argument('--model-sha256', required=True)
    p.add_argument('--checkpoint', required=True)
    p.add_argument('--checkpoint-sha256', required=True)
    p.add_argument('--adaptation-dir')
    p.add_argument('--initialization-manifest')
    p.add_argument('--initialization-manifest-sha256')
    p.add_argument('--out', required=True)
    a = p.parse_args()
    import torch
    from hybrid.run_stage1 import file_sha
    from hybrid.model import ChemFMGenerator
    if not torch.cuda.is_available():
        raise RuntimeError('real-model restore verification requires an available CUDA GPU on EC2')
    for path, expected in ((Path(a.model_dir) / 'model.safetensors', a.model_sha256),
                           (Path(a.checkpoint), a.checkpoint_sha256)):
        if file_sha(path) != expected:
            raise ValueError('pinned SHA256 mismatch: ' + str(path))
    output = Path(a.out)
    if output.exists():
        raise ValueError('refusing to overwrite prior validation evidence')
    state = torch.load(a.checkpoint, map_location='cpu', weights_only=True)
    steps = validate_state(state)
    if state['knowledge_config'] is not None:
        raise ValueError('this restore diagnostic supports L0 knowledge-off only; use exact catalogue configuration for other arms')
    cfg = state['sampling_config']
    # Constructor requires a parent but this diagnostic never samples or scores it.
    g = ChemFMGenerator(a.model_dir, ['C'], device='cuda',
        adaptation_dir=a.adaptation_dir,
        initialization_manifest=a.initialization_manifest,
        initialization_manifest_sha256=a.initialization_manifest_sha256, **cfg)
    g.load_lora(a.checkpoint)
    restored = torch.load(io.BytesIO(g.lora_state()), map_location='cpu', weights_only=True)
    validate_state(restored)
    assert_equal(state, restored)
    report = dict(status='REAL_MODEL_STATE_RESTORE_MATCH', real_model=True,
                  checkpoint_sha256=a.checkpoint_sha256, model_sha256=a.model_sha256,
                  optimizer_steps=g.steps, optimizer_state_entries=len(steps),
                  initialization_identity=g.initialization_identity,
                  torch_version=str(torch.__version__), cuda_version=torch.version.cuda,
                  gpu=torch.cuda.get_device_name(),
                  limitations=['No resumed update or sampling executed',
                               'No proof of uninterrupted/resumed trajectory equivalence',
                               'No run-identity or cumulative-deadline certification',
                               'Not an M1 pass certificate or study authorization'])
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('x') as stream:
        json.dump(report, stream, indent=2, allow_nan=False)
    print(json.dumps(report))


if __name__ == '__main__':
    main()
