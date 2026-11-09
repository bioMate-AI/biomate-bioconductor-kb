"""Remote-only synthetic hand-off checks; no downloaded or research models.

Run on the approved EC2 QA worker. These tests do not establish ChemFM quality,
corpus eligibility, low-precision equivalence or a completed method study.
"""
import copy
import json
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from hybrid.initialization import (assert_initialization_matches,
                                   merge_adaptation, prepare_initialization,
                                   sha256_file)


def fixtures(tmp_path):
    base = tmp_path / 'base'
    adapter = tmp_path / 'adapter'
    base.mkdir(); adapter.mkdir()
    for name in ('config.json', 'tokenizer.json', 'tokenizer_config.json'):
        (base / name).write_text('{}')
    (base / 'model.safetensors').write_bytes(b'synthetic base; never tensor-loaded')
    (adapter / 'adapter_config.json').write_text(json.dumps(dict(
        peft_type='LORA', task_type='CAUSAL_LM', bias='none',
        target_modules=['q_proj', 'k_proj', 'v_proj', 'o_proj'], r=2)))
    (adapter / 'adapter_model.safetensors').write_bytes(b'synthetic adapter; never tensor-loaded')
    manifest = tmp_path / 'initialization.json'
    manifest.write_text(json.dumps(dict(schema='hybrid_initialization_v1',
        base_files={p.name: sha256_file(p) for p in base.iterdir()},
        adapter_files={p.name: sha256_file(p) for p in adapter.iterdir()})))
    return base, adapter, manifest


def initialize(base, adapter, manifest):
    return prepare_initialization(base, adaptation_dir=adapter,
        manifest_path=manifest, manifest_sha256=sha256_file(manifest))


def test_bare_pretrained_path_is_preserved_and_resume_bound(tmp_path):
    base, _, _ = fixtures(tmp_path)
    identity = prepare_initialization(base)
    assert identity['reference'] == 'frozen_initial_base'
    assert identity['adapter_files'] is None
    assert_initialization_matches(copy.deepcopy(identity), identity)
    altered = copy.deepcopy(identity)
    altered['base_files']['tokenizer.json'] = '0' * 64
    with pytest.raises(ValueError, match='initialization/reference differs'):
        assert_initialization_matches(altered, identity)
    with pytest.raises(ValueError, match='legacy checkpoint'):
        assert_initialization_matches(None, identity)


def test_adapter_requires_externally_pinned_manifest(tmp_path):
    base, adapter, manifest = fixtures(tmp_path)
    with pytest.raises(ValueError, match='pinned initialization manifest'):
        prepare_initialization(base, adaptation_dir=adapter)
    with pytest.raises(ValueError, match='manifest SHA256 mismatch'):
        prepare_initialization(base, adaptation_dir=adapter,
            manifest_path=manifest, manifest_sha256='0' * 64)
    identity = initialize(base, adapter, manifest)
    assert identity['reference'] == 'frozen_adapted_base'
    assert identity['adaptation_handoff'] == 'peft_safe_merge'


@pytest.mark.parametrize('kind,name', [('base', 'tokenizer.json'),
    ('base', 'config.json'), ('base', 'model.safetensors'),
    ('adapter', 'adapter_model.safetensors')])
def test_tampered_checkpoint_files_fail_before_tensor_loading(tmp_path, kind, name):
    base, adapter, manifest = fixtures(tmp_path)
    root = base if kind == 'base' else adapter
    (root / name).write_bytes(b'changed')
    with pytest.raises(ValueError, match='files differ'):
        initialize(base, adapter, manifest)


def test_extra_files_and_unsafe_layout_fail_closed(tmp_path):
    base, adapter, manifest = fixtures(tmp_path)
    extra = base / 'generation_config.json'
    extra.write_text('{}')
    with pytest.raises(ValueError, match='files differ'):
        initialize(base, adapter, manifest)
    extra.unlink()
    (adapter / 'linked.json').symlink_to(base / 'config.json')
    with pytest.raises(ValueError, match='flat regular files'):
        initialize(base, adapter, manifest)


def test_base_cannot_redirect_loading_to_an_unbound_adapter(tmp_path):
    base, _, _ = fixtures(tmp_path)
    (base / 'adapter_config.json').write_text('{"base_model_name_or_path":"elsewhere"}')
    with pytest.raises(ValueError, match='redirects model loading'):
        prepare_initialization(base)


