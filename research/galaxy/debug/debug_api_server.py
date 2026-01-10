#!/usr/bin/env python3
"""
独立的API调试服务器 - 用于调试AI助手API端点
"""

import os
import sys
from typing import Dict, Any

# 添加lib目录到Python路径
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lib'))

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import uvicorn

# 初始化FastAPI应用
app = FastAPI(title="Galaxy AI Assistant Debug API", version="1.0.0")

class AIRequestModel(BaseModel):
    request_text: str
    context: Dict[str, Any] = {}

@app.get("/")
async def root():
    return {"message": "Galaxy AI Assistant Debug Server", "status": "running"}

@app.post("/debug/rag_generation")
async def debug_rag_generation(request: AIRequestModel):
    """调试RAG工作流生成"""
    try:
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        from galaxy.ai.rag_workflow_generator import RAGWorkflowGenerator
        from galaxy.ai.types import UserRequest
        
        # 在这里设置断点进行调试
        crawler_data_path = "lib/galaxy/ai/data/workflows"
        rag_generator = RAGWorkflowGenerator(DEFAULT_AI_CONFIG, crawler_data_path)
        
        user_request = UserRequest(
            user_id="debug_user",
            request_text=request.request_text,
            context=request.context
        )
        
        # 这里是调试的核心逻辑
        result = rag_generator.generate_workflow(user_request)
        
        return {
            "status": "success" if result.get('success') else "failed",
            "result": result,
            "debug_info": {
                "request_text": request.request_text,
                "context": request.context
            }
        }
        
    except Exception as e:
        import traceback
        return {
            "status": "error",
            "error": str(e),
            "traceback": traceback.format_exc()
        }

@app.post("/debug/workflow_search")
async def debug_workflow_search(request: AIRequestModel):
    """调试工作流搜索"""
    try:
        from galaxy.ai.rag_workflow_loader import RAGWorkflowRecommender
        
        # 在这里设置断点
        crawler_data_path = "lib/galaxy/ai/data/workflows"
        recommender = RAGWorkflowRecommender(crawler_data_path)
        
        results = recommender.get_workflow_recommendations(
            request.request_text, 
            max_recommendations=5
        )
        
        return {
            "status": "success",
            "results": results,
            "debug_info": {
                "query": request.request_text,
                "found_count": len(results.get('recommendations', []))
            }
        }
        
    except Exception as e:
        import traceback
        return {
            "status": "error",
            "error": str(e),
            "traceback": traceback.format_exc()
        }

@app.post("/debug/ai_assistant")
async def debug_ai_assistant(request: AIRequestModel):
    """调试完整的AI助手流程"""
    try:
        from galaxy.ai.ai_assistant import AIAssistant
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        from galaxy.ai.types import UserRequest
        
        # 初始化AI助手
        crawler_data_path = "lib/galaxy/ai/data/workflows"
        assistant = AIAssistant(
            config=DEFAULT_AI_CONFIG,
            galaxy_app=None,
            crawler_data_path=crawler_data_path
        )
        
        user_request = UserRequest(
            user_id="debug_user",
            request_text=request.request_text,
            context=request.context
        )
        
        # 在这里设置断点调试整个流程
        if assistant.rag_workflow_generator:
            result = assistant.rag_workflow_generator.generate_workflow(user_request)
        else:
            result = {"success": False, "error": "RAG generator not available"}
        
        return {
            "status": "success",
            "assistant_initialized": assistant is not None,
            "rag_available": assistant.rag_workflow_generator is not None,
            "result": result
        }
        
    except Exception as e:
        import traceback
        return {
            "status": "error",
            "error": str(e),
            "traceback": traceback.format_exc()
        }

if __name__ == "__main__":
    print("🚀 Starting Galaxy AI Debug Server...")
    print("📍 Server will be available at: http://localhost:8081")
    print("📖 API docs at: http://localhost:8081/docs")
    
    uvicorn.run(
        "debug_api_server:app",
        host="localhost",
        port=8081,
        reload=True,
        log_level="info"
    )