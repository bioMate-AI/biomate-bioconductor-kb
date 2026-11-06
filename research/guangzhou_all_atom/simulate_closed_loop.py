"""SIMULATED assay -> real platform persistence -> preferences -> DPO -> reload/evaluate.

Only assay observations and latent/model fixtures are simulated. The platform
service, preference conversion, ID loader, DPO optimizer, and checkpoint IO are
executed directly. This is not full UniMoMo or evidence of biological improvement.
"""
import argparse
import csv
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parents[1] / 'backend/lib'))
from galaxy.ai.drug_discovery.assay_ingestion import AssayIngestionService
from campaign_assay_to_pairs import export_campaign_pairs
from dpo_unimomo_adapter import (
    UniMoMoPairRecordLoader, _UniMoMoShapedStub, _stub_sample, denoise_loss_unimomo,
    make_reference, train_dpo, load_pairset_jsonl, diffusion_dpo_loss,
)
import torch


class SimulatedLatentDataset:
    """Explicit simulation fixture with the dataset ID/collate interface."""
    def __init__(self, candidates):
        self.ids = [c['id'] for c in candidates]
        self.items = [_stub_sample(seed=1000 + i) for i in range(len(self.ids))]

    def __len__(self): return len(self.ids)
    def get_id(self, idx): return self.ids[idx]
    def __getitem__(self, idx): return self.items[idx]
    def collate_fn(self, items):
        if len(items) != 1: raise ValueError('Simulation fixture requires one candidate per batch')
        return items[0]


def evaluate(policy, ref, loader):
    policy.eval()
    margins, losses = [], []
    with torch.no_grad():
        for i, (chosen, rejected) in enumerate(loader):
            # Identical independent evaluation draws before and after training.
            for draw in range(8):
                torch.manual_seed(9000 + i * 8 + draw)
                _, metrics = diffusion_dpo_loss(policy, ref, chosen, rejected, beta=1.,
                                                 forward_fn=denoise_loss_unimomo)
                margins.append(metrics.reward_margin)
                losses.append(metrics.loss)
    return {'mean_reward_margin': sum(margins) / len(margins),
            'mean_dpo_loss': sum(losses) / len(losses), 'evaluation_draws': len(margins)}


def run(out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    # An existing DB would duplicate assay rows. Each run owns a fresh output dir.
    if (out / 'assays.sqlite').exists():
        raise ValueError('Use a fresh output directory; simulation DB already exists')
    torch.set_num_threads(1)
    torch.manual_seed(0)
    campaign = 'SIMULATED-cyclic-integration'
    candidates = [dict(id=f'SIM-{i}', sequence=seq, target='SIM-TARGET-A' if i < 3 else 'SIM-TARGET-B')
                  for i, seq in enumerate(['ACDEFG', 'HIKLMN', 'PQRSTV', 'WYACDE', 'FGHIKL', 'MNPQRS'])]
    manifest = dict(campaign_id=campaign, data_origin='simulated', candidates=candidates)
    (out / 'candidate_manifest.json').write_text(json.dumps(manifest, indent=2))
    csv_path = out / 'simulated_assays.csv'
    with csv_path.open('w', newline='') as handle:
        writer = csv.writer(handle)
        writer.writerow(['compound_id', 'assay_type', 'value', 'unit', 'assay_date', 'operator', 'operator_note'])
        for i, candidate in enumerate(candidates):
            writer.writerow([candidate['id'], 'Kd', [12, 800, 100000][i % 3], 'nM', '2026-10-03',
                             '>' if i % 3 == 2 else '=', 'SIMULATED integration fixture; not measured'])
    service = AssayIngestionService(str(out / 'assays.sqlite'))
    ingestion = service.ingest(campaign, str(csv_path))
    if ingestion['errors'] or ingestion['ingested'] != 6:
        raise RuntimeError(f'Assay ingestion failed: {ingestion}')
    # Reload from disk through a fresh service instance, not transient objects.
    service = AssayIngestionService(str(out / 'assays.sqlite'))
    pairset = export_campaign_pairs(service, campaign, manifest, simulated=True)
    pairset.write_jsonl(out / 'simulated_pairs.jsonl')
    pairs = load_pairset_jsonl(str(out / 'simulated_pairs.jsonl'))
    dataset = SimulatedLatentDataset(candidates)
    loader = UniMoMoPairRecordLoader(pairs, dataset)
    policy = _UniMoMoShapedStub()
    reference = make_reference(policy)
    ref_before = {key: value.clone() for key, value in reference.state_dict().items()}
    policy_before = {key: value.clone() for key, value in policy.state_dict().items()}
    before = evaluate(policy, reference, loader)
    checkpoint = out / 'SIMULATED_policy.ckpt'
    torch.manual_seed(123)
    trained = train_dpo(policy, reference, loader, beta=1., lr=2e-3, steps=120,
                        forward_fn=denoise_loss_unimomo, log_every=30, out_ckpt=str(checkpoint))
    # This is our own freshly written checkpoint, not an untrusted input pickle.
    reloaded = torch.load(checkpoint, map_location='cpu', weights_only=False)
    after = evaluate(reloaded, reference, loader)
    checks = {
        'six_assays_persisted': len(service.get_campaign_results(campaign)) == 6,
        'six_within_target_pairs': len(pairs) == 6,
        'simulated_provenance_preserved': all(p['provenance']['data_origin'] == 'simulated' for p in pairs),
        'all_candidate_ids_resolve': len(loader) == len(pairs),
        'all_reference_state_unchanged': all(torch.equal(ref_before[k], v) for k, v in reference.state_dict().items()),
        'policy_changed': any(not torch.equal(policy_before[k], v) for k, v in policy.state_dict().items()),
        'checkpoint_roundtrip_exact': all(torch.equal(v, reloaded.state_dict()[k]) for k, v in policy.state_dict().items()),
        'matched_noise_loss_decreased': after['mean_dpo_loss'] < before['mean_dpo_loss'],
        'matched_noise_margin_increased': after['mean_reward_margin'] > before['mean_reward_margin'],
        'steps_completed': len(trained.step_metrics) == 120,
    }
    report = dict(data_origin='simulated', scope='platform service + DPO mechanics, simulated latent model',
                  limitations=['No live HTTP/UI test', 'No real UniMoMo featurization in this CPU run',
                               'Training-pair evaluation only; no biological or generalization claim'],
                  campaign_id=campaign, ingestion=ingestion, before=before, after=after,
                  checks=checks, passed=all(checks.values()))
    (out / 'integration_report.json').write_text(json.dumps(report, indent=2) + '\n')
    if not report['passed']: raise RuntimeError(json.dumps(checks))
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(run(args.out), indent=2))
