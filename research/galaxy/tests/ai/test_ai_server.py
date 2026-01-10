#!/usr/bin/env python3

"""
Simple test server for AI Assistant functionality
"""

import sys
import json
import asyncio
from typing import Dict, Any

# Add the lib path
sys.path.insert(0, '/Users/renyuankai/work/biometa/galaxy/lib')

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn

app = FastAPI(title="Galaxy AI Assistant Test Server")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Request models
class AIRequestModel(BaseModel):
    request_text: str
    context: Dict[str, Any] = {}

# Global RAG generator
_rag_generator = None

def get_rag_generator():
    global _rag_generator
    if _rag_generator is None:
        try:
            from galaxy.ai.rag_workflow_generator import RAGWorkflowGenerator
            from galaxy.ai.config import DEFAULT_AI_CONFIG
            
            data_path = 'lib/galaxy/ai/data/workflows'
            _rag_generator = RAGWorkflowGenerator(DEFAULT_AI_CONFIG, data_path)
            print(f"✅ RAG generator initialized with {len(_rag_generator.workflow_data.workflows)} workflows")
        except Exception as e:
            print(f"❌ Failed to initialize RAG generator: {e}")
            raise
    return _rag_generator

@app.get("/")
async def root():
    return {"message": "Galaxy AI Assistant Test Server", "status": "running"}

@app.post("/api/ai_assistant/enhanced_workflow_recommendations")
async def enhanced_workflow_recommendations(
    request: AIRequestModel,
    level: str = "quick"
):
    """Test the enhanced workflow recommendations."""
    
    try:
        from galaxy.ai.types import UserRequest
        
        rag_generator = get_rag_generator()
        
        user_request = UserRequest(
            user_id="test_user",
            request_text=request.request_text,
            context=request.context
        )
        
        if level == "quick":
            # Quick recommendations
            recommendations = rag_generator.get_workflow_recommendations(user_request, limit=5)
            
            return {
                "status": "success",
                "recommendations": recommendations,
                "total_options": len(recommendations),
                "method": "RAG-based (using 951 crawled workflows)"
            }
        
        elif level == "enhanced":
            # Enhanced generation
            result = rag_generator.generate_workflow(user_request)
            
            if result.get('success', False):
                workflow_data = result.get("workflow", {})
                
                workflow_response = {
                    "name": workflow_data.get("name", "Generated Workflow"),
                    "description": workflow_data.get("description", ""),
                    "steps": workflow_data.get("steps", []),
                    "step_count": len(workflow_data.get("steps", [])),
                    "inputs": workflow_data.get("inputs", []),
                    "outputs": workflow_data.get("outputs", []),
                    "tags": workflow_data.get("tags", []),
                    "tools": []
                }
                
                # Extract tool list from steps
                for step in workflow_data.get("steps", []):
                    if step.get("tool_id"):
                        tool_name = step["tool_id"]
                        if "/" in tool_name:
                            tool_name = tool_name.split("/")[-1]
                        if tool_name not in workflow_response["tools"]:
                            workflow_response["tools"].append(tool_name)
                
                return {
                    "status": "success",
                    "workflow": workflow_response,
                    "confidence": result.get("confidence", 0),
                    "method": "RAG Enhanced Generation",
                    "similar_workflows_count": result.get("similar_workflows_count", 0)
                }
            else:
                return {
                    "status": "error",
                    "error": result.get("error", "Generation failed")
                }
        
    except Exception as e:
        return {
            "status": "error",
            "error": str(e)
        }

@app.get("/api/ai_assistant/status")
async def ai_status():
    """Get AI Assistant status."""
    try:
        rag_generator = get_rag_generator()
        return {
            "available": True,
            "ready": True,
            "rag_available": True,
            "workflows_loaded": len(rag_generator.workflow_data.workflows),
            "embeddings_count": len(rag_generator.embeddings)
        }
    except Exception as e:
        return {
            "available": False,
            "ready": False,
            "error": str(e)
        }

if __name__ == "__main__":
    print("🚀 Starting Galaxy AI Assistant Test Server...")
    print("📊 This will test the fixed RAG functionality")
    print("🌐 Server will be available at: http://localhost:8000")
    print("📝 Try these endpoints:")
    print("   - GET  /api/ai_assistant/status")
    print("   - POST /api/ai_assistant/enhanced_workflow_recommendations?level=quick")
    print("   - POST /api/ai_assistant/enhanced_workflow_recommendations?level=enhanced")
    print()
    
    uvicorn.run(app, host="0.0.0.0", port=8000)