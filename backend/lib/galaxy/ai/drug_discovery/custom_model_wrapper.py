"""
Custom model wrapper for BioMate drug discovery pipelines.

Supports three integration modes:
  1. Python function (callable)
  2. Docker container (via subprocess)
  3. REST endpoint (via requests)
"""
import json
import subprocess
import logging
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Callable, Optional

log = logging.getLogger(__name__)


@dataclass
class ModelRunRecord:
    model_name: str
    campaign_id: str
    mode: str              # 'python' | 'docker' | 'rest'
    input_count: int
    output_count: int
    run_at: str
    duration_s: float
    success: bool
    error: Optional[str] = None


class BaseModelWrapper(ABC):
    def __init__(self, name: str, campaign_id: str,
                 weight: float = 1.0, higher_is_better: bool = True):
        self.name = name
        self.campaign_id = campaign_id
        self.weight = weight
        self.higher_is_better = higher_is_better
        self.enabled = True

    @abstractmethod
    def score(self, smiles_list: list[str]) -> dict[str, float]:
        """Return {smiles: score} for each input SMILES."""
        ...

    def run(self, smiles_list: list[str]) -> tuple[dict[str, float], ModelRunRecord]:
        """Call score(), record the run, return results + audit record."""
        t0 = datetime.now(timezone.utc)
        try:
            scores = self.score(smiles_list)
            duration = (datetime.now(timezone.utc) - t0).total_seconds()
            record = ModelRunRecord(
                model_name=self.name, campaign_id=self.campaign_id,
                mode=self._mode(), input_count=len(smiles_list),
                output_count=len(scores), run_at=t0.isoformat(),
                duration_s=duration, success=True
            )
            return scores, record
        except Exception as e:
            duration = (datetime.now(timezone.utc) - t0).total_seconds()
            record = ModelRunRecord(
                model_name=self.name, campaign_id=self.campaign_id,
                mode=self._mode(), input_count=len(smiles_list),
                output_count=0, run_at=t0.isoformat(),
                duration_s=duration, success=False, error=str(e)
            )
            raise

    @abstractmethod
    def _mode(self) -> str: ...


class PythonFunctionWrapper(BaseModelWrapper):
    """Wrap a plain Python callable: fn(smiles_list) -> {smiles: float}"""

    def __init__(self, name: str, campaign_id: str, fn: Callable,
                 weight: float = 1.0, higher_is_better: bool = True):
        super().__init__(name, campaign_id, weight, higher_is_better)
        self._fn = fn

    def score(self, smiles_list: list[str]) -> dict[str, float]:
        result = self._fn(smiles_list)
        if not isinstance(result, dict):
            raise ValueError(f"Model {self.name}: expected dict output, got {type(result)}")
        return {str(k): float(v) for k, v in result.items()}

    def _mode(self) -> str:
        return 'python'


class DockerModelWrapper(BaseModelWrapper):
    """Wrap a Docker container that reads SMILES from stdin and writes JSON scores to stdout."""

    def __init__(self, name: str, campaign_id: str, image: str,
                 input_format: str = 'smiles_one_per_line',
                 output_format: str = 'json_smiles_to_score',
                 weight: float = 1.0, higher_is_better: bool = True,
                 extra_args: list[str] = None):
        super().__init__(name, campaign_id, weight, higher_is_better)
        self.image = image
        self.input_format = input_format
        self.output_format = output_format
        self.extra_args = extra_args or []

    def score(self, smiles_list: list[str]) -> dict[str, float]:
        stdin_data = '\n'.join(smiles_list).encode()
        cmd = ['docker', 'run', '--rm', '-i'] + self.extra_args + [self.image]
        proc = subprocess.run(cmd, input=stdin_data, capture_output=True, timeout=300)
        if proc.returncode != 0:
            raise RuntimeError(
                f"Docker model {self.name} failed: {proc.stderr.decode()[:500]}"
            )
        return json.loads(proc.stdout.decode())

    def _mode(self) -> str:
        return 'docker'


class RESTModelWrapper(BaseModelWrapper):
    """Wrap a REST endpoint: POST {smiles: [list]} → parse scores from response."""

    def __init__(self, name: str, campaign_id: str, endpoint: str,
                 input_key: str = 'smiles', output_path: str = 'scores',
                 weight: float = 1.0, higher_is_better: bool = True,
                 headers: dict = None, timeout: int = 60):
        super().__init__(name, campaign_id, weight, higher_is_better)
        self.endpoint = endpoint
        self.input_key = input_key
        self.output_path = output_path
        self.headers = headers or {'Content-Type': 'application/json'}
        self.timeout = timeout

    def score(self, smiles_list: list[str]) -> dict[str, float]:
        try:
            import requests
        except ImportError:
            raise ImportError("requests library required for RESTModelWrapper")
        payload = {self.input_key: smiles_list}
        resp = requests.post(self.endpoint, json=payload,
                             headers=self.headers, timeout=self.timeout)
        resp.raise_for_status()
        data = resp.json()
        # Traverse output_path (dot-separated), stripping leading '$.'
        for key in self.output_path.lstrip('$.').split('.'):
            data = data[key]
        if isinstance(data, list):
            return {s: float(v) for s, v in zip(smiles_list, data)}
        return {str(k): float(v) for k, v in data.items()}

    def _mode(self) -> str:
        return 'rest'
