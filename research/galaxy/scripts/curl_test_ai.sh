#!/bin/bash

# Simple curl test for AI Assistant API endpoints
# Make sure Galaxy is running first

BASE_URL="http://localhost:8080"
echo "🚀 Testing AI Assistant API endpoints..."
echo "Base URL: $BASE_URL"
echo ""

# Test 1: AI Assistant Status
echo "1️⃣ Testing AI Assistant Status..."
curl -s -X GET "$BASE_URL/api/ai_assistant/status" | python3 -m json.tool
echo ""
echo ""

# Test 2: Enhanced Workflow Recommendations (Quick)
echo "2️⃣ Testing Enhanced Workflow Recommendations (Quick)..."
curl -s -X POST "$BASE_URL/api/ai_assistant/enhanced_workflow_recommendations?level=quick" \
  -H "Content-Type: application/json" \
  -d '{
    "request_text": "RNA-seq differential expression analysis",
    "context": {}
  }' | python3 -m json.tool
echo ""
echo ""

# Test 3: Enhanced Workflow Recommendations (Enhanced)  
echo "3️⃣ Testing Enhanced Workflow Recommendations (Enhanced)..."
curl -s -X POST "$BASE_URL/api/ai_assistant/enhanced_workflow_recommendations?level=enhanced" \
  -H "Content-Type: application/json" \
  -d '{
    "request_text": "RNA-seq differential expression analysis", 
    "context": {}
  }' | python3 -m json.tool
echo ""
echo ""

# Test 4: Process Request (Full AI Assistant)
echo "4️⃣ Testing Full AI Assistant Process Request..."
curl -s -X POST "$BASE_URL/api/ai_assistant/process_request" \
  -H "Content-Type: application/json" \
  -d '{
    "request_text": "RNA-seq differential expression analysis",
    "context": {}
  }' | python3 -m json.tool

echo ""
echo "✅ All tests completed!"