"""
Galaxy Parameter Inference API

RESTful API endpoints for intelligent parameter inference including:
- Pilot data analysis
- Progressive context gathering
- Full parameter inference pipeline
"""

import json
import logging
from typing import Dict, List, Any, Optional, Union
from pathlib import Path

from fastapi import HTTPException, UploadFile, File, Form
from pydantic import BaseModel, Field

from galaxy.managers.context import ProvidesUserContext
from galaxy.webapps.galaxy.api import (
    DependsOnTrans,
    Router
)

# Import parameter inference components
try:
    from galaxy.ai.pilot_analysis import (
        get_pilot_manager,
        PilotAnalysisExecutor,
        AnalysisResult,
        run_pilot_analysis
    )
    from galaxy.ai.agents.context_gatherer import ContextGatherer
    PARAMETER_INFERENCE_AVAILABLE = True
except ImportError as e:
    logging.warning(f"Parameter inference components not available: {e}")
    PARAMETER_INFERENCE_AVAILABLE = False
    get_pilot_manager = None
    PilotAnalysisExecutor = None
    ContextGatherer = None

log = logging.getLogger(__name__)

router = Router(tags=["parameter_inference"])


# ============================================================================
# Request/Response Models
# ============================================================================

class PilotAnalysisRequest(BaseModel):
    """Request to run pilot analysis on user data."""
    analyzer_name: str = Field(..., description="Name of pilot analyzer to run")
    input_file_path: str = Field(..., description="Path to input data file")
    params: Optional[Dict[str, Any]] = Field(default=None, description="Optional additional parameters")


class PilotAnalysisResponse(BaseModel):
    """Response from pilot analysis execution."""
    analyzer_name: str
    status: str  # "success", "failed", "timeout", "fallback"
    extracted_data: Dict[str, Any]
    execution_time_seconds: float
    used_fallback: bool
    error_message: Optional[str] = None
    metadata: Dict[str, Any] = Field(default_factory=dict)


class PilotAnalyzerInfo(BaseModel):
    """Information about an available pilot analyzer."""
    name: str
    domain: str
    description: str
    input_type: str
    runtime_estimate: str
    max_runtime_seconds: int
    output_type: str


class PilotAnalyzersListResponse(BaseModel):
    """Response listing available pilot analyzers."""
    total_analyzers: int
    analyzers_by_domain: Dict[str, int]
    quick_analyzers_count: int  # <30s
    analyzers: List[PilotAnalyzerInfo]


class ContextGatheringRequest(BaseModel):
    """Request for progressive context gathering."""
    tool_id: str = Field(..., description="Tool identifier")
    initial_query: Optional[str] = Field(default=None, description="User's natural language query")
    user_answers: Optional[Dict[str, Any]] = Field(default=None, description="Answers to previous questions")
    input_files: Optional[Dict[str, str]] = Field(default=None, description="Uploaded data files for pilot analysis")


class ContextQuestion(BaseModel):
    """A context gathering question for the user."""
    field: str
    question: str
    type: str  # "select" or "text"
    parameter: str
    help_text: str
    options: Optional[List[Dict[str, Any]]] = None
    allow_custom: Optional[bool] = None
    placeholder: Optional[str] = None


class ContextGatheringResponse(BaseModel):
    """Response from context gathering."""
    status: str  # "need_more_context" or "context_complete"
    questions: Optional[List[ContextQuestion]] = None
    context: Optional[Dict[str, Any]] = None
    gathered_so_far: Dict[str, Any]
    progress: Optional[Dict[str, int]] = None
    summary: Optional[str] = None
    pilot_analysis_results: Optional[Dict[str, Any]] = None


class ParameterInferenceRequest(BaseModel):
    """Request for full parameter inference pipeline."""
    tool_id: str = Field(..., description="Tool identifier")
    user_query: str = Field(..., description="User's natural language description")
    input_files: Optional[Dict[str, str]] = Field(default=None, description="Uploaded data files")
    user_context: Optional[Dict[str, Any]] = Field(default=None, description="User-provided context")
    enable_pilot_analysis: bool = Field(default=True, description="Enable automatic pilot analysis")


class ParameterInferenceResponse(BaseModel):
    """Response from parameter inference pipeline."""
    tool_id: str
    inferred_parameters: Dict[str, Any]
    context_used: Dict[str, Any]
    pilot_analysis_run: bool
    pilot_analysis_results: Optional[Dict[str, Any]] = None
    confidence: Dict[str, str]  # parameter -> confidence level ("high", "medium", "low")
    recommendations: List[str]
    warnings: List[str] = Field(default_factory=list)


# ============================================================================
# API Endpoints
# ============================================================================

