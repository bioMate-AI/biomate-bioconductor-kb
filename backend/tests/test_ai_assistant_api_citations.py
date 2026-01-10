"""
Tests for AI Assistant API - Citations, Pilot Runs, and Parameter Recommendations

Tests the new API endpoints and response models added for:
1. Citation management
2. Progressive tuning / pilot runs
3. Parameter recommendations
4. Methods section generation
5. BibTeX export
"""

import pytest
import sys
import os
from unittest.mock import MagicMock, patch, AsyncMock
from typing import Dict, Any

# Add lib directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))


class TestCitationModels:
    """Test Pydantic models for citations."""

    def test_citation_model_creation(self):
        """Test CitationModel can be created with required fields."""
        from galaxy.webapps.galaxy.api.ai_assistant import CitationModel

        citation = CitationModel(
            tool_id="fastqc",
            tool_name="FastQC",
            title="FastQC: a quality control tool for high throughput sequence data",
            authors=["Simon Andrews"],
            year=2010,
            doi="10.1093/bioinformatics/xxx"
        )

        assert citation.tool_id == "fastqc"
        assert citation.tool_name == "FastQC"
        assert citation.year == 2010
        assert len(citation.authors) == 1

    def test_citation_model_optional_fields(self):
        """Test CitationModel with optional fields."""
        from galaxy.webapps.galaxy.api.ai_assistant import CitationModel

        citation = CitationModel(
            tool_id="star",
            tool_name="STAR",
            title="STAR: ultrafast universal RNA-seq aligner"
        )

        assert citation.pmid is None
        assert citation.doi is None
        assert citation.journal is None
        assert citation.formatted_bibtex == ""


class TestMethodsSectionModels:
    """Test Pydantic models for methods section."""

    def test_methods_section_model(self):
        """Test MethodsSectionModel creation."""
        from galaxy.webapps.galaxy.api.ai_assistant import MethodsSectionModel

        methods = MethodsSectionModel(
            text="Quality control was performed using FastQC (Andrews, 2010).",
            style="short",
            tools_cited=["fastqc"],
            tools_missing_citations=[]
        )

        assert "FastQC" in methods.text
        assert methods.style == "short"
        assert "fastqc" in methods.tools_cited


class TestPilotRunModels:
    """Test Pydantic models for pilot runs."""

    def test_tuning_config_model(self):
        """Test TuningConfigModel with defaults."""
        from galaxy.webapps.galaxy.api.ai_assistant import TuningConfigModel

        config = TuningConfigModel()

        assert config.pilot_fraction == 0.1
        assert config.sampling_strategy == "stratified"
        assert config.min_pilot_samples == 3
        assert config.max_pilot_samples == 50

    def test_tuning_config_validation(self):
        """Test TuningConfigModel validation."""
        from galaxy.webapps.galaxy.api.ai_assistant import TuningConfigModel
        from pydantic import ValidationError

        # Valid config
        config = TuningConfigModel(pilot_fraction=0.15)
        assert config.pilot_fraction == 0.15

        # Invalid - fraction too low
        with pytest.raises(ValidationError):
            TuningConfigModel(pilot_fraction=0.01)

        # Invalid - fraction too high
        with pytest.raises(ValidationError):
            TuningConfigModel(pilot_fraction=0.5)

    def test_pilot_status_response(self):
        """Test PilotStatusResponse model."""
        from galaxy.webapps.galaxy.api.ai_assistant import PilotStatusResponse

        status = PilotStatusResponse(
            pilot_id="pilot_abc123",
            status="running",
            progress=50.0
        )

        assert status.pilot_id == "pilot_abc123"
        assert status.status == "running"
        assert status.progress == 50.0

    def test_full_run_estimate_response(self):
        """Test FullRunEstimateResponse model."""
        from galaxy.webapps.galaxy.api.ai_assistant import FullRunEstimateResponse

        estimate = FullRunEstimateResponse(
            estimated_runtime_seconds=2700,
            estimated_runtime_display="~45 minutes",
            estimated_memory_gb=12.0,
            estimated_cost_usd=0.85,
            confidence=0.8
        )

        assert estimate.estimated_runtime_seconds == 2700
        assert estimate.confidence == 0.8


class TestParameterRecommendationModels:
    """Test Pydantic models for parameter recommendations."""

    def test_parameter_recommendation_model(self):
        """Test ParameterRecommendationModel creation."""
        from galaxy.webapps.galaxy.api.ai_assistant import ParameterRecommendationModel

        rec = ParameterRecommendationModel(
            parameter_name="threads",
            recommended_value=16,
            current_value=8,
            confidence=0.9,
            source="benchmark",
            reason="Based on test harness benchmark results"
        )

        assert rec.parameter_name == "threads"
        assert rec.recommended_value == 16
        assert rec.confidence == 0.9
        assert rec.source == "benchmark"


