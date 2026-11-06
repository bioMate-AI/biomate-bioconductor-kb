import copy
from pathlib import Path
import sys
import pytest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from simulate_closed_loop import run, SimulatedLatentDataset
from campaign_assay_to_pairs import export_campaign_pairs
from dpo_unimomo_adapter import UniMoMoPairRecordLoader
from galaxy.ai.drug_discovery.assay_ingestion import AssayIngestionService


def test_simulated_platform_to_checkpoint_roundtrip(tmp_path):
    report = run(tmp_path)
    assert report['passed']
    assert all(report['checks'].values())
    import json
    manifest = json.loads((tmp_path / 'candidate_manifest.json').read_text())
    service = AssayIngestionService(str(tmp_path / 'assays.sqlite'))
    with pytest.raises(ValueError, match='Simulation flag'):
        export_campaign_pairs(service, manifest['campaign_id'], manifest)
    with pytest.raises(ValueError, match='campaign mismatch'):
        export_campaign_pairs(service, 'foreign-campaign', manifest, simulated=True)
    broken = copy.deepcopy(manifest)
    broken['candidates'] = broken['candidates'][1:]
    with pytest.raises(ValueError, match='missing from manifest'):
        export_campaign_pairs(service, manifest['campaign_id'], broken, simulated=True)
    # Foreign campaign rows cannot leak into the pair export.
    service.ingest('another-campaign', str(tmp_path / 'simulated_assays.csv'))
    assert len(export_campaign_pairs(service, manifest['campaign_id'], manifest, simulated=True).pairs) == 6
    service.ingest(manifest['campaign_id'], str(tmp_path / 'simulated_assays.csv'))
    with pytest.raises(ValueError, match='Replicate KD'):
        export_campaign_pairs(service, manifest['campaign_id'], manifest, simulated=True)


def test_loader_rejects_partial_missing_and_duplicate_ids():
    dataset = SimulatedLatentDataset([{'id': 'A'}, {'id': 'B'}])
    pairs = [{'chosen_id': 'A', 'rejected_id': 'B'}, {'chosen_id': 'A', 'rejected_id': 'missing'}]
    with pytest.raises(ValueError, match='Unmatched'):
        UniMoMoPairRecordLoader(pairs, dataset)
    dataset.ids[1] = 'A'
    with pytest.raises(ValueError, match='Duplicate'):
        UniMoMoPairRecordLoader(pairs[:1], dataset)


def test_loader_is_indexable_without_eager_materialization():
    dataset = SimulatedLatentDataset([{'id': 'A'}, {'id': 'B'}])
    loader = UniMoMoPairRecordLoader([{'chosen_id': 'A', 'rejected_id': 'B'}], dataset)
    assert len(loader) == 1
    chosen, rejected = loader[0]
    assert chosen['H_0'].shape == rejected['H_0'].shape


def test_nonfinite_dpo_does_not_write_checkpoint(tmp_path):
    import torch
    from dpo_unimomo_adapter import _UniMoMoShapedStub, _stub_sample, make_reference, train_dpo
    model = _UniMoMoShapedStub()
    reference = make_reference(model)
    original = {k: v.clone() for k, v in model.state_dict().items()}
    def invalid_forward(policy, batch, hw):
        return next(policy.parameters()).sum() * float('nan')
    checkpoint = tmp_path / 'invalid.ckpt'
    with pytest.raises(RuntimeError, match='Nonfinite DPO'):
        train_dpo(model, reference, [(_stub_sample(), _stub_sample(seed=1))],
                  beta=1., lr=.001, steps=1, forward_fn=invalid_forward, out_ckpt=str(checkpoint))
    assert not checkpoint.exists()
    assert all(torch.equal(v, original[k]) for k, v in model.state_dict().items())


@pytest.mark.parametrize('value,unit', [('NaN', 'nM'), ('inf', 'nM'), ('0', 'nM'), ('-5', 'nM'), ('1e308', 'mM')])
def test_platform_rejects_invalid_kd_before_sqlite(tmp_path, value, unit):
    path = tmp_path / 'invalid.csv'
    path.write_text(f'compound_id,assay_type,value,unit,assay_date\nA,Kd,{value},{unit},2026-10-03\n')
    service = AssayIngestionService(str(tmp_path / 'assays.sqlite'))
    result = service.ingest('SIMULATED-invalid', str(path))
    assert result['ingested'] == 0
    assert result['errors']
    assert service.get_campaign_results('SIMULATED-invalid') == []