def test_duplicate_manifest_keys_are_rejected_even_if_hash_matches(tmp_path):
    base, adapter, manifest = fixtures(tmp_path)
    manifest.write_text('{"schema":"hybrid_initialization_v1","schema":"other"}')
    with pytest.raises(ValueError, match='duplicate JSON key'):
        initialize(base, adapter, manifest)


def test_non_lora_or_saved_head_adaptation_is_rejected(tmp_path):
    base, adapter, manifest = fixtures(tmp_path)
    config = adapter / 'adapter_config.json'
    row = json.loads(config.read_text())
    row['modules_to_save'] = ['lm_head']
    config.write_text(json.dumps(row))
    with pytest.raises(ValueError, match='without trained biases or saved modules'):
        initialize(base, adapter, manifest)


def test_changed_adaptation_cannot_resume_prior_initialization(tmp_path):
    base, adapter, manifest = fixtures(tmp_path)
    first = initialize(base, adapter, manifest)
    weight = adapter / 'adapter_model.safetensors'
    weight.write_bytes(b'another adaptation')
    doc = json.loads(manifest.read_text())
    doc['adapter_files'][weight.name] = sha256_file(weight)
    manifest.write_text(json.dumps(doc))
    second = initialize(base, adapter, manifest)
    with pytest.raises(ValueError, match='initialization/reference differs'):
        assert_initialization_matches(first, second)


def test_real_peft_merge_preserves_adapted_logits_and_reference(tmp_path):
    # Tiny randomly initialised fixture, not scientific training or a download.
    import torch
    from transformers import LlamaConfig, LlamaForCausalLM
    from peft import LoraConfig, get_peft_model
    torch.manual_seed(5)
    base = LlamaForCausalLM(LlamaConfig(vocab_size=16, hidden_size=16,
        intermediate_size=24, num_hidden_layers=1, num_attention_heads=2,
        num_key_value_heads=2, max_position_embeddings=16)).eval()
    original = copy.deepcopy(base)
    adapted = get_peft_model(base, LoraConfig(r=2, lora_alpha=4,
        target_modules=['q_proj', 'k_proj', 'v_proj', 'o_proj'],
        lora_dropout=0.0, bias='none', task_type='CAUSAL_LM')).eval()
    with torch.no_grad():
        for name, parameter in adapted.named_parameters():
            if 'lora_' in name:
                parameter.normal_(mean=0.0, std=0.2)
    tokens = torch.tensor([[1, 3, 5, 7]])
    with torch.no_grad():
        expected = adapted(tokens).logits.clone()
        original_logits = original(tokens).logits.clone()
    directory = tmp_path / 'real_adapter'
    adapted.save_pretrained(directory, safe_serialization=True)
    import shutil
    from safetensors.torch import load_file, save_file
    broken = tmp_path / 'incomplete_adapter'
    shutil.copytree(directory, broken)
    state = load_file(str(broken / 'adapter_model.safetensors'))
    state.pop(next(iter(state)))
    save_file(state, str(broken / 'adapter_model.safetensors'))
    with pytest.raises(ValueError, match='tensor keys'):
        merge_adaptation(copy.deepcopy(original), broken)
    merged = merge_adaptation(original, directory).eval()
    assert all(not p.requires_grad for p in merged.parameters())
    with torch.no_grad():
        assert torch.allclose(merged(tokens).logits, expected, atol=1e-6, rtol=1e-5)
        assert not torch.allclose(expected, original_logits, atol=1e-6, rtol=1e-5)
    policy = get_peft_model(merged, LoraConfig(r=2, lora_alpha=4,
        target_modules=['q_proj', 'v_proj'], lora_dropout=0.0,
        bias='none', task_type='CAUSAL_LM')).eval()
    with torch.no_grad():
        assert torch.allclose(policy(tokens).logits, expected, atol=1e-6, rtol=1e-5)
        with policy.disable_adapter():
            assert torch.allclose(policy(tokens).logits, expected, atol=1e-6, rtol=1e-5)
    assert all('lora_' in name for name, p in policy.named_parameters() if p.requires_grad)
