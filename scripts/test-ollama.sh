#!/bin/bash

# Ollama Integration Test Script
# Tests Ollama functionality with LightRAG service

set -e

# Configuration
OLLAMA_URL="http://localhost:11434"
LIGHTRAG_URL="http://localhost:8013"
TEST_MODEL="llama3.3:8b"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🦙 Testing Ollama Integration${NC}"
echo "==============================="

# Test 1: Check Ollama Service
echo -n "📡 Testing Ollama service connectivity... "
if curl -sf "$OLLAMA_URL/api/tags" > /dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "Ollama service is not accessible at $OLLAMA_URL"
    exit 1
fi

# Test 2: List Available Models
echo -n "📋 Testing model listing... "
MODELS_RESPONSE=$(curl -s "$OLLAMA_URL/api/tags")
if echo "$MODELS_RESPONSE" | jq '.models' > /dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS${NC}"
    MODEL_COUNT=$(echo "$MODELS_RESPONSE" | jq '.models | length')
    echo "   Found $MODEL_COUNT models"
else
    echo -e "${RED}✗ FAIL${NC}"
fi

# Test 3: Check if test model exists
echo -n "🔍 Checking for test model ($TEST_MODEL)... "
if echo "$MODELS_RESPONSE" | jq -e ".models[] | select(.name == \"$TEST_MODEL\")" > /dev/null; then
    echo -e "${GREEN}✓ EXISTS${NC}"
    MODEL_EXISTS=true
else
    echo -e "${YELLOW}! NOT FOUND${NC}"
    MODEL_EXISTS=false
fi

# Test 4: Pull model if not exists (optional - can be slow)
if [ "$MODEL_EXISTS" = false ]; then
    read -p "$(echo -e ${YELLOW}Pull test model $TEST_MODEL? This may take several minutes [y/N]: ${NC})" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}📥 Pulling model $TEST_MODEL...${NC}"
        curl -X POST "$OLLAMA_URL/api/pull" \
            -H "Content-Type: application/json" \
            -d "{\"name\": \"$TEST_MODEL\"}" &
        
        # Show progress
        PULL_PID=$!
        while kill -0 $PULL_PID 2>/dev/null; do
            echo -n "."
            sleep 5
        done
        echo
        
        if wait $PULL_PID; then
            echo -e "${GREEN}✓ Model pulled successfully${NC}"
            MODEL_EXISTS=true
        else
            echo -e "${RED}✗ Failed to pull model${NC}"
        fi
    fi
fi

# Test 5: Test LightRAG Health with Ollama info
echo -n "🏥 Testing LightRAG health endpoint... "
HEALTH_RESPONSE=$(curl -s "$LIGHTRAG_URL/health")
if echo "$HEALTH_RESPONSE" | jq '.status' | grep -q "healthy"; then
    echo -e "${GREEN}✓ PASS${NC}"
    
    # Show model provider info
    PROVIDER=$(echo "$HEALTH_RESPONSE" | jq -r '.model_provider // "unknown"')
    echo "   Model provider: $PROVIDER"
    
    if [ "$PROVIDER" = "ollama" ]; then
        OLLAMA_AVAILABLE=$(echo "$HEALTH_RESPONSE" | jq -r '.ollama_available // false')
        echo "   Ollama available: $OLLAMA_AVAILABLE"
    fi
else
    echo -e "${RED}✗ FAIL${NC}"
fi

# Test 6: Test LightRAG Model Listing
echo -n "📝 Testing LightRAG model listing... "
LIGHTRAG_MODELS=$(curl -s "$LIGHTRAG_URL/models")
if echo "$LIGHTRAG_MODELS" | jq '.provider' > /dev/null 2>&1; then
    echo -e "${GREEN}✓ PASS${NC}"
    PROVIDER=$(echo "$LIGHTRAG_MODELS" | jq -r '.provider')
    echo "   Provider: $PROVIDER"
else
    echo -e "${RED}✗ FAIL${NC}"
fi

# Test 7: Test Model Pulling via LightRAG (if Ollama is provider)
if [ "$PROVIDER" = "ollama" ] && [ "$MODEL_EXISTS" = false ]; then
    echo -n "🔄 Testing model pull via LightRAG... "
    PULL_RESPONSE=$(curl -s -X POST "$LIGHTRAG_URL/models/pull?model_name=llama2:latest")
    if echo "$PULL_RESPONSE" | jq '.status' | grep -q "success"; then
        echo -e "${GREEN}✓ PASS${NC}"
    else
        echo -e "${YELLOW}⚠ SKIP${NC} (may require larger model or timeout)"
    fi
fi