@router.get(
    "/api/pilot_analysis/analyzers",
    summary="List available pilot analyzers"
)
def list_pilot_analyzers(
    domain: Optional[str] = None,
    input_type: Optional[str] = None,
    quick_only: bool = False,
    trans: ProvidesUserContext = DependsOnTrans
) -> PilotAnalyzersListResponse:
    """
    Get list of available pilot analyzers.

    Args:
        domain: Optional filter by domain (genomics, cryo_em, etc.)
        input_type: Optional filter by input type (bam, fastq, etc.)
        quick_only: Only return quick analyzers (<30s)

    Returns:
        List of available analyzers with metadata
    """
    if not PARAMETER_INFERENCE_AVAILABLE:
        raise HTTPException(status_code=503, detail="Parameter inference not available")

    try:
        manager = get_pilot_manager()

        # Get analyzers based on filters
        if domain:
            analyzers = manager.get_domain_analyzers(domain)
            analyzers_list = [
                {"name": name, "domain": domain, "spec": spec}
                for name, spec in analyzers.items()
            ]
        elif input_type:
            analyzers_list = manager.get_analyzers_by_input_type(input_type)
        elif quick_only:
            analyzers_list = manager.get_quick_analyzers(max_runtime=30)
        else:
            all_analyzers = manager.get_all_analyzers()
            analyzers_list = [
                {"name": name, "domain": info["domain"], "spec": info["spec"]}
                for name, info in all_analyzers.items()
            ]

        # Convert to response format
        analyzer_infos = []
        for item in analyzers_list:
            spec = item["spec"]
            analyzer_infos.append(PilotAnalyzerInfo(
                name=item["name"],
                domain=item["domain"],
                description=spec.description,
                input_type=spec.input_type,
                runtime_estimate=spec.runtime_estimate,
                max_runtime_seconds=spec.max_runtime_seconds,
                output_type=spec.output_type
            ))

        # Get stats
        counts = manager.get_analyzer_count_by_domain()
        quick_count = len(manager.get_quick_analyzers(30))

        return PilotAnalyzersListResponse(
            total_analyzers=len(analyzer_infos),
            analyzers_by_domain=counts,
            quick_analyzers_count=quick_count,
            analyzers=analyzer_infos
        )

    except Exception as e:
        log.error(f"Error listing pilot analyzers: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post(
    "/api/pilot_analysis/run",
    summary="Run pilot analyzer on data"
)
def run_pilot_analyzer(
    request: PilotAnalysisRequest,
    trans: ProvidesUserContext = DependsOnTrans
) -> PilotAnalysisResponse:
    """
    Execute a pilot analyzer on user data.

    Args:
        request: Analyzer name, input file path, and optional parameters

    Returns:
        Analysis results with extracted context
    """
    if not PARAMETER_INFERENCE_AVAILABLE:
        raise HTTPException(status_code=503, detail="Parameter inference not available")

    try:
        executor = PilotAnalysisExecutor(use_fallback_on_error=True)

        result = executor.run_analyzer(
            request.analyzer_name,
            request.input_file_path,
            request.params
        )

        return PilotAnalysisResponse(
            analyzer_name=result.analyzer_name,
            status=result.status,
            extracted_data=result.extracted_data,
            execution_time_seconds=result.execution_time_seconds,
            used_fallback=result.used_fallback,
            error_message=result.error_message,
            metadata=result.metadata
        )

    except Exception as e:
        log.error(f"Error running pilot analyzer: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post(
    "/api/pilot_analysis/batch",
    summary="Run multiple pilot analyzers"
)
def run_pilot_batch(
    analyzer_names: List[str],
    input_file_path: str,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, PilotAnalysisResponse]:
    """
    Run multiple pilot analyzers on the same input file.

    Args:
        analyzer_names: List of analyzer names to run
        input_file_path: Path to input data file

    Returns:
        Dict mapping analyzer names to results
    """
    if not PARAMETER_INFERENCE_AVAILABLE:
        raise HTTPException(status_code=503, detail="Parameter inference not available")

    try:
        executor = PilotAnalysisExecutor(use_fallback_on_error=True)

        results = executor.run_batch(analyzer_names, input_file_path)

        return {
            name: PilotAnalysisResponse(
                analyzer_name=result.analyzer_name,
                status=result.status,
                extracted_data=result.extracted_data,
                execution_time_seconds=result.execution_time_seconds,
                used_fallback=result.used_fallback,
                error_message=result.error_message,
                metadata=result.metadata
            )
            for name, result in results.items()
        }

    except Exception as e:
        log.error(f"Error running pilot batch: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post(
    "/api/context_gathering/chat",
    summary="Progressive context gathering dialogue"
)
def context_gathering_chat(
    request: ContextGatheringRequest,
    trans: ProvidesUserContext = DependsOnTrans
) -> ContextGatheringResponse:
    """
    Progressive context gathering through dialogue.

    This endpoint handles the iterative process of gathering context:
    1. Initial query → extract what we can
    2. Generate questions for missing info (max 3 at a time)
    3. User answers → incorporate into context
    4. Run pilot analysis if data files provided
    5. Repeat until context complete

    Args:
        request: Tool ID, query, user answers, and optional input files

    Returns:
        Current status, questions (if needed), or complete context
    """
    if not PARAMETER_INFERENCE_AVAILABLE:
        raise HTTPException(status_code=503, detail="Parameter inference not available")

    try:
        # Create context gatherer for this tool
        gatherer = ContextGatherer(
            tool_id=request.tool_id,
            enable_pilot_analysis=True
        )

        # Gather context from query and user answers
        result = gatherer.gather_context(
            initial_query=request.initial_query or "",
            user_answers=request.user_answers
        )

        # Run pilot analysis if input files provided
        pilot_results = None
        if request.input_files and result['status'] != 'context_complete':
            pilot_results = gatherer.run_pilot_analysis(request.input_files)

            # Re-check if context is now complete after pilot analysis
            result = gatherer.gather_context("", None)

        # Convert to response format
        questions = None
        if result.get('questions'):
            questions = [
                ContextQuestion(
                    field=q['field'],
                    question=q['question'],
                    type=q['type'],
                    parameter=q['parameter'],
                    help_text=q['help_text'],
                    options=q.get('options'),
                    allow_custom=q.get('allow_custom'),
                    placeholder=q.get('placeholder')
                )
                for q in result['questions']
            ]

        return ContextGatheringResponse(
            status=result['status'],
            questions=questions,
            context=result.get('context'),
            gathered_so_far=result['gathered_so_far'],
            progress=result.get('progress'),
            summary=result.get('summary'),
            pilot_analysis_results=pilot_results
        )

    except Exception as e:
        log.error(f"Error in context gathering: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.post(
    "/api/parameter_inference/infer",
    summary="Full parameter inference pipeline"
)
def infer_parameters(
    request: ParameterInferenceRequest,
    trans: ProvidesUserContext = DependsOnTrans
) -> ParameterInferenceResponse:
    """
    Complete parameter inference pipeline.

    This is the high-level endpoint that combines:
    1. Context extraction from user query
    2. Pilot analysis on uploaded data
    3. Parameter inference using gathered context
    4. Confidence assessment

    Args:
        request: Tool ID, user query, optional data files and context

    Returns:
        Inferred parameters with confidence levels and recommendations
    """
    if not PARAMETER_INFERENCE_AVAILABLE:
        raise HTTPException(status_code=503, detail="Parameter inference not available")

    try:
        # Create context gatherer
        gatherer = ContextGatherer(
            tool_id=request.tool_id,
            enable_pilot_analysis=request.enable_pilot_analysis
        )

        # Step 1: Extract context from query
        context_result = gatherer.gather_context(request.user_query)

        # Step 2: Incorporate user-provided context
        if request.user_context:
            gatherer.gathered_context.update(request.user_context)

        # Step 3: Run pilot analysis if files provided
        pilot_results = None
        if request.input_files and request.enable_pilot_analysis:
            pilot_results = gatherer.run_pilot_analysis(request.input_files)

        # Step 4: Infer parameters from gathered context
        inferred_params = {}
        confidence = {}
        recommendations = []
        warnings = []

        for param_name in gatherer.requirements.get('parameters', {}).keys():
            value = gatherer.get_parameter_value(param_name)
            if value is not None:
                inferred_params[param_name] = value

                # Assess confidence
                param_req = gatherer.requirements['parameters'][param_name]
                context_type = param_req.get('context_type', 'unknown')

                if context_type == 'user_providable' and param_name in request.user_context:
                    confidence[param_name] = "high"  # User explicitly provided
                elif context_type == 'data_dependent' and pilot_results:
                    if param_name in pilot_results:
                        confidence[param_name] = "high"  # Extracted from data
                    else:
                        confidence[param_name] = "medium"  # Using fallback
                        warnings.append(f"Using fallback value for {param_name}")
                else:
                    confidence[param_name] = "medium"  # Inferred from context

        # Generate recommendations
        if not pilot_results and request.enable_pilot_analysis:
            recommendations.append("Consider uploading data files for more accurate parameter inference")

        if context_result.get('status') == 'need_more_context':
            recommendations.append("Some context is missing - parameters may use default values")

        return ParameterInferenceResponse(
            tool_id=request.tool_id,
            inferred_parameters=inferred_params,
            context_used=gatherer.gathered_context,
            pilot_analysis_run=pilot_results is not None,
            pilot_analysis_results=pilot_results,
            confidence=confidence,
            recommendations=recommendations,
            warnings=warnings
        )

    except Exception as e:
        log.error(f"Error in parameter inference: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=str(e))


@router.get(
    "/api/parameter_inference/health",
    summary="Check parameter inference system health"
)
def check_health(trans: ProvidesUserContext = DependsOnTrans) -> Dict[str, Any]:
    """
    Health check for parameter inference system.

    Returns:
        System status and component availability
    """
    return {
        "parameter_inference_available": PARAMETER_INFERENCE_AVAILABLE,
        "pilot_analysis_available": get_pilot_manager is not None if PARAMETER_INFERENCE_AVAILABLE else False,
        "context_gathering_available": ContextGatherer is not None if PARAMETER_INFERENCE_AVAILABLE else False,
        "status": "healthy" if PARAMETER_INFERENCE_AVAILABLE else "unavailable"
    }
