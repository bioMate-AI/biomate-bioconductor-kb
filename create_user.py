import requests
import json

BASE_URL = "http://localhost:8081"
BOOTSTRAP_KEY = "e5b2a0e7e843b203ec49ec9a5b1a2dbfab20f92e72651410f29bd7b2101467b3"

def create_user():
    headers = {"x-api-key": BOOTSTRAP_KEY, "Content-Type": "application/json"}
    payload = {
        "email": "testuser@biomate.org",
        "password": "password123",
        "username": "testuser"
    }
    
    # Try creating user
    try:
        response = requests.post(f"{BASE_URL}/api/users", headers=headers, json=payload)
        if response.status_code == 200:
            return response.json()["id"]
        # If user exists, find it?
        # Only admin can list users usually
        if response.status_code == 400 and "exists" in response.text:
             print("User exists")
             # Assuming I can't find ID easily without listing.
             # But I know ID from previous run.
             return "1cd8e2f6b131e891"
    except Exception as e:
        print(e)
    return "1cd8e2f6b131e891"

def create_api_key(user_id):
    headers = {"x-api-key": BOOTSTRAP_KEY, "Content-Type": "application/json"}
    response = requests.post(f"{BASE_URL}/api/users/{user_id}/api_key", headers=headers)
    print(f"Create API Key Response: {response.status_code}")
    print(response.text)
    if response.status_code == 200:
        return response.json()
    return None

if __name__ == "__main__":
    user_id = create_user()
    if user_id:
        print(f"User ID: {user_id}")
        key = create_api_key(user_id)
        print(f"API Key: {key}")
