# New Developer Guide

Welcome to Biomate! This guide will help you get up to speed with the codebase and start contributing.

---

## Your First Day

### 1. Get Access
- [ ] GitHub repository access
- [ ] Slack channel (#biomate-dev)
- [ ] Development credentials (ask team lead)
- [ ] Claude API key for local development

### 2. Set Up Your Environment
Follow the [Development Setup Guide](DEVELOPMENT_SETUP.md) to get your local environment running.

### 3. Understand the Architecture
Read these documents in order:
1. [System Overview](../01-architecture/SYSTEM_OVERVIEW.md) - High-level architecture
2. [Information Flow](../01-architecture/INFORMATION_FLOW.md) - How data moves through the system
3. [Start Here](../00-START-HERE.md) - Quick navigation reference

---

## Codebase Orientation

### Directory Map

```
biomate/
├── frontend/                 # React + Express application
│   ├── client/src/          # React UI code
│   │   ├── components/      # UI components (START HERE for frontend)
│   │   ├── hooks/           # Custom React hooks
│   │   ├── lib/             # API clients & utilities
│   │   └── pages/           # Route pages
│   ├── server/              # Express backend (START HERE for API)
│   │   ├── routes.ts        # All API endpoints
│   │   └── galaxy-assistant.ts  # AI integration
│   └── shared/              # Shared types between client/server
│
├── backend/                  # Galaxy + Python AI
│   └── lib/galaxy/ai/       # AI modules (START HERE for ML/AI)
│       ├── ai_assistant.py  # Main orchestrator
│       └── llm_client.py    # LLM integration
│
└── docs/                     # Documentation (you are here)
```

### Key Files to Understand First

| File | Purpose | Read When |
|------|---------|-----------|
| `frontend/server/routes.ts` | All API endpoints | Understanding API structure |
| `frontend/server/galaxy-assistant.ts` | AI chat logic | Working on chat features |
| `frontend/client/src/components/chat-interface.tsx` | Main chat UI | Working on UI |
| `frontend/client/src/hooks/useWorkflowExecution.ts` | Workflow state management | Working on execution |
| `backend/lib/galaxy/ai/ai_assistant.py` | Backend AI orchestrator | Working on AI logic |

---

## First Tasks

### Beginner-Friendly Tasks
These are good first contributions to learn the codebase:

1. **Add a tooltip** to a button in the UI
2. **Fix a typo** in documentation or error messages
3. **Add a new validation rule** to form inputs
4. **Write a unit test** for an existing function
5. **Add logging** to an endpoint that lacks it

### Learning Path

**Week 1: Frontend Focus**
- Run the development server
- Make a small UI change
- Understand React Query usage
- Read chat-interface.tsx thoroughly

**Week 2: Backend Focus**
- Understand routes.ts structure
- Make a small API change
- Read galaxy-assistant.ts
- Learn about SSE implementation

**Week 3: AI Integration**
- Understand the Claude integration
- Learn about tool search
- Study workflow generation
- Explore benchmark knowledge

**Week 4: Full Stack**
- Implement a small end-to-end feature
- Write tests (unit + integration)
- Create a pull request
- Get code review

---

## Development Workflow

### Git Branching

```bash
# Create feature branch from develop
git checkout develop
git pull
git checkout -b feature/my-feature

# Make changes, commit often
git add .
git commit -m "feat: add new feature"

# Push and create PR
git push -u origin feature/my-feature
```

### Branch Naming
- `feature/description` - New features
- `fix/description` - Bug fixes
- `docs/description` - Documentation
- `refactor/description` - Code refactoring
- `test/description` - Test additions

### Commit Messages
Follow conventional commits:
```
feat: add user authentication
fix: resolve workflow execution error
docs: update API documentation
refactor: simplify tool search logic
test: add unit tests for auth service
```

---

## Running Tests

### Frontend Tests
```bash
cd frontend
npm test                  # Run all tests
npm test -- --watch       # Watch mode
npm test -- --coverage    # Coverage report
```

### Backend Tests
```bash
cd backend
pytest                    # Run all tests
pytest -v                 # Verbose output
pytest --cov=lib/galaxy/ai  # Coverage report
```

---

## Code Style

### TypeScript (Frontend)
- Use TypeScript strict mode
- Prefer interfaces over types
- Use async/await over .then()
- Destructure props in components

```typescript
// Good
interface Props {
  message: string;
  onSend: (text: string) => void;
}

const ChatInput = ({ message, onSend }: Props) => {
  // ...
};

// Avoid
const ChatInput = (props: any) => {
  // ...
};
```

### Python (Backend)
- Follow PEP 8
- Use type hints
- Docstrings for public functions
- Async for I/O operations

```python
# Good
async def search_tools(query: str, limit: int = 10) -> list[Tool]:
    """Search for Galaxy tools matching the query.

    Args:
        query: Search string
        limit: Maximum number of results

    Returns:
        List of matching Tool objects
    """
    pass
```

---

## Common Patterns

### API Endpoints
```typescript
// frontend/server/routes.ts

app.post("/api/feature", authenticateToken, async (req, res) => {
  try {
    const { param1, param2 } = req.body;

    if (!param1) {
      return res.status(400).json({ error: "param1 is required" });
    }

    const result = await someService.doSomething(param1, param2);

    res.json({ success: true, data: result });
  } catch (error: any) {
    console.error('[Feature] Error:', error);
    res.status(500).json({
      error: 'OperationFailed',
      message: error.message
    });
  }
});
```

### React Components
```typescript
// frontend/client/src/components/MyComponent.tsx

import { useState } from 'react';
import { Button } from '@/components/ui/button';

interface MyComponentProps {
  initialValue: string;
  onChange?: (value: string) => void;
}

export function MyComponent({ initialValue, onChange }: MyComponentProps) {
  const [value, setValue] = useState(initialValue);

  const handleChange = (newValue: string) => {
    setValue(newValue);
    onChange?.(newValue);
  };

  return (
    <div className="flex gap-2">
      <input value={value} onChange={(e) => handleChange(e.target.value)} />
      <Button onClick={() => handleChange('')}>Clear</Button>
    </div>
  );
}
```

### Custom Hooks
```typescript
// frontend/client/src/hooks/useMyFeature.ts

import { useState, useCallback } from 'react';

export function useMyFeature() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const doSomething = useCallback(async (param: string) => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch('/api/feature', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ param }),
      });

      if (!response.ok) throw new Error('Request failed');

      return await response.json();
    } catch (err: any) {
      setError(err.message);
      throw err;
    } finally {
      setLoading(false);
    }
  }, []);

  return { doSomething, loading, error };
}
```

---

## Debugging Tips

### Frontend
```typescript
// Use React DevTools extension
// Add console logs (remove before committing)
console.log('[ComponentName] state:', state);

// Use debugger statement
debugger; // Browser will pause here
```

### Backend
```python
# Python logging
import logging
logger = logging.getLogger(__name__)
logger.info(f"Processing request: {request_data}")

# Print debugging (remove before committing)
print(f"[DEBUG] value = {value}")
```

### API Requests
```bash
# Test endpoints with curl
curl -X POST http://localhost:3000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello"}'

# Or use the REST Client VS Code extension
```

---

## Getting Help

### Resources
- [Start Here](../00-START-HERE.md) - Documentation index
- Slack: #biomate-dev
- GitHub Issues: Report bugs, request features

### Who to Ask
- **Frontend questions**: [Frontend lead]
- **Backend/AI questions**: [Backend lead]
- **Infrastructure/DevOps**: [DevOps lead]
- **Architecture decisions**: [Tech lead]

### Code Review
- All PRs require at least 1 approval
- Address all comments before merging
- Squash commits if requested

---

## Checklist: Ready to Contribute?

- [ ] Local environment running
- [ ] Can start frontend dev server
- [ ] Understand the architecture docs
- [ ] Made a test commit on a feature branch
- [ ] Ran the test suite
- [ ] Read through one major component

**You're ready! Pick a beginner task and start contributing!**

---

**Last Updated**: January 9, 2026
