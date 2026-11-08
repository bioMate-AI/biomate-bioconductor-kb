"""Knowledge endpoint used by the main BioMate assistant's query_knowledge tool."""
import os
import sqlite3
from pathlib import Path
from fastapi import HTTPException
from pydantic import BaseModel, Field
from galaxy.webapps.galaxy.api import Router
from galaxy.ai.local_knowledge_query import query_knowledge

router = Router(tags=['knowledge'])


class KnowledgeQuery(BaseModel):
    query: str = Field(min_length=1, max_length=500)
    domain: str = Field(default='general', max_length=100)
    limit: int = Field(default=5, ge=1, le=10)


@router.post('/api/knowledge/query', summary='Retrieve local BioMate tool and workflow evidence')
def knowledge_query(request: KnowledgeQuery):
    default = Path(__file__).resolve().parents[5] / 'database' / 'galaxy_ai_tools.db'
    path = os.environ.get('BIOMATE_KNOWLEDGE_DB', str(default))
    try:
        return {**query_knowledge(path, request.query, request.limit), 'query': request.query, 'domain': request.domain}
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except sqlite3.Error as exc:
        raise HTTPException(status_code=503, detail='Local knowledge catalogue is unavailable') from exc
