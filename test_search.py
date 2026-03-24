
import sys
import os
import logging

# Add backend to path
sys.path.append(os.path.join(os.getcwd(), 'backend'))

# Configure logging
logging.basicConfig(level=logging.INFO)

from backend.lib.galaxy.ai.unified_workflow_search import get_workflow_search

def test_search():
    print("Initializing search...")
    search = get_workflow_search()
    print("Search initialized.")
    
    query = "rnaseq-nf"
    print(f"Searching for: {query}")
    results = search.search(query, limit=1)
    
    print(f"Found {len(results)} results")
    if results:
        print(f"Top result: {results[0].name}")
        print(f"Format: {results[0].format}")

if __name__ == "__main__":
    test_search()
