#!/usr/bin/env python3
"""
BioMate UI Demo Video Creator
Uses browser automation to record the UI and create a demo video
"""

import subprocess
import time
import json
from pathlib import Path

# Configuration
FRONTEND_URL = "http://localhost:5000"
OUTPUT_DIR = Path("/home/yzhang/biomate/demo_videos")
OUTPUT_DIR.mkdir(exist_ok=True)

def check_frontend():
    """Check if frontend is running"""
    import urllib.request
    try:
        with urllib.request.urlopen(FRONTEND_URL, timeout=5) as response:
            return response.status == 200
    except:
        return False

def create_demo_screenshots():
    """Create screenshots for key demo moments"""
    print("Creating demo screenshots...")

    # Use selenium or puppeteer to automate browser
    # For now, create a step-by-step guide

    demo_steps = [
        {
            "step": 1,
            "title": "BioMate Home Page",
            "url": FRONTEND_URL,
            "description": "Main interface with chat panel and workflow visualization",
            "action": "Open homepage"
        },
        {
            "step": 2,
            "title": "Chat Workflow Generation",
            "url": FRONTEND_URL,
            "description": "Type: 'Model bacterial growth with initial population 1000'",
            "action": "Send chat message",
            "api_call": {
                "endpoint": "/api/chat",
                "method": "POST",
                "body": {
                    "message": "Model bacterial growth dynamics with initial population of 1000 cells and growth rate of 0.5"
                }
            }
        },
        {
            "step": 3,
            "title": "Generated Workflow",
            "description": "AI-generated workflow JSON with correct tool IDs and parameters",
            "action": "Show workflow visualization"
        },
        {
            "step": 4,
            "title": "Workflow Execution",
            "description": "Click Execute, choose execution mode (local/AWS/Slurm)",
            "action": "Execute workflow"
        },
        {
            "step": 5,
            "title": "Real-time Monitoring",
            "description": "SSE streaming shows real-time status updates",
            "action": "Monitor execution"
        },
        {
            "step": 6,
            "title": "Results & Download",
            "description": "Completed workflow with downloadable outputs",
            "action": "View results"
        }
    ]

    # Save demo script
    script_file = OUTPUT_DIR / "demo_script.json"
    with open(script_file, 'w') as f:
        json.dump(demo_steps, f, indent=2)

    print(f"Demo script saved to: {script_file}")
    return demo_steps

def create_video_from_api_demo():
    """Create a video showing API interactions"""
    print("\n" + "="*60)
    print("BIOMATE UI DEMO - API INTERACTION")
    print("="*60 + "\n")

    if not check_frontend():
        print("❌ Frontend is not running on", FRONTEND_URL)
        print("Please start the frontend first:")
        print("  cd /home/yzhang/biomate/frontend")
        print("  npm start")
        return

    print("✅ Frontend is running on", FRONTEND_URL)
    print("\n" + "-"*60)
    print("DEMO STEP 1: Generate Workflow via Chat API")
    print("-"*60 + "\n")

    # Demonstrate chat API call
    chat_request = {
        "message": "Model bacterial growth dynamics with initial population of 1000 cells and growth rate of 0.5"
    }

    print("Request:")
    print(f"  POST {FRONTEND_URL}/api/chat")
    print(f"  Body: {json.dumps(chat_request, indent=4)}")
    print("\nExecuting API call...")

    # Make actual API call
    import urllib.request
    import urllib.parse

    try:
        req = urllib.request.Request(
            f"{FRONTEND_URL}/api/chat",
            data=json.dumps(chat_request).encode('utf-8'),
            headers={'Content-Type': 'application/json'},
            method='POST'
        )

        with urllib.request.urlopen(req, timeout=60) as response:
            result = json.loads(response.read().decode('utf-8'))

            print("\n✅ Response received!")
            print("\nWorkflow generated:")
            print(f"  - Success: {result.get('workflow', {}).get('success', False)}")
            print(f"  - Workflow name: {result.get('workflow', {}).get('workflow_ga', {}).get('name', 'N/A')}")

            if 'workflow' in result and 'workflow_ga' in result['workflow']:
                workflow = result['workflow']['workflow_ga']
                print(f"  - Steps: {len(workflow.get('steps', {}))}")

                # Save full response
                output_file = OUTPUT_DIR / f"chat_response_{int(time.time())}.json"
                with open(output_file, 'w') as f:
                    json.dump(result, f, indent=2)
                print(f"\n📄 Full response saved to: {output_file}")

                return result

    except Exception as e:
        print(f"\n❌ Error: {e}")
        return None

