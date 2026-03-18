# BioMate UI Demo Guide

**Date**: February 19, 2026
**Purpose**: Demonstrate BioMate's AI-powered workflow generation and execution capabilities
**Frontend URL**: http://localhost:5000

---

## Demo Overview

BioMate is an AI-powered bioinformatics platform that allows researchers to:
1. **Chat with AI** to describe their analysis needs in natural language
2. **Auto-generate workflows** from 950+ validated scientific workflows
3. **Execute workflows** on local or cloud infrastructure (AWS Batch, Slurm)
4. **Monitor execution** in real-time with SSE streaming
5. **Download results** and visualize outputs

---

## Demo Script (10-15 minutes)

### Part 1: Introduction (2 min)

**What to show:**
- Open http://localhost:5000 in browser
- Highlight key UI components:
  - Chat interface (left panel)
  - Workflow visualization (center/right panel)
  - Execution status panel (bottom/right)
  - Settings and configuration (top right)

**What to say:**
> "BioMate combines conversational AI with 950+ pre-validated scientific workflows. Instead of manually building pipelines, researchers describe what they need, and BioMate generates, validates, and executes the workflow automatically."

---

### Part 2: Natural Language Workflow Generation (5 min)

**Demo 1: Simple Microbiological Analysis**

1. **Type in chat:**
   ```
   Model bacterial growth dynamics with an initial population of 1000 cells and growth rate of 0.5
   ```

2. **Point out what happens:**
   - ✅ AI recognizes intent: "microbiology workflow"
   - ✅ Searches 950+ workflows and ranks relevant tools
   - ✅ Auto-generates workflow JSON with correct parameters
   - ✅ Shows workflow graph visualization
   - ✅ Displays estimated execution time and resource requirements

3. **Highlight key features:**
   - **Intent Classification**: AI understands domain (microbiology)
   - **Tool Ranking**: Finds `model_bacterial_growth_dynamics` from database
   - **Parameter Inference**: Extracts `initial_population: 1000`, `growth_rate: 0.5`
   - **Workflow Validation**: Ensures tool IDs and parameters are correct

**Demo 2: Complex Biochemistry Analysis**

1. **Type in chat:**
   ```
   Analyze enzyme kinetics with Michaelis-Menten model using substrate concentrations from 0.1 to 10 mM
   ```

2. **Point out:**
   - AI generates multi-step workflow
   - Shows parameter ranges and validation
   - Displays expected outputs (plots, kinetic constants)

---

### Part 3: Workflow Execution (5 min)

**Show execution flow:**

1. **Click "Execute Workflow" button**
   - Choose execution mode:
     - 🖥️ **Local**: Run on this machine
     - ☁️ **AWS Batch**: Run on cloud (GPU support)
     - 🔬 **Slurm**: Run on HPC cluster
     - 🧪 **Sandbox**: Mock execution for testing

2. **Real-time monitoring:**
   - **Status updates** via Server-Sent Events (SSE)
   - **Progress bar** showing completed steps
   - **Log streaming** from Nextflow execution
   - **Resource usage** (CPU, memory, disk)

3. **State synchronization:**
   - Show how frontend status matches backend state
   - Highlight the fix we just implemented:
     - ✅ Backend monitoring thread
     - ✅ Database commit on completion
     - ✅ Frontend recognizes 'scheduled' as terminal state

**What to say:**
> "BioMate provides real-time execution monitoring. We've integrated with Nextflow for scalable pipeline execution, and recently fixed a critical state synchronization bug to ensure the UI always reflects the true backend status."

---

### Part 4: Results & Downloads (3 min)

**Show outputs:**

1. **Completed workflow panel:**
   - ✅ Output files listed with metadata
   - 📊 Visualization options (if applicable)
   - ⬇️ Download buttons for each output

2. **Result validation:**
   - Show output file contents
   - Highlight data format (JSON, CSV, plots)
   - Verify scientific accuracy of results

3. **Report generation:**
   - Auto-generated execution report
   - Includes: workflow graph, parameters, execution time, resources used
   - Downloadable as PDF or HTML