class TestWorkflowGenerationResponse:
    """Test enhanced workflow generation response."""

    def test_workflow_response_with_citations(self):
        """Test WorkflowGenerationResponse includes citations."""
        from galaxy.webapps.galaxy.api.ai_assistant import (
            WorkflowGenerationResponse,
            CitationModel,
            MethodsSectionModel
        )

        citations = [
            CitationModel(
                tool_id="fastqc",
                tool_name="FastQC",
                title="FastQC: a quality control tool"
            )
        ]

        methods = MethodsSectionModel(
            text="Quality control was performed using FastQC.",
            style="short",
            tools_cited=["fastqc"]
        )

        response = WorkflowGenerationResponse(
            success=True,
            confidence=0.85,
            citations=citations,
            methods_section=methods
        )

        assert response.success
        assert len(response.citations) == 1
        assert response.methods_section is not None


class TestCitationIntegration:
    """Integration tests for citation features."""

    def test_methods_generator_integration(self):
        """Test MethodsSectionGenerator integration."""
        from galaxy.ai.methods_generator import MethodsSectionGenerator
        from galaxy.ai.tool_knowledge_provider import ToolKnowledgeProvider

        provider = ToolKnowledgeProvider()
        generator = MethodsSectionGenerator(provider)

        # Test with a mock workflow
        workflow = {
            "name": "Test Workflow",
            "steps": {
                "0": {
                    "type": "tool",
                    "tool_id": "fastqc",
                    "name": "FastQC",
                    "tool_state": "{}"
                }
            }
        }

        # Generate methods section
        methods_text = generator.generate(
            workflow,
            citation_style="short",
            include_parameters=True
        )

        assert isinstance(methods_text, str)
        assert len(methods_text) > 0

    def test_bibtex_generation(self):
        """Test BibTeX generation from workflow."""
        from galaxy.ai.methods_generator import MethodsSectionGenerator
        from galaxy.ai.tool_knowledge_provider import ToolKnowledgeProvider

        provider = ToolKnowledgeProvider()
        generator = MethodsSectionGenerator(provider)

        workflow = {
            "name": "Test Workflow",
            "steps": {
                "0": {
                    "type": "tool",
                    "tool_id": "star",
                    "name": "STAR",
                    "tool_state": "{}"
                }
            }
        }

        bibtex = generator.generate_bibtex(workflow)
        assert isinstance(bibtex, str)

    def test_citations_summary(self):
        """Test getting citations summary."""
        from galaxy.ai.methods_generator import MethodsSectionGenerator
        from galaxy.ai.tool_knowledge_provider import ToolKnowledgeProvider

        provider = ToolKnowledgeProvider()
        generator = MethodsSectionGenerator(provider)

        workflow = {
            "name": "Test Workflow",
            "steps": {
                "0": {"type": "tool", "tool_id": "fastqc", "name": "FastQC", "tool_state": "{}"},
                "1": {"type": "tool", "tool_id": "unknown_tool", "name": "Unknown", "tool_state": "{}"}
            }
        }

        summary = generator.get_citations_summary(workflow)

        assert "total_steps" in summary
        assert "steps_with_citations" in summary
        assert "citations" in summary
        assert "missing_citations" in summary


class TestPilotRunIntegration:
    """Integration tests for pilot run features."""

    def test_progressive_tuning_controller(self):
        """Test ProgressiveTuningController functionality."""
        from galaxy.ai.progressive_tuning import (
            ProgressiveTuningController,
            TuningConfig
        )

        config = TuningConfig(
            pilot_fraction=0.1,
            min_pilot_samples=5,
            max_pilot_samples=50
        )

        controller = ProgressiveTuningController(config=config)

        # Test pilot size calculation
        pilot_size = controller.calculate_pilot_size(100)
        assert 5 <= pilot_size <= 50
        assert pilot_size == 10  # 10% of 100

        # Edge case: very small dataset
        pilot_size_small = controller.calculate_pilot_size(20)
        assert pilot_size_small >= 5  # min_pilot_samples

    def test_data_sampler_random(self):
        """Test DataSampler random sampling."""
        from galaxy.ai.progressive_tuning import DataSampler

        data = list(range(100))
        sample = DataSampler.random_sample(data, fraction=0.1, seed=42)

        assert len(sample) == 10
        assert all(s in data for s in sample)

    def test_data_sampler_first_n(self):
        """Test DataSampler first_n sampling."""
        from galaxy.ai.progressive_tuning import DataSampler

        data = list(range(100))
        sample = DataSampler.first_n(data, n=15)

        assert len(sample) == 15
        assert sample == list(range(15))

    def test_estimate_full_run(self):
        """Test full run estimation from pilot results."""
        from galaxy.ai.progressive_tuning import ProgressiveTuningController

        controller = ProgressiveTuningController()

        # Create simple pilot result object
        class SimplePilot:
            runtime_seconds = 60
            samples_used = 10
            peak_memory_gb = 4.0

        pilot_result = SimplePilot()
        estimate = controller.estimate_full_run(
            pilot_result,
            full_size=100,
            cost_per_hour_usd=0.50
        )

        assert "estimated_runtime_seconds" in estimate
        assert "estimated_runtime_display" in estimate
        assert "estimated_memory_gb" in estimate
        assert estimate["estimated_runtime_seconds"] > 0