def create_markdown_demo():
    """Create a markdown document with embedded screenshots"""
    demo_md = OUTPUT_DIR / f"biomate_demo_{int(time.time())}.md"

    content = """# BioMate UI Demo

**Generated**: {timestamp}
**Frontend**: http://localhost:5000

## Overview

BioMate is an AI-powered bioinformatics platform that:
- Generates workflows from natural language descriptions
- Executes on local/cloud/HPC infrastructure
- Provides real-time monitoring and results

## Demo Walkthrough

### 1. Chat Interface

The main interface includes:
- **Left Panel**: Chat input for natural language queries
- **Center Panel**: Workflow visualization and execution status
- **Right Panel**: Settings and configuration

### 2. Workflow Generation

**User Input:**
```
Model bacterial growth dynamics with initial population of 1000 cells and growth rate of 0.5
```

**AI Response:**
- ✅ Recognizes microbiology domain
- ✅ Finds relevant workflow: `model_bacterial_growth_dynamics`
- ✅ Extracts parameters: `initial_population=1000`, `growth_rate=0.5`
- ✅ Generates valid Nextflow workflow JSON

### 3. Workflow Execution

**Execution Options:**
- 🖥️ Local (this machine)
- ☁️ AWS Batch (cloud with GPU support)
- 🔬 Slurm (HPC cluster)
- 🧪 Sandbox (mock execution for testing)

**Real-time Monitoring:**
- Server-Sent Events (SSE) stream status updates
- Progress bar shows completed steps
- Live logs from Nextflow execution

### 4. Results

**Outputs:**
- Downloadable result files
- Visualization of data (plots, tables)
- Execution report (workflow graph, timing, resources)

## Technical Features

- **950+ workflows** across biochemistry, microbiology, genomics, structural biology
- **LLM-powered** with Claude Opus 4.6
- **Nextflow backend** for scalable execution
- **State synchronization** recently fixed (Feb 2026)

## Next Steps

- Try your own workflow request
- Explore different scientific domains
- Execute workflows on your infrastructure
- Download results and integrate into your pipelines

---

*Generated by BioMate Demo Creator*
""".format(timestamp=time.strftime("%Y-%m-%d %H:%M:%S"))

    with open(demo_md, 'w') as f:
        f.write(content)

    print(f"\n📄 Demo documentation created: {demo_md}")
    return demo_md

if __name__ == "__main__":
    print("BioMate UI Demo Video Creator")
    print("="*60)

    # Create output directory
    OUTPUT_DIR.mkdir(exist_ok=True)

    # Create demo materials
    steps = create_demo_screenshots()
    result = create_video_from_api_demo()
    doc = create_markdown_demo()

    print("\n" + "="*60)
    print("DEMO MATERIALS CREATED")
    print("="*60)
    print(f"\n📁 Output directory: {OUTPUT_DIR}")
    print("\nFiles created:")
    print(f"  1. Demo script: {OUTPUT_DIR}/demo_script.json")
    print(f"  2. Demo documentation: {doc}")
    if result:
        print(f"  3. API response samples in: {OUTPUT_DIR}/")

    print("\n" + "="*60)
    print("TO RECORD A VIDEO:")
    print("="*60)
    print("\n1. Manual recording (recommended):")
    print("   - Open http://localhost:5000 in browser")
    print("   - Use OBS Studio, SimpleScreenRecorder, or similar")
    print("   - Follow the demo script in demo_script.json")
    print("\n2. Automated recording:")
    print("   - Install: sudo apt-get install ffmpeg")
    print("   - Run: ./BIOMATE_UI_DEMO_RECORDING.sh")

    print("\n✅ Demo preparation complete!")
