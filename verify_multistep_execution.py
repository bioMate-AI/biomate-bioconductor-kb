import requests
import json
import time
import sys

# Configuration
BASE_URL = "http://localhost:8081"
API_KEY = "8e446449b441a6dbb72ba88c51db02df"  # Adjust if your instance requires a real key
HEADERS = {
    "x-api-key": API_KEY,
    "Content-Type": "application/json"
}

def run_multistep_workflow():
    print("Step 1: Submitting multistep workflow execution...")
    
    payload = {
        "workflow_name": "biomni/test_multistep",
        "parameters": {},
        "entry_point": "STEP_1" 
    }
    
    try:
        response = requests.post(f"{BASE_URL}/api/nextflow/execute", json=payload, headers=HEADERS)
        
        if response.status_code == 200:
            data = response.json()
            print("\n✅ Execution Submitted Successfully!")
            print(json.dumps(data, indent=2))
            
            invocation_id = data.get("invocation_id")
            if not invocation_id:
                print("❌ No invocation_id returned!")
                return
                
            poll_status(invocation_id)
            
        else:
            print(f"\n❌ Submission Failed: {response.status_code}")
            print(response.text)
            
    except Exception as e:
        print(f"\n❌ Error: {str(e)}")

def poll_status(invocation_id):
    print(f"\nStep 2: Polling status for Invocation ID: {invocation_id}...")
    
    start_time = time.time()
    last_status = None
    
    while time.time() - start_time < 60:  # Poll for up to 60 seconds
        try:
            response = requests.get(f"{BASE_URL}/api/invocations/{invocation_id}", headers=HEADERS)
            
            if response.status_code == 200:
                data = response.json()
                status = data.get("state")
                steps = data.get("steps", [])
                
                # Print status update if changed
                if status != last_status:
                    print(f"[{time.strftime('%H:%M:%S')}] Status: {status}")
                    last_status = status
                
                # Check steps progress
                completed_steps = [s for s in steps if s.get('state') == 'ok']
                running_steps = [s for s in steps if s.get('state') == 'running']
                
                sys.stdout.write(f"\rSteps: {len(completed_steps)}/{len(steps)} completed, {len(running_steps)} running... ")
                sys.stdout.flush()
                
                if status in ["scheduled", "ok", "error"]:
                    if status == "ok":
                        print(f"\n✅ Workflow Completed Successfully!")
                        break
                    elif status == "error":
                        print(f"\n❌ Workflow Failed!")
                        break
                
            elif response.status_code == 404:
                print(f"\n⚠️ Invocation not found yet (might be pending commit)...")
            else:
                print(f"\n⚠️ Status check failed: {response.status_code}")
                print(response.text)
                
        except Exception as e:
            print(f"\n⚠️ Polling error: {str(e)}")
            
        time.sleep(2)
    
    if time.time() - start_time >= 60:
        print("\n⏱️ Polling timed out!")

if __name__ == "__main__":
    run_multistep_workflow()
