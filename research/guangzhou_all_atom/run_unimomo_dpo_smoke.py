"""Real UniMoMo CUDA integration with explicitly SIMULATED assay preferences.

Requires the pinned UniMoMo environment, staged platform assay modules under
platform_assay, and a processed train mmap. Real structures/weights are used only
to verify the data/optimizer path; synthetic affinities carry no biological claim.
"""
import argparse
import csv
import json
from pathlib import Path
import torch
from platform_assay.assay_ingestion import AssayIngestionService
from campaign_assay_to_pairs import export_campaign_pairs
from dpo_unimomo_adapter import (build_unimomo_policy, make_reference, UniMoMoPairRecordLoader,
                                train_dpo, denoise_loss_unimomo, diffusion_dpo_loss)
from data.peptide import PeptideDataset


def run(args):
    if not torch.cuda.is_available(): raise RuntimeError('CUDA required')
    out = args.out
    out.mkdir(parents=True, exist_ok=True)
    if (out / 'SIMULATED_assays.sqlite').exists(): raise ValueError('Use a new smoke output directory')
    dataset = PeptideDataset(str(args.dataset), specify_index=str(args.dataset / 'train_index.txt'))
    # Three smallest real complexes bound memory while exercising real mmap/featurization.
    indices = sorted(range(len(dataset)), key=dataset.get_len)[:3]
    if len(indices) != 3: raise ValueError('Need three processed structures')
    candidates = [{'id': dataset.get_id(i), 'sequence': dataset.get_summary(i).ref_seq,
                   'target': 'SIMULATED-integration-target'} for i in indices]
    manifest = {'campaign_id': 'SIMULATED-UNIMOMO-DPO', 'data_origin': 'simulated', 'candidates': candidates}
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    path = out / 'SIMULATED_assays.csv'
    with path.open('w', newline='') as handle:
        writer = csv.writer(handle)
        writer.writerow(['compound_id', 'assay_type', 'value', 'unit', 'assay_date', 'operator_note'])
        for candidate, kd in zip(candidates, [12, 800, 100000]):
            writer.writerow([candidate['id'], 'Kd', kd, 'nM', '2026-10-03', 'SIMULATED integration only'])
    service = AssayIngestionService(str(out / 'SIMULATED_assays.sqlite'))
    ingestion = service.ingest(manifest['campaign_id'], str(path))
    assert ingestion['ingested'] == 3 and not ingestion['errors'], ingestion
    pairs = export_campaign_pairs(service, manifest['campaign_id'], manifest, simulated=True)
    pairs.write_jsonl(out / 'SIMULATED_pairs.jsonl')
    assert len(pairs.pairs) == 3, 'Expected three preference pairs'
    loader = UniMoMoPairRecordLoader([p.to_dict() for p in pairs.pairs], dataset, device='cuda:0')
    torch.manual_seed(0)
    policy = build_unimomo_policy(str(args.checkpoint), device='cuda:0')
    reference = make_reference(policy).to('cuda:0')
    before = {k: v.detach().cpu().clone() for k, v in policy.state_dict().items()}
    reference_before = {k: v.detach().cpu().clone() for k, v in reference.state_dict().items()}
    def evaluate():
        policy.eval(); reference.eval()
        result = []
        with torch.no_grad():
            for i, (chosen, rejected) in enumerate(loader):
                torch.manual_seed(100 + i)
                _, metrics = diffusion_dpo_loss(policy, reference, chosen, rejected, beta=1.,
                                                 forward_fn=denoise_loss_unimomo)
                result.append(metrics.__dict__)
        return result
    initial = evaluate()
    torch.manual_seed(123)
    trained = train_dpo(policy, reference, loader, beta=1., lr=1e-6, steps=3,
                        forward_fn=denoise_loss_unimomo, out_ckpt=str(out / 'SIMULATED_policy.ckpt'))
    final = evaluate()
    ae_names = [k for k in before if k.startswith('autoencoder.')]
    changed = [k for k, p in policy.named_parameters() if p.requires_grad and not torch.equal(before[k], p.detach().cpu())]
    reloaded = torch.load(out / 'SIMULATED_policy.ckpt', map_location='cpu')
    checks = {
        'three_pairs_loaded': len(loader) == 3,
        'three_updates_completed': len(trained.step_metrics) == 3,
        'all_reference_state_unchanged': all(torch.equal(reference_before[k], v.detach().cpu()) for k, v in reference.state_dict().items()),
        'frozen_ae_unchanged': bool(ae_names) and all(torch.equal(before[k], policy.state_dict()[k].detach().cpu()) for k in ae_names),
        'trainable_weights_changed': bool(changed),
        'checkpoint_roundtrip_exact': all(torch.equal(v.detach().cpu(), reloaded.state_dict()[k]) for k, v in policy.state_dict().items()),
        'finite_weights': all(bool(torch.isfinite(p).all()) for p in policy.parameters()),
    }
    report = {'data_origin': 'simulated', 'model': 'real pinned UniMoMo on CUDA',
              'claim': 'Integration mechanics only; simulated KD across fixture complexes is not biological evidence',
              'checks': checks, 'passed': all(checks.values()), 'before': initial, 'after': final,
              'candidate_ids': [c['id'] for c in candidates], 'changed_parameters': len(changed)}
    (out / 'integration_report.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))
    assert report['passed'], checks


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dataset', required=True, type=Path)
    parser.add_argument('--checkpoint', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    run(parser.parse_args())
