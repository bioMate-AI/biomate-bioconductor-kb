"""Fail fast on invalid updates and log real gradient/update evidence for pinned code."""
import argparse
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, required=True)
args = parser.parse_args()
p = args.root / 'trainer/abs_trainer.py'
s = p.read_text()
start = s.index('            if self.is_oom_return(loss):')
end = s.index('            self.optimizer.zero_grad()', start)
s = s[:start] + '''            if self.is_oom_return(loss):
                raise RuntimeError('Forward OOM: reduce declared batch budget')
            if not torch.isfinite(loss):
                raise RuntimeError('Nonfinite training loss')
''' + s[end:]
start = s.index('            if not backward_ok:')
end = s.index('            if self.config.grad_clip', start)
s = s[:start] + '''            if not backward_ok:
                raise RuntimeError('Backward OOM: no optimizer update performed')
            grads = [p.grad for p in self.model.parameters() if p.grad is not None]
            if not grads or any(not torch.isfinite(g).all() for g in grads):
                raise RuntimeError('Missing or nonfinite gradients')
            if self.global_step % 100 == 0:
                norm = sum(g.float().square().sum() for g in grads).sqrt().item()
                if norm == 0:
                    raise RuntimeError('Zero gradient norm')
                print_log(f'UPDATE_EVIDENCE step={self.global_step} loss={loss.item()} grad_norm={norm}')
''' + s[end:]
s = s.replace('        valid_metric = self._aggregate_val_metric(metric_arr)',
'''        valid_metric = self._aggregate_val_metric(metric_arr)
        if not np.isfinite(valid_metric):
            raise RuntimeError('Nonfinite validation metric')''')
p.write_text(s)