**What to say:**
> "All outputs are stored in Galaxy histories and can be downloaded or visualized directly in the UI. BioMate validates that outputs are scientifically plausible and in the correct format."

---

### Part 5: Advanced Features (2 min)

**Quick highlights:**

1. **Multi-domain support:**
   - Biochemistry (enzyme kinetics, protein analysis)
   - Microbiology (growth models, community dynamics)
   - Genomics (RNA-seq, variant calling)
   - Structural Biology (AlphaFold, Cryo-EM)
   - Pharmacology (drug screening, ADME)

2. **Intelligent features:**
   - **Auto-pilot mode**: AI suggests optimal sample sizes
   - **QC gates**: Pause execution if quality metrics fail
   - **AutoFix**: AI automatically fixes common errors
   - **Parameter suggestions**: AI recommends optimal parameters

3. **Infrastructure flexibility:**
   - Local execution (CPU/GPU)
   - AWS Batch (scalable cloud)
   - Slurm/HPC (institutional clusters)
   - Nextflow Tower integration (coming soon)

---

## Key Selling Points

### For Researchers:
- ✅ **No coding required** - describe analysis in plain English
- ✅ **950+ validated workflows** - covering major bioinformatics domains
- ✅ **Real-time monitoring** - see exactly what's happening
- ✅ **Reproducible** - all workflows are versioned and parameterized
- ✅ **Scalable** - runs on laptop or cloud with 1000s of CPUs

### For Institutions:
- ✅ **Cost tracking** - built-in billing for AWS/cloud usage
- ✅ **Multi-user** - supports teams with shared workflows
- ✅ **HPC integration** - works with existing Slurm infrastructure
- ✅ **Audit trail** - complete execution logs for compliance

### Technical Highlights:
- ✅ **LLM-powered**: Claude Opus 4.6 for intent classification
- ✅ **Nextflow backend**: Industry-standard workflow engine
- ✅ **Galaxy integration**: 20+ years of bioinformatics tooling
- ✅ **Real-time SSE**: Sub-second status updates
- ✅ **State synchronization**: Recently fixed critical bug (Feb 2026)

---

## Demo Questions to Anticipate

**Q: "What if the AI generates the wrong workflow?"**
A: Users can review and edit the generated workflow JSON before execution. The system also shows confidence scores and allows manual tool selection.

**Q: "Can it handle my custom tools?"**
A: Yes! BioMate has an auto-update pipeline that discovers new tools from GitHub, containerizes them, and adds them to the database.

**Q: "What about data security?"**
A: All execution can be done locally. For cloud execution, data is encrypted in transit and at rest on S3. Future: private cloud VPC deployment.

**Q: "How accurate are the AI-generated parameters?"**
A: The LLM is fine-tuned on 236+ existing workflows. Parameters are validated against tool schemas. Pilot mode allows testing on small datasets first.

**Q: "What's the cost?"**
A: Local execution is free. Cloud execution uses AWS Batch pricing (~$0.10/vCPU-hour). Built-in billing tracks usage per user with quota limits.

---

## Follow-up Materials

After the demo, provide:
1. **Live access** to the demo instance (if appropriate)
2. **This guide** as PDF
3. **Architecture diagram** (frontend/backend/infra)
4. **Sample workflows** they can try
5. **Roadmap** showing upcoming features
6. **Case studies** from early adopters (if available)

---

## Technical Setup Notes

**For the demo environment:**
- Frontend: http://localhost:5000 (Node.js/Express)
- Backend: Galaxy Python on port 8081 (or galaxy_nextflow on 8080)
- Database: 950+ workflows indexed, 236+ Nextflow pipelines
- Recent fix: State synchronization bug (Feb 18-19, 2026)

**Demo data:**
- Use mock mode for fast demos (no real computation)
- Keep sample datasets small (< 1 MB) for quick execution
- Pre-run one workflow to warm up the system

**If something breaks:**
- Check frontend logs: `pm2 logs` or console
- Check backend logs: `/tmp/galaxy_backend_new.log`
- Restart services: `pm2 restart all` for frontend
- Fall back to explaining the architecture with diagrams

---

## Recording the Demo

See `BIOMATE_UI_DEMO_RECORDING.sh` for automated screen recording commands.

