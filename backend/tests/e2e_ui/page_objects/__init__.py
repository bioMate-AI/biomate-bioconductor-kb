"""
Page Objects for BioMate E2E Testing

This package contains page object classes that encapsulate UI interactions
for the BioMate application, following the Page Object Model pattern.
"""

from .chat_page import ChatPage
from .workflow_page import WorkflowPage
from .execution_page import (
    ExecutionPage,
    ParameterDialog,
    ExecutionTimeline,
    JobLogViewer,
)

__all__ = [
    'ChatPage',
    'WorkflowPage',
    'ExecutionPage',
    'ParameterDialog',
    'ExecutionTimeline',
    'JobLogViewer',
]
