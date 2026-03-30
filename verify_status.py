import requests
import time
import sys
import json

BASE_URL = "http://localhost:8081"
INVOCATION_ID = "48" # Use the ID from previous run

def check_status():
    print(f"Checking status for Invocation {INVOCATION_ID}...")
    
    url = f"{BASE_URL}/api/invocations/{INVOCATION_ID}/status"
    
    try:
        response = requests.get(url)
        print(f"Response Status: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print(json.dumps(data, indent=2))
            
            state = data.get('state')
            steps = data.get('steps', [])
            print(f"\n✅ State: {state}")
            print(f"✅ Steps: {len(steps)}")
            return True
        else:
            print(f"❌ Status check failed: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ Exception: {e}")
        return False

if __name__ == "__main__":
    check_status()
