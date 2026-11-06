"""Exact local training-state checkpointing for trusted, same-runtime runs.

Caller must persist sampler state and resume at the recorded next batch. Worker
prefetch state is not captured: use deterministic indexed sampling or restartable
shards; CUDA kernels must be deterministic for bitwise trajectory guarantees.
"""
import hashlib
import json
import os
import random
import tempfile
from pathlib import Path
import numpy as np
import torch

VERSION = 1

def manifest_hash(value):
    """Canonical JSON hash; reject NaN and non-JSON opaque objects."""
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest()

def _validate_identity(identity):
    if set(identity) != {'source_manifest_hash', 'schema_hash', 'config_hash'}:
        raise ValueError('Identity requires source_manifest_hash, schema_hash, config_hash')
    for value in identity.values():
        if not isinstance(value, str) or len(value) != 64 or any(c not in '0123456789abcdef' for c in value):
            raise ValueError('Identity values must be lowercase SHA256 hashes')

def save_checkpoint(path, *, model, optimizer, identity, epoch, next_batch,
                    sampler_state, scheduler=None, scaler=None):
    _validate_identity(identity)
    if type(epoch) is not int or type(next_batch) is not int or min(epoch, next_batch) < 0:
        raise ValueError('Epoch and next_batch must be nonnegative integers')
    if sampler_state is None:
        raise ValueError('Explicit resumable sampler_state required')
    payload = {'version': VERSION, 'identity': dict(identity), 'epoch': epoch,
               'next_batch': next_batch, 'sampler_state': sampler_state,
               'model': model.state_dict(), 'optimizer': optimizer.state_dict(),
               'scheduler': scheduler.state_dict() if scheduler is not None else None,
               'scaler': scaler.state_dict() if scaler is not None else None,
               'rng': {'python': random.getstate(), 'numpy': np.random.get_state(),
                       'torch': torch.get_rng_state(),
                       'cuda': torch.cuda.get_rng_state_all() if torch.cuda.is_available() else []}}
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=path.name + '.', suffix='.tmp', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            torch.save(payload, stream); stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try: os.fsync(directory)
        finally: os.close(directory)
    finally:
        if os.path.exists(temporary): os.unlink(temporary)

def load_checkpoint(path, *, model, optimizer, identity, scheduler=None, scaler=None):
    """Load only locally trusted checkpoints; torch pickle is not a safe interchange format.

    Identity/component checks run before mutating any training state. A malformed
    state_dict can still fail during loading; discard training objects on failure.
    """
    _validate_identity(identity)
    payload = torch.load(path, map_location='cpu', weights_only=False)
    if payload.get('version') != VERSION: raise ValueError('Unsupported checkpoint version')
    if payload.get('identity') != identity: raise ValueError('Checkpoint source/schema/config identity mismatch')
    for name, component in [('scheduler', scheduler), ('scaler', scaler)]:
        if (payload[name] is None) != (component is None):
            raise ValueError(f'Checkpoint {name} presence mismatch')
    if len(payload['rng']['cuda']) != (torch.cuda.device_count() if torch.cuda.is_available() else 0):
        raise ValueError('CUDA device topology mismatch')
    model.load_state_dict(payload['model'], strict=True)
    optimizer.load_state_dict(payload['optimizer'])
    if scheduler is not None: scheduler.load_state_dict(payload['scheduler'])
    if scaler is not None: scaler.load_state_dict(payload['scaler'])
    random.setstate(payload['rng']['python']); np.random.set_state(payload['rng']['numpy'])
    torch.set_rng_state(payload['rng']['torch'])
    if payload['rng']['cuda']: torch.cuda.set_rng_state_all(payload['rng']['cuda'])
    return {k: payload[k] for k in ['epoch', 'next_batch', 'sampler_state']}
