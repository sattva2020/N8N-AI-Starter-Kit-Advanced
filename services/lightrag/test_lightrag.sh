#!/bin/bash

# LightRAG Service Test Script
# This script tests the LightRAG service functionality

set -e

# Configuration
LIGHTRAG_URL="http://localhost:8003"
TEST_DOCUMENT="LightRAG is a graph-based retrieval augmented generation system that automatically extracts entities and relationships from documents. It provides multiple query modes including naive, local, global, and hybrid approaches for intelligent question answering."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo "🧪 Testing LightRAG Service"
echo "================================"

# Test 1: Health Check
echo -n "📊 Testing health endpoint... "
if curl -sf "$LIGHTRAG_URL/health" > /dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "LightRAG service is not accessible at $LIGHTRAG_URL"
    exit 1
fi

# Test 2: Service Stats
echo -n "📈 Testing stats endpoint... "
if curl -sf "$LIGHTRAG_URL/stats" > /dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
fi

# Test 3: Document Ingestion
echo -n "📄 Testing document ingestion... "
INGEST_RESPONSE=$(curl -s -X POST "$LIGHTRAG_URL/documents/ingest" \
    -H "Content-Type: application/json" \
    -d "{
        \"content\": \"$TEST_DOCUMENT\",
        \"metadata\": {\"test\": \"true\"},
        \"source\": \"test_script\"
    }")

if echo "$INGEST_RESPONSE" | grep -q '"success":true'; then
    echo -e "${GREEN}✓ PASS${NC}"
    DOCUMENT_ID=$(echo "$INGEST_RESPONSE" | grep -o '"document_id":"[^"]*"' | cut -d'"' -f4)
    echo "  📝 Document ID: $DOCUMENT_ID"
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "  Response: $INGEST_RESPONSE"
fi

# Test 4: Knowledge Graph Query (Naive Mode)
echo -n "🔍 Testing naive query... "
QUERY_RESPONSE=$(curl -s -X POST "$LIGHTRAG_URL/query" \
    -H "Content-Type: application/json" \
    -d '{
        "query": "What is LightRAG?",
        "mode": "naive"
    }')

if echo "$QUERY_RESPONSE" | grep -q '"success":true'; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "  Response: $QUERY_RESPONSE"
fi

# Test 5: Knowledge Graph Query (Hybrid Mode)
echo -n "🔗 Testing hybrid query... "
HYBRID_RESPONSE=$(curl -s -X POST "$LIGHTRAG_URL/query" \
    -H "Content-Type: application/json" \
    -d '{
        "query": "How does LightRAG work?",
        "mode": "hybrid"
    }')

if echo "$HYBRID_RESPONSE" | grep -q '"success":true'; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
    echo "  Response: $HYBRID_RESPONSE"
fi

# Test 6: List Documents
echo -n "📋 Testing document listing... "
if curl -sf "$LIGHTRAG_URL/documents" > /dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
fi

# Test 7: File Upload (if test file exists)
if [ -f "test_document.txt" ]; then
    echo -n "📁 Testing file upload... "
    UPLOAD_RESPONSE=$(curl -s -X POST "$LIGHTRAG_URL/documents/ingest-file" \
        -F "file=@test_document.txt")
    
    if echo "$UPLOAD_RESPONSE" | grep -q '"success":true'; then
        echo -e "${GREEN}✓ PASS${NC}"
    else
        echo -e "${RED}✗ FAIL${NC}"
        echo "  Response: $UPLOAD_RESPONSE"
    fi
else
    echo -e "${YELLOW}⚠ SKIP${NC} File upload test (test_document.txt not found)"
fi

# Test 8: Metrics Endpoint
echo -n "📊 Testing metrics endpoint... "
if curl -sf "$LIGHTRAG_URL/metrics" > /dev/null; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC}"
fi

echo ""
echo "🎉 Testing complete!"
echo ""

# Show some statistics
echo "📊 Service Statistics:"
curl -s "$LIGHTRAG_URL/stats" | python3 -m json.tool 2>/dev/null || echo "Failed to retrieve stats"

echo ""
echo "💡 Usage Examples:"
echo ""
echo "# Ingest a document"
echo "curl -X POST '$LIGHTRAG_URL/documents/ingest' \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"content\": \"Your document content here...\"}'"
echo ""
echo "# Query the knowledge graph"
echo "curl -X POST '$LIGHTRAG_URL/query' \\"
echo "  -H 'Content-Type: application/json' \\"
echo "  -d '{\"query\": \"Your question here?\", \"mode\": \"hybrid\"}'"
echo ""
echo "# Upload a file"
echo "curl -X POST '$LIGHTRAG_URL/documents/ingest-file' \\"
echo "  -F 'file=@your_document.txt'"