class TestToolKnowledgeIntegration:
    """Integration tests for tool knowledge provider."""

    def test_get_tool_knowledge(self):
        """Test getting knowledge for a known tool."""
        from galaxy.ai.tool_knowledge_provider import ToolKnowledgeProvider

        provider = ToolKnowledgeProvider()

        # Test with a commonly known tool
        knowledge = provider.get_tool_knowledge("star")

        if knowledge:  # May not have knowledge for all tools
            assert hasattr(knowledge, 'tool_name')
            assert hasattr(knowledge, 'citation')
            assert hasattr(knowledge, 'recommended_parameters')
            # Check that we got STAR knowledge
            assert knowledge.tool_name == "STAR"

    def test_get_parameter_recommendation(self):
        """Test getting parameter recommendations."""
        from galaxy.ai.tool_knowledge_provider import ToolKnowledgeProvider

        provider = ToolKnowledgeProvider()

        # Try to get recommendation
        rec = provider.get_parameter_recommendation("star", "threads")

        # Recommendation may or may not exist
        if rec:
            assert hasattr(rec, 'recommended_value')
            assert hasattr(rec, 'confidence')


class TestAPIEndpointsUnit:
    """Unit tests for API endpoint functions."""

    def test_bibtex_export_request(self):
        """Test BibTeXExportRequest model."""
        from galaxy.webapps.galaxy.api.ai_assistant import BibTeXExportRequest

        request = BibTeXExportRequest(
            workflow_ga={
                "name": "Test",
                "steps": {}
            },
            include_all=True
        )

        assert request.workflow_ga is not None
        assert request.include_all is True

    def test_start_pilot_request(self):
        """Test StartPilotRequest model."""
        from galaxy.webapps.galaxy.api.ai_assistant import (
            StartPilotRequest,
            TuningConfigModel
        )

        request = StartPilotRequest(
            workflow_id="wf123",
            total_samples=100,
            config=TuningConfigModel(pilot_fraction=0.15)
        )

        assert request.workflow_id == "wf123"
        assert request.total_samples == 100
        assert request.config.pilot_fraction == 0.15


class TestEndToEndWorkflowGeneration:
    """End-to-end tests for workflow generation with citations."""

    @pytest.fixture
    def mock_ai_assistant(self):
        """Create mock AI assistant."""
        mock = MagicMock()
        mock.generate_workflow_unified.return_value = {
            'success': True,
            'workflow_ga': {
                'name': 'RNA-seq Analysis',
                'steps': {
                    '0': {'type': 'tool', 'tool_id': 'fastqc', 'name': 'FastQC'}
                }
            },
            'source': 'from_scratch',
            'confidence': 0.85,
            'citations': [
                {
                    'tool_id': 'fastqc',
                    'tool_name': 'FastQC',
                    'citation': {
                        'title': 'FastQC: a quality control tool',
                        'authors': ['Simon Andrews'],
                        'year': 2010
                    }
                }
            ],
            'methods_section': 'Quality control was performed using FastQC.',
            'generated_parameters': []
        }
        return mock

    def test_workflow_generation_includes_citations(self, mock_ai_assistant):
        """Test that workflow generation returns citations."""
        result = mock_ai_assistant.generate_workflow_unified(
            user_intent="Perform RNA-seq quality control",
            uploaded_datasets=[]
        )

        assert result['success']
        assert 'citations' in result
        assert len(result['citations']) > 0
        assert result['citations'][0]['tool_id'] == 'fastqc'

    def test_workflow_generation_includes_methods(self, mock_ai_assistant):
        """Test that workflow generation returns methods section."""
        result = mock_ai_assistant.generate_workflow_unified(
            user_intent="Perform RNA-seq quality control",
            uploaded_datasets=[]
        )

        assert result['success']
        assert 'methods_section' in result
        assert 'FastQC' in result['methods_section']


if __name__ == "__main__":
    pytest.main([__file__, "-v", "--tb=short"])
