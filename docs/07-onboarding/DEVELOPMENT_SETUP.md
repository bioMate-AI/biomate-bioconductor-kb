# Development Environment Setup

This guide walks you through setting up your local development environment for Biomate.

---

## Prerequisites

### Required Software

| Software | Version | Installation |
|----------|---------|--------------|
| Node.js | 20.x LTS | [nodejs.org](https://nodejs.org) or `nvm install 20` |
| Python | 3.11+ | [python.org](https://python.org) or `pyenv install 3.11` |
| PostgreSQL | 14+ | `brew install postgresql` (macOS) |
| Git | 2.x | `brew install git` (macOS) |

### Optional Software
| Software | Purpose | Installation |
|----------|---------|--------------|
| Redis | Session storage (production) | `brew install redis` |
| Docker | Container deployment | [docker.com](https://docker.com) |

---

## Step 1: Clone the Repository

```bash
# Clone with SSH (recommended)
git clone git@github.com:your-org/biomate.git
cd biomate

# Or clone with HTTPS
git clone https://github.com/your-org/biomate.git
cd biomate
```

---

## Step 2: Environment Configuration

### Create Environment File

```bash
# Copy the example environment file
cp .env.example .env
```

### Edit .env with Required Values

```bash
# Required: Claude API key for AI features
ANTHROPIC_API_KEY=sk-ant-api03-your-key-here

# Required: PostgreSQL database connection
DATABASE_URL=postgresql://biomate:password@localhost:5432/biomate_dev

# Required: JWT secret (generate a secure key)
JWT_SECRET=$(openssl rand -hex 32)

# Required: AWS S3 for file storage
AWS_ACCESS_KEY_ID=your-aws-access-key
AWS_SECRET_ACCESS_KEY=your-aws-secret-key
AWS_REGION=us-east-1
S3_BUCKET_NAME=biomate-dev-yourusername

# Optional: OpenAI fallback
# OPENAI_API_KEY=sk-...

# Optional: Stripe (for payment features)
# STRIPE_SECRET_KEY=sk_test_...
```

### Get API Keys

| Key | Where to Get |
|-----|-------------|
| ANTHROPIC_API_KEY | [console.anthropic.com](https://console.anthropic.com) |
| OPENAI_API_KEY | [platform.openai.com](https://platform.openai.com) |
| AWS credentials | AWS Console → IAM → Users → Security credentials |
| STRIPE_SECRET_KEY | [dashboard.stripe.com/apikeys](https://dashboard.stripe.com/apikeys) |

---

## Step 3: Database Setup

### Option A: Local PostgreSQL

```bash
# Start PostgreSQL (macOS)
brew services start postgresql

# Create database and user
psql postgres << EOF
CREATE USER biomate WITH PASSWORD 'password';
CREATE DATABASE biomate_dev OWNER biomate;
GRANT ALL PRIVILEGES ON DATABASE biomate_dev TO biomate;
EOF
```

### Option B: Docker PostgreSQL

```bash
docker run -d \
  --name biomate-postgres \
  -e POSTGRES_USER=biomate \
  -e POSTGRES_PASSWORD=password \
  -e POSTGRES_DB=biomate_dev \
  -p 5432:5432 \
  postgres:14
```

### Run Database Migrations

```bash
cd frontend
npm run db:push
```

---

## Step 4: Frontend Setup

```bash
cd frontend

# Install dependencies
npm install

# Start development server
npm run dev
```

The frontend will be available at:
- **React Client**: http://localhost:5173
- **Express API**: http://localhost:3000

### Expected Output

```
[Server] Initializing...
[Server] Seeding example parameter templates...
[Server] Seeding example workflow templates...
[GalaxyAssistant] Initialized with Claude Sonnet 4.5
serving on port 3000
```

---

## Step 5: Backend Setup (Optional)

The Python backend is only needed for advanced AI features and Galaxy integration.

```bash
cd backend

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # macOS/Linux
# or .venv\Scripts\activate  # Windows

# Install dependencies
pip install -r requirements.txt

# Run backend server
python -m galaxy.webapps.galaxy
```

---

## Verify Installation

### 1. Check Health Endpoint

```bash
curl http://localhost:3000/api/health
# Should return: {"status":"ok","timestamp":"..."}
```

### 2. Test Chat API

```bash
curl -X POST http://localhost:3000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "What tools are available for RNA-seq analysis?"}'
```

### 3. Open in Browser

Navigate to http://localhost:5173 and:
1. You should see the Biomate chat interface
2. Try sending a message
3. Verify AI response appears

---

## Common Issues

### Issue: "ANTHROPIC_API_KEY not configured"

**Solution**: Ensure your `.env` file has a valid Anthropic API key:
```bash
grep ANTHROPIC_API_KEY .env
# Should show: ANTHROPIC_API_KEY=sk-ant-api03-...
```

### Issue: Database connection refused

**Solution**: Verify PostgreSQL is running:
```bash
# macOS
brew services list | grep postgresql

# Docker
docker ps | grep postgres

# Test connection
psql -h localhost -U biomate -d biomate_dev -c "SELECT 1"
```

### Issue: "Module not found" errors

**Solution**: Clear node_modules and reinstall:
```bash
cd frontend
rm -rf node_modules
npm install
```

### Issue: Port already in use

**Solution**: Find and kill the process:
```bash
# Find process on port 3000
lsof -i :3000

# Kill it
kill -9 <PID>
```

### Issue: S3 upload failures

**Solution**: Verify AWS credentials:
```bash
# Test AWS CLI access
aws s3 ls s3://your-bucket-name

# Check env vars are set
echo $AWS_ACCESS_KEY_ID
echo $AWS_REGION
```

---

## Development Commands

### Frontend

```bash
cd frontend

# Start development server
npm run dev

# Build for production
npm run build

# Run production build locally
npm start

# Type checking
npm run check

# Database migrations
npm run db:push
```

### Backend

```bash
cd backend
source .venv/bin/activate

# Run tests
pytest

# Run specific test file
pytest lib/galaxy/ai/test_llm_client.py -v

# Run with coverage
pytest --cov=lib/galaxy/ai
```

---

## IDE Setup

### VS Code (Recommended)

Install these extensions:
- **ESLint** - JavaScript/TypeScript linting
- **Prettier** - Code formatting
- **Tailwind CSS IntelliSense** - CSS autocomplete
- **Python** - Python support
- **REST Client** - API testing

#### Recommended Settings (`.vscode/settings.json`)

```json
{
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "typescript.preferences.importModuleSpecifier": "relative",
  "python.formatting.provider": "black",
  "python.linting.enabled": true,
  "python.linting.pylintEnabled": true
}
```

### WebStorm/PyCharm

1. Open the project root directory
2. Configure Node.js interpreter: Preferences → Languages → Node.js
3. Configure Python interpreter: Preferences → Project → Python Interpreter
4. Enable ESLint: Preferences → Languages → JavaScript → ESLint

---

## Environment-Specific Notes

### macOS
```bash
# Install Homebrew if needed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install dependencies
brew install node@20 postgresql python@3.11
```

### Linux (Ubuntu/Debian)
```bash
# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install PostgreSQL
sudo apt-get install -y postgresql postgresql-contrib

# Install Python
sudo apt-get install -y python3.11 python3.11-venv
```

### Windows (WSL2 Recommended)
```bash
# Install WSL2
wsl --install

# Then follow Linux instructions inside WSL2
```

---

## Next Steps

1. **Read the Architecture Docs**
   - [System Overview](../01-architecture/SYSTEM_OVERVIEW.md)
   - [Information Flow](../01-architecture/INFORMATION_FLOW.md)

2. **Follow the New Developer Guide**
   - [New Developer Guide](NEW_DEVELOPER_GUIDE.md)

3. **Make Your First Contribution**
   - Pick a beginner-friendly task
   - Create a feature branch
   - Submit a pull request

---

## Quick Reference

| Command | Description |
|---------|-------------|
| `cd frontend && npm run dev` | Start development server |
| `npm run build` | Build for production |
| `npm run check` | TypeScript type checking |
| `npm run db:push` | Push database schema |
| `pytest` | Run Python tests |
| `git checkout -b feature/name` | Create feature branch |

---

**Last Updated**: January 9, 2026
