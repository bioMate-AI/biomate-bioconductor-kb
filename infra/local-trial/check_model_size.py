#!/usr/bin/env python3
"""Count stored tensors in a complete unquantized safetensors checkpoint without loading weights.

Conservative cap check: includes any stored buffers/vision/MTP tensors. Does not
infer original parameter count from quantized weights or adapters.
"""
import argparse
import json
import math
import struct
from pathlib import Path


def count(path):
    files=sorted(path.glob('*.safetensors'))
    if not files: raise ValueError('No safetensors checkpoint files')
    index=path/'model.safetensors.index.json'
    mapping=json.loads(index.read_text())['weight_map'] if index.exists() else None
    if mapping and {p.name for p in files}!={*mapping.values()}: raise ValueError('Incomplete or mixed checkpoint shard set')
    seen={};total=0
    for file in files:
        with file.open('rb') as reader:
            header_size=struct.unpack('<Q',reader.read(8))[0]
            if header_size > 100_000_000: raise ValueError('Unreasonable safetensors header')
            header=json.loads(reader.read(header_size))
        for name,tensor in header.items():
            if name=='__metadata__':continue
            if name in seen:raise ValueError('Duplicate tensor across shards')
            if tensor['dtype'] not in {'BF16','F16','F32','F64'}:raise ValueError('Quantized/non-floating checkpoint: inspect original model parameter count separately')
            if mapping and mapping.get(name)!=file.name:raise ValueError('Tensor/index mismatch')
            start,end=tensor['data_offsets']
            if end < start or 8+header_size+end > file.stat().st_size:raise ValueError('Truncated checkpoint')
            seen[name]=file.name;total+=math.prod(tensor['shape'])
    if mapping and set(mapping)!=set(seen):raise ValueError('Missing tensors')
    return {'stored_tensor_elements':total,'tensor_count':len(seen),'shard_count':len(files),
      'maximum':32_000_000_000,'passes_conservative_32b_cap':total<=32_000_000_000,
      'scope':'complete unquantized stored tensor count including optional components; no runtime quality claim'}

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('checkpoint',type=Path);args=ap.parse_args()
    result=count(args.checkpoint);print(json.dumps(result,indent=2));raise SystemExit(0 if result['passes_conservative_32b_cap'] else 1)
