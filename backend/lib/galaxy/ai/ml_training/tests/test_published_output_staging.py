import ast
import io
import json
from pathlib import Path
import pytest
from galaxy.ai.ml_training import published_output_staging as staging
from galaxy.ai.ml_training.run_registration import list_registered_run_versions


class S3:
    def __init__(self, objects):
        self.objects, self.calls = objects, []
    def get_object(self, Bucket, Key):
        self.calls.append((Bucket, Key))
        data = self.objects[(Bucket, Key)]
        return {'Body': io.BytesIO(data), 'ContentLength': len(data)}


def payload():
    return [{'s3_uri': 's3://allowed/run/artifact/model.pkl', 'relative_path': 'model.pkl'},
            {'s3_uri': 's3://allowed/run/artifact/metadata.json', 'relative_path': 'metadata.json'}]


def client():
    return S3({('allowed','run/artifact/model.pkl'): b'inert bytes',
               ('allowed','run/artifact/metadata.json'): b'{"model_type":"sklearn_tabular"}',
               ('allowed','run/metrics.json'): b'{"name":"test","metrics":{"auc":0.8}}'})


def test_stages_exact_refs_without_executing_model(tmp_path):
    s3 = client()
    result = staging.stage_published_outputs(s3, {'allowed'}, payload(), 's3://allowed/run/metrics.json', str(tmp_path))
    assert Path(result.artifact_dir, 'model.pkl').read_bytes() == b'inert bytes'
    assert len(result.expected_artifact_sha256) == 64
    assert result.metrics_document['metrics']['auc'] == 0.8
    assert len(s3.calls) == 3


@pytest.mark.parametrize('relative', ['../private', '/absolute', 'a/../../private', 'a\\file', 'a//file', './file'])
def test_rejects_traversal_before_storage_reads(tmp_path, relative):
    s3 = client(); entries = payload(); entries[0]['relative_path'] = relative
    with pytest.raises(ValueError, match='relative path'):
        staging.stage_published_outputs(s3, {'allowed'}, entries, 's3://allowed/run/metrics.json', str(tmp_path))
    assert s3.calls == []


@pytest.mark.parametrize('uri', ['s3://private/file', 'http://localhost/private', 'file:///etc/passwd', 's3://allowed/run/file?x=1'])
def test_rejects_nonconfigured_storage_and_network_urls(tmp_path, uri):
    s3 = client(); entries = payload(); entries[0]['s3_uri'] = uri
    with pytest.raises(ValueError, match='configured-bucket'):
        staging.stage_published_outputs(s3, {'allowed'}, entries, 's3://allowed/run/metrics.json', str(tmp_path))
    assert s3.calls == []


def test_rejects_oversized_artifact_and_duplicate_references(tmp_path, monkeypatch):
    monkeypatch.setattr(staging, 'MAX_ARTIFACT_BYTES', 3)
    with pytest.raises(ValueError, match='size limit'):
        staging.stage_published_outputs(client(), {'allowed'}, payload(), 's3://allowed/run/metrics.json', str(tmp_path))
    with pytest.raises(ValueError, match='Duplicate'):
        staging.stage_published_outputs(client(), {'allowed'}, payload()[:1] * 2, 's3://allowed/run/metrics.json', str(tmp_path / 'other'))


def test_internal_routes_are_admin_only():
    source = Path(__file__).parents[3] / 'webapps/galaxy/api/models_training_internal.py'
    tree = ast.parse(source.read_text())
    routes = [node for node in ast.walk(tree) if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and isinstance(node.func.value, ast.Name) and node.func.value.id == 'router' and node.func.attr in ('post', 'get')]
    assert len(routes) == 2
    assert all(any(kw.arg == 'require_admin' and isinstance(kw.value, ast.Constant) and kw.value.value is True for kw in node.keywords) for node in routes)


def test_missing_owner_namespace_read_returns_no_global_models(tmp_path):
    assert list_registered_run_versions(str(tmp_path), 'owner', 'project') == []
    assert not list(tmp_path.iterdir())


def test_bucket_authority_matches_nextflow_deployment_names(monkeypatch):
    for key in ('AWS_S3_BUCKET', 'NEXTFLOW_S3_BUCKET', 'S3_BUCKET_NAME', 'AWS_S3_NEXTFLOW_BUCKET', 'AWS_NF_S3_BUCKET', 'AWS_S3_UPLOAD_BUCKET', 'S3_ENDPOINT_URL'):
        monkeypatch.delenv(key, raising=False)
    assert staging.configured_buckets() == {'biomate-nextflow-work'}
    monkeypatch.setenv('S3_ENDPOINT_URL', 'http://minio:9000')
    assert staging.configured_buckets() == {'biomate-data'}
    monkeypatch.setenv('AWS_S3_NEXTFLOW_BUCKET', 'configured-results')
    monkeypatch.setenv('AWS_NF_S3_BUCKET', 'configured-nf')
    assert staging.configured_buckets() == {'configured-results', 'configured-nf'}