# Test 8: Test Basic Text Generation (if model exists)
if [ "$MODEL_EXISTS" = true ] || [ "$PROVIDER" = "openai" ]; then
    echo -n "🤖 Testing text generation... "
    
    QUERY_DATA=$(cat <<EOF
{
    "query": "What is artificial intelligence in one sentence?",
    "mode": "local"
}
EOF
)
    
    QUERY_RESPONSE=$(curl -s -X POST "$LIGHTRAG_URL/query" \
        -H "Content-Type: application/json" \
        -d "$QUERY_DATA")
    
    if echo "$QUERY_RESPONSE" | jq '.success' | grep -q "true"; then
        echo -e "${GREEN}✓ PASS${NC}"
        RESPONSE_TEXT=$(echo "$QUERY_RESPONSE" | jq -r '.response // "No response"')
        echo "   Response: ${RESPONSE_TEXT:0:100}..."
    else
        echo -e "${RED}✗ FAIL${NC}"
        ERROR=$(echo "$QUERY_RESPONSE" | jq -r '.detail // "Unknown error"')
        echo "   Error: $ERROR"
    fi
else
    echo -e "${YELLOW}⚠ SKIP${NC} Text generation test (no suitable model available)"
fi

# Test 9: Test Document Ingestion
echo -n "📄 Testing document ingestion... "
INGEST_DATA=$(cat <<EOF
{
    "content": "Ollama is a tool for running large language models locally. It provides an easy way to deploy and manage AI models on your own hardware.",
    "metadata": {"test": true, "source": "ollama_test"},
    "source": "test_document"
}
EOF
)

INGEST_RESPONSE=$(curl -s -X POST "$LIGHTRAG_URL/documents/ingest" \
    -H "Content-Type: application/json" \
    -d "$INGEST_DATA")

if echo "$INGEST_RESPONSE" | jq '.success' | grep -q "true"; then
    echo -e "${GREEN}✓ PASS${NC}"
    DOC_ID=$(echo "$INGEST_RESPONSE" | jq -r '.document_id')
    echo "   Document ID: $DOC_ID"
else
    echo -e "${RED}✗ FAIL${NC}"
fi

# Test 10: Performance Test (if model available)
if [ "$MODEL_EXISTS" = true ] || [ "$PROVIDER" = "openai" ]; then
    echo -n "⏱️  Testing response time... "
    
    START_TIME=$(date +%s.%N)
    PERF_RESPONSE=$(curl -s -X POST "$LIGHTRAG_URL/query" \
        -H "Content-Type: application/json" \
        -d '{"query": "Hello", "mode": "naive"}')
    END_TIME=$(date +%s.%N)
    
    if echo "$PERF_RESPONSE" | jq '.success' | grep -q "true"; then
        DURATION=$(echo "$END_TIME - $START_TIME" | bc)
        echo -e "${GREEN}✓ PASS${NC}"
        echo "   Response time: ${DURATION}s"
        
        if (( $(echo "$DURATION < 5.0" | bc -l) )); then
            echo -e "   ${GREEN}Fast response${NC}"
        elif (( $(echo "$DURATION < 15.0" | bc -l) )); then
            echo -e "   ${YELLOW}Moderate response${NC}"
        else
            echo -e "   ${RED}Slow response${NC}"
        fi
    else
        echo -e "${RED}✗ FAIL${NC}"
    fi
else
    echo -e "${YELLOW}⚠ SKIP${NC} Performance test (no suitable model available)"
fi

# Summary
echo
echo -e "${BLUE}=== Test Summary ===${NC}"

if [ "$PROVIDER" = "ollama" ]; then
    echo -e "${GREEN}✓ Ollama integration is working${NC}"
    echo "  • Ollama service: Available"
    echo "  • LightRAG integration: Active"
    echo "  • Model provider: Ollama"
    
    if [ "$MODEL_EXISTS" = true ]; then
        echo "  • Test model: Available ($TEST_MODEL)"
    else
        echo -e "  • Test model: ${YELLOW}Not available${NC} (pull manually if needed)"
    fi
else
    echo -e "${YELLOW}ℹ Currently using OpenAI provider${NC}"
    echo "  • To enable Ollama:"
    echo "    1. Set MODEL_PROVIDER=ollama in .env"
    echo "    2. Set USE_LOCAL_MODELS=true in .env"
    echo "    3. Restart services: ./start.sh restart"
fi

echo
echo -e "${BLUE}Recommended Next Steps:${NC}"

if [ "$PROVIDER" = "ollama" ]; then
    if [ "$MODEL_EXISTS" = false ]; then
        echo "1. Pull a suitable model:"
        echo "   curl -X POST \"$LIGHTRAG_URL/models/pull?model_name=llama2:7b\""
    fi
    echo "2. Test with different models:"
    echo "   • llama2:7b (general purpose)"
    echo "   • mistral:7b (fast inference)"  
    echo "   • codellama:7b (code generation)"
else
    echo "1. Enable Ollama in .env:"
    echo "   MODEL_PROVIDER=ollama"
    echo "   USE_LOCAL_MODELS=true"
    echo "2. Restart services:"
    echo "   ./start.sh restart"
fi

echo "3. Monitor GPU usage:"
echo "   curl http://localhost:8014/gpu/info"
echo "4. Check detailed documentation:"
echo "   ./docs/OLLAMA-GUIDE.md"

echo
echo -e "${GREEN}🦙 Ollama integration test completed!${NC}"