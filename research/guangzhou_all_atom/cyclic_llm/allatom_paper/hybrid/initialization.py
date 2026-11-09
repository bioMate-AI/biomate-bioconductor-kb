"""Verified pretrained/adaptation hand-off; hashing only, no implicit downloads.

Manifests must be outside checkpoint directories and supplied with their SHA256.
The supported checkpoint layout is one flat directory per base/adapter, with
safetensors weights. All regular files are bound, not merely the weight file.
Validation establishes identity and compatibility, not scientific eligibility.
"""
import hashlib
import json
from pathlib import Path
import re


def sha256_file(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def _unique_object(pairs):
    out = {}
    for key, value in pairs:
        if key in out:
            raise ValueError('duplicate JSON key: ' + key)
        out[key] = value
    return out


def _read_json(path):
    return json.loads(Path(path).read_text(), object_pairs_hook=_unique_object)


def _inventory(directory, required):
    root = Path(directory)
    if root.is_symlink() or not root.is_dir():
        raise ValueError('initialization requires a real checkpoint directory')
    files = {}
    for item in sorted(root.iterdir()):
        if item.is_symlink() or not item.is_file():
            raise ValueError('checkpoint must be flat regular files: ' + str(item))
        files[item.name] = sha256_file(item)
    if not required <= files.keys():
        raise ValueError('checkpoint missing required files: ' + ', '.join(sorted(required - files.keys())))
    return files


def _check_inventory(actual, expected, label):
    if not isinstance(expected, dict) or any(
        not isinstance(k, str) or Path(k).name != k or k in ('.', '..')
        or not isinstance(v, str) or re.fullmatch(r'[0-9a-f]{64}', v) is None
        for k, v in expected.items()
    ):
        raise ValueError('invalid ' + label + ' manifest file map')
    if actual != expected:
        raise ValueError(label + ' checkpoint files differ from pinned manifest')


def prepare_initialization(model_dir, *, adaptation_dir=None, manifest_path=None,
                           manifest_sha256=None):
    """Return a path-independent identity, before loading any tensors.

    Bare pretrained initialization remains available without a manifest; its
    observed identity is still saved in every resume checkpoint. Adaptation is
    accepted only with an externally pinned manifest covering both directories.
    Optional base-only manifests use adapter_files=null.
    """
    if bool(manifest_path) != bool(manifest_sha256):
        raise ValueError('initialization manifest and SHA256 must be supplied together')
    if adaptation_dir is not None and manifest_path is None:
        raise ValueError('adaptation requires a pinned initialization manifest')
    base_files = _inventory(model_dir, {'config.json', 'tokenizer.json',
                                       'tokenizer_config.json', 'model.safetensors'})
    if 'adapter_config.json' in base_files:
        raise ValueError('base directory must not contain an adapter config that redirects model loading')
    adapter_files = None
    if adaptation_dir is not None:
        adapter_files = _inventory(adaptation_dir, {'adapter_config.json', 'adapter_model.safetensors'})
        cfg = _read_json(Path(adaptation_dir) / 'adapter_config.json')
        if (not isinstance(cfg, dict) or cfg.get('peft_type') != 'LORA' or cfg.get('task_type') != 'CAUSAL_LM'
                or cfg.get('bias', 'none') != 'none' or cfg.get('modules_to_save')):
            raise ValueError('adaptation must be causal-LM LoRA without trained biases or saved modules')
        if not cfg.get('target_modules'):
            raise ValueError('adaptation target modules must be explicit')
    if manifest_path is not None:
        if not isinstance(manifest_sha256, str) or re.fullmatch(r'[0-9a-f]{64}', manifest_sha256) is None:
            raise ValueError('invalid initialization manifest SHA256')
        if sha256_file(manifest_path) != manifest_sha256:
            raise ValueError('initialization manifest SHA256 mismatch')
        manifest = _read_json(manifest_path)
        if (not isinstance(manifest, dict)
                or set(manifest) != {'schema', 'base_files', 'adapter_files'}
                or manifest['schema'] != 'hybrid_initialization_v1'):
            raise ValueError('unsupported initialization manifest schema')
        _check_inventory(base_files, manifest['base_files'], 'base')
        if adapter_files is None:
            if manifest['adapter_files'] is not None:
                raise ValueError('manifest requires an adaptation checkpoint')
        else:
            _check_inventory(adapter_files, manifest['adapter_files'], 'adaptation')
    return dict(schema='hybrid_initialization_v1', base_files=base_files,
                adapter_files=adapter_files, manifest_sha256=manifest_sha256,
                reference='frozen_adapted_base' if adapter_files is not None else 'frozen_initial_base',
                adaptation_handoff='peft_safe_merge' if adapter_files is not None else 'none')


def merge_adaptation(base, adaptation_dir):
    """Merge validated local adaptation into the frozen DPO reference base.

    Caller must run prepare_initialization first. Fresh optimizer/DPO adapters
    are constructed afterwards; preparatory optimizer state is never restored.
    """
    from peft import PeftModel, get_peft_model_state_dict
    from safetensors.torch import load_file
    import torch
    saved = load_file(str(Path(adaptation_dir) / 'adapter_model.safetensors'), device='cpu')
    if not saved or not all(bool(torch.isfinite(t).all()) for t in saved.values()):
        raise ValueError('adaptation contains empty or nonfinite tensor state')
    adapted = PeftModel.from_pretrained(base, str(adaptation_dir),
                                       is_trainable=False, local_files_only=True)
    # PEFT may warn and leave fresh values for absent keys. Such a partial load
    # must never become a supposedly verified pretrained initialization.
    loaded = get_peft_model_state_dict(adapted)
    if saved.keys() != loaded.keys():
        raise ValueError('adaptation tensor keys do not exactly cover the loaded adapter')
    for name, value in saved.items():
        actual = loaded[name]
        if value.shape != actual.shape or not torch.equal(value.to(device=actual.device, dtype=actual.dtype), actual):
            raise ValueError('adaptation tensor was not restored exactly: ' + name)
    merged = adapted.merge_and_unload(safe_merge=True)
    merged.requires_grad_(False)
    return merged


def assert_initialization_matches(checkpoint_identity, expected):
    if checkpoint_identity is None:
        raise ValueError('legacy checkpoint lacks initialization identity; explicit migration required')
    if checkpoint_identity != expected:
        raise ValueError('checkpoint initialization/reference differs')
