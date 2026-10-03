"""Exercise patched upstream epoch code with real torch autograd and optimizer.

Fixture: kxz18/UniMoMo f58f117d43975d45dc2521b34ae3066a095582f0,
trainer/abs_trainer.py. AST extraction avoids unrelated GPU/plugin imports.
"""
import ast
from collections import namedtuple
from pathlib import Path
import sys
from types import SimpleNamespace

import pytest
import torch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from patch_unimomo_training import patch_source

SOURCE = (Path(__file__).parent / 'fixtures/unimomo_abs_trainer.py.txt').read_text()
OOMReturn = namedtuple('OOMReturn', 'fake_loss')


class Loader(list):
    sampler = None


def make_trainer(mode='valid', backward_ok=True):
    tree = ast.parse(patch_source(SOURCE))
    cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'Trainer')
    method = next(n for n in cls.body if isinstance(n, ast.FunctionDef) and n.name == '_train_epoch')
    namespace = {'torch': torch, 'print_log': lambda msg: events.append(msg)}
    def backward(loss, model):
        loss.backward()
        return backward_ok
    namespace['safe_backward'] = backward
    exec(compile(ast.Module(body=[method], type_ignores=[]), '<patched upstream epoch>', 'exec'), namespace)
    events = []
    model = torch.nn.Linear(1, 1, bias=False)
    with torch.no_grad():
        model.weight.fill_(1)
    def step(batch, idx):
        loss = model(batch).square().sum()
        if mode == 'oom': return OOMReturn(loss * 0)
        if mode == 'nan': return loss * float('nan')
        if mode == 'inf': return loss * float('inf')
        if mode == 'zero': return loss * 0
        if mode == 'missing': return torch.tensor(1., requires_grad=True)
        return loss
    trainer = SimpleNamespace(
        train_loader=Loader([torch.ones(1, 1)]), local_rank=-1, epoch=0,
        _train_epoch_begin=lambda device: None, _train_epoch_end=lambda device: None,
        _is_main_proc=lambda: False, to_device=lambda batch, device: batch,
        train_step=step, global_step=0, is_oom_return=lambda loss: isinstance(loss, OOMReturn),
        optimizer=torch.optim.SGD(model.parameters(), lr=.1), model=model,
        config=SimpleNamespace(grad_clip=None), log=lambda *args: None, sched_freq=None,
    )
    return trainer, namespace['_train_epoch'], events


def test_success_changes_parameters_and_records_update():
    trainer, epoch, events = make_trainer()
    epoch(trainer, 'cpu')
    assert trainer.model.weight.item() == pytest.approx(.8)
    assert trainer.global_step == 1
    assert len(events) == 1 and 'UPDATE_EVIDENCE step=0' in events[0]


@pytest.mark.parametrize('mode,backward_ok,error', [
    ('oom', True, 'Forward OOM'), ('valid', False, 'Backward OOM'),
    ('nan', True, 'Nonfinite'), ('inf', True, 'Nonfinite'),
    ('zero', True, 'Zero gradient'), ('missing', True, 'Missing or nonfinite'),
])
def test_invalid_batch_never_updates(mode, backward_ok, error):
    trainer, epoch, events = make_trainer(mode, backward_ok)
    with pytest.raises(RuntimeError, match=error): epoch(trainer, 'cpu')
    assert trainer.model.weight.item() == 1
    assert trainer.global_step == 0
    assert events == []


def test_empty_training_rejected():
    trainer, epoch, _ = make_trainer()
    trainer.train_loader.clear()
    with pytest.raises(RuntimeError, match='Empty training'): epoch(trainer, 'cpu')


def test_patch_is_idempotent_and_rejects_source_drift():
    patched = patch_source(SOURCE)
    assert patch_source(patched) == patched
    with pytest.raises(ValueError): patch_source(SOURCE.replace('self.optimizer.step()', 'changed()'))


def test_single_complex_config_has_no_silent_budget_filter():
    import yaml
    config = yaml.safe_load((Path(__file__).parents[1] / 'unimomo_cyclic_ft.yaml').read_text())
    for split in ('train', 'valid'):
        assert config['dataset'][split]['class'] == 'PeptideDataset'
        assert config['dataloader'][split]['batch_size'] == 1
