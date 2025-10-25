# BioMate - AI-Powered Galaxy Workflow Generator

BioMate is an intelligent workflow generation platform that uses AI to create Galaxy workflows from natural language descriptions. It leverages a comprehensive database of 7000+ Galaxy tools to build bioinformatics analysis pipelines.

## Features

- **Natural Language Workflow Generation**: Describe your analysis in plain English
- **7000+ Galaxy Tools**: Access to comprehensive Galaxy tool database
- **Real-time Workflow Visualization**: Interactive workflow graph editor
- **Parameter Configuration**: Edit tool parameters with templates
- **Execution Monitoring**: Track workflow execution with real-time updates
- **Galaxy Integration**: Native Galaxy workflow execution (.ga format)

## Prerequisites

- **Python 3.9+**
- **Node.js 16+**
- **Git**
- **Git LFS** (if database files are tracked with LFS)
- **Anthropic API Key** (for Claude AI)

## Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/bioMate-AI/biomate.git
cd biomate
```

### 2. Setup Database Files

The application requires two large database files not included in the repository:

- `backend/galaxy_ai_tools.db` (144 MB) - Galaxy tools database
- `backend/database/all_unique_tools.json` (69 MB) - Tool definitions

**Option A: Download from release/cloud storage**
```bash
# Contact the repository maintainer for database file access
# Or download from releases page
```

**Option B: If using Git LFS**
```bash
git lfs pull
```

### 3. Configure API Keys

```bash
cd backend

# Copy environment template
cp .env.template .env

# Edit .env and add your API keys
# ANTHROPIC_API_KEY=your-key-here

# Copy config template
cp config/galaxy.yml.template config/galaxy.yml

# The config will read from environment variables
```

### 4. Backend Setup

```bash
cd backend

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Start Galaxy backend
./run.sh
```

The backend will be available at: `http://localhost:8080`

### 5. Frontend Setup

```bash
cd frontend

# Install dependencies
npm install

# Start development server
npm run dev
```

The frontend will be available at: `http://localhost:5173`

### 6. Verify Setup

```bash
# Check backend
curl http://localhost:8080/api/version

# Open frontend in browser
open http://localhost:5173
```

## Project Structure

```
biomate/
├── backend/                    # Galaxy backend
│   ├── config/                 # Galaxy configuration
│   │   ├── galaxy.yml.template # Config template (use this!)
│   │   └── galaxy.yml          # Your config (not in git)
│   ├── database/               # Galaxy runtime databases
│   ├── lib/galaxy/             # Galaxy core library
│   ├── tests/e2e_ui/           # End-to-end tests
│   ├── galaxy_ai_tools.db      # Tool database (144 MB, not in git)
│   ├── run.sh                  # Start script
│   └── requirements.txt        # Python dependencies
├── frontend/                   # React frontend
│   ├── client/                 # React app
│   │   ├── src/
│   │   │   ├── components/     # UI components
│   │   │   ├── hooks/          # React hooks
│   │   │   └── pages/          # Page components
│   │   └── index.html
│   ├── server/                 # Express proxy server
│   │   ├── routes.ts           # API routes
│   │   └── index.ts
│   └── package.json
└── README.md                   # This file
```

## Development

### Running Tests

```bash
cd backend/tests/e2e_ui
pytest test_cases/test_01_dia_lcms.py -v
```

### Building for Production

```bash
# Frontend
cd frontend
npm run build

# Backend
cd backend
# Follow Galaxy deployment guide
```

## Configuration

### Environment Variables

Create `backend/.env` with:

```bash
ANTHROPIC_API_KEY=your-anthropic-api-key
OPENAI_API_KEY=your-openai-api-key  # Optional backup
```

### Galaxy Configuration

Edit `backend/config/galaxy.yml`:

```yaml
galaxy:
  enable_ai_assistant: true
  ai_llm_provider: anthropic
  ai_llm_model: claude-sonnet-4-5
  ai_llm_api_key: ${ANTHROPIC_API_KEY}
```

## Database Files

### galaxy_ai_tools.db

Contains indexed information for 7000+ Galaxy tools:
- Tool IDs and names
- Tool descriptions
- Parameter information
- Help text and documentation

**Size:** 144 MB
**Location:** `backend/galaxy_ai_tools.db`
**Required:** Yes

### all_unique_tools.json

Complete tool definitions from Galaxy:
- Full tool XML schemas
- Input/output specifications
- Parameter definitions

**Size:** 69 MB
**Location:** `backend/database/all_unique_tools.json`
**Required:** Yes

## API Documentation

### Backend API (Port 8080)

- `GET /api/version` - Galaxy version
- `POST /api/workflows/generate` - Generate workflow from text
- `POST /api/galaxy/workflows/invoke` - Execute workflow
- `GET /api/galaxy/workflows/sse/:invocationId` - Real-time updates

### Frontend API (Port 5173)

The frontend proxies Galaxy API calls through Express server.

## Architecture

```
User Browser
    ↓
Frontend (React + Vite) :5173
    ↓
Express Proxy Server
    ↓
Galaxy Backend (Python) :8080
    ↓
AI Service (Claude/OpenAI)
```

## Troubleshooting

### Backend won't start

**Check database file exists:**
```bash
ls -lh backend/galaxy_ai_tools.db
```

**Check Python version:**
```bash
python3 --version  # Should be 3.9+
```

**Check Galaxy logs:**
```bash
tail -f backend/galaxy.log
```

### Frontend build errors

**Clear node_modules:**
```bash
rm -rf frontend/node_modules
npm install
```

**Check Node version:**
```bash
node --version  # Should be 16+
```

### Workflow generation fails

**Check API key:**
```bash
# In backend/.env
echo $ANTHROPIC_API_KEY
```

**Check backend logs:**
```bash
tail -f backend/galaxy.log | grep -i "workflow"
```

### Database path errors

**Verify path in code:**
The fix is in `backend/lib/galaxy/ai/galaxy_workflow_generator.py:538`

**Check database is readable:**
```bash
sqlite3 backend/galaxy_ai_tools.db "SELECT COUNT(*) FROM tools;"
```

## Security Notes

⚠️ **Never commit API keys to git!**

- Use environment variables for secrets
- Keep `galaxy.yml` out of git (use `galaxy.yml.template`)
- Add `.env` to `.gitignore`
- Revoke any exposed keys immediately

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## Testing Status

**E2E Tests:** 5/10 passing (50%)

**Passing:**
- ✅ Navigate to chat interface
- ✅ Send workflow query
- ✅ Wait for workflow generation
- ✅ Validate workflow steps
- ✅ Validate parameter editor

**Failing:**
- ❌ Execute individual step (architecture mismatch)
- ❌ Monitor execution
- ❌ View job logs
- ❌ Validate completion

See `backend/tests/e2e_ui/E2E_TEST_FINAL_REPORT_20251024.md` for details.

## License

[Add license information]

## Contact

[Add contact information]

## Acknowledgments

- Built on [Galaxy Project](https://galaxyproject.org/)
- Powered by [Anthropic Claude](https://www.anthropic.com/)
- UI components from [shadcn/ui](https://ui.shadcn.com/)
