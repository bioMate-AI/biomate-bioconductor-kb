"""Apply fail-fast update accounting to the pinned UniMoMo trainer before GPU use."""
import argparse
import ast
from pathlib import Path

MARKER = '# BIOMATE_STRICT_UPDATES_V1'


def patch_source(source):
    if MARKER in source:
        return source
    replacements = [
        ("            if self.is_oom_return(loss):", "            self.optimizer.zero_grad()", '''            if self.is_oom_return(loss):
                raise RuntimeError('Forward OOM: no valid update; reduce batch size')
            if not torch.isfinite(loss):
                raise RuntimeError('Nonfinite training loss')
'''),
        ("            if not backward_ok:", "            if self.config.grad_clip", '''            if not backward_ok:
                raise RuntimeError('Backward OOM: no valid update; reduce batch size')
            grads = [p.grad for p in self.model.parameters() if p.requires_grad and p.grad is not None]
            if not grads or any(not torch.isfinite(g).all() for g in grads):
                raise RuntimeError('Missing or nonfinite gradients')
            grad_norm = sum(g.float().square().sum() for g in grads).sqrt().item()
            if grad_norm == 0:
                raise RuntimeError('Zero gradient norm')
'''),
    ]
    for start, end, replacement in replacements:
        if source.count(start) != 1:
            raise ValueError(f'Expected one pinned trainer anchor: {start.strip()}')
        i = source.index(start)
        j = source.index(end, i)
        source = source[:i] + replacement + source[j:]
    for old, new in [
        ('        self._train_epoch_begin(device)', '''        if len(self.train_loader) == 0:
            raise RuntimeError('Empty training loader')
        self._train_epoch_begin(device)'''),
        ('            self.optimizer.step()', '''            self.optimizer.step()
            print_log(f'UPDATE_EVIDENCE step={self.global_step} loss={loss.item()} grad_norm={grad_norm}')'''),
        ('                metric_arr.append(metric.cpu().item())', '''                if self.is_oom_return(metric) or not torch.isfinite(metric):
                    raise RuntimeError('Invalid validation result')
                metric_arr.append(metric.cpu().item())'''),
        ('        valid_metric = self._aggregate_val_metric(metric_arr)', '''        if not metric_arr:
            raise RuntimeError('Empty validation loader')
        valid_metric = self._aggregate_val_metric(metric_arr)
        if not np.isfinite(valid_metric):
            raise RuntimeError('Nonfinite validation metric')'''),
    ]:
        if source.count(old) != 1:
            raise ValueError(f'Expected one pinned trainer anchor: {old.strip()}')
        source = source.replace(old, new, 1)
    source = MARKER + '\n' + source
    ast.parse(source)
    return source


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    path = args.root / 'trainer/abs_trainer.py'
    path.write_text(patch_source(path.read_text()))
