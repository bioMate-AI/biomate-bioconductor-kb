import requests
import json
import time
import sys

BASE_URL = "http://localhost:8081"
API_KEY = "fake_key"  # Galaxy often allows no auth for localhost/dev if configured, or I need a real key.
# For now, let's assume I can hit the endpoint or I'll need to get a key.
# Actually, the user script `verify_nextflow_api.ts` used no auth for `/api/chat` but `/api/workflows/execute` might need it.
# Let's try to get a user API key if possible, or just try without.

def run_execution_test():
    print(f"Testing execution against {BASE_URL}...")
    
    # 1. Create a dummy execution request
    # This matches the NextflowExecutionRequest model in `nextflow_executor_v2.py`
    payload = {
        "workflow_name": "microbiology/count_bacterial_colonies",
        "parameters": {
            "image_dir": "data/images/*.jpg",
            "threshold": 0.5
        },
        "profile": "test",
        "enable_input_validation": False
    }
    
    try:
        response = requests.post(
            f"{BASE_URL}/api/nextflow/execute",
            json=payload,
            headers={"Content-Type": "application/json"}
        )
        
        print(f"Response Status: {response.status_code}")
        print(f"Response Body: {response.text}")
        
        if response.status_code == 200:
            data = response.json()
            if data.get('success'):
                print("✅ Execution started successfully!")
                print(f"Invocation ID: {data.get('invocation_id')}")
                return True
            else:
                print("❌ Execution failed (API returned success=False)")
                return False
        else:
            print("❌ Request failed")
            return False
            
    except Exception as e:
        print(f"❌ Exception: {e}")
        return False

if __name__ == "__main__":
    success = run_execution_test()
    sys.exit(0 if success else 1)
