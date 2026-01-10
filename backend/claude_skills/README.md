# Claude Skills Integration

Integration of Claude Scientific Skills resources into BioMate's tool index.

## Source Repository
`/home/yzhang/biomate/research_repos/claude-scientific-skills-biomate/`

## Contents

```
claude_skills/
├── README.md                                    # This file
├── 20251204_CLAUDE_SKILLS_VS_TOOL_INDEX_GAP_ANALYSIS.md  # Gap analysis
├── 20251204_CLAUDE_SKILLS_INTEGRATION_PLAN.md   # Integration plan
├── test_tools.db                                # Test database
├── scripts/
│   └── populate_test_db.py                      # Script to populate test DB
└── data/
    ├── databases.json                           # Database tool definitions
    ├── packages.json                            # Package tool definitions
    └── integrations.json                        # Integration tool definitions
```

## Resource Types

| Type | Count | Pattern |
|------|-------|---------|
| Databases | 4 | `biomni/database/query_{name}` |
| Packages | 13 | `biomni/package/{name}` |
| Integrations | 6 | `biomni/integration/{name}` |

## Workflow

1. Define tools in `data/*.json`
2. Run `scripts/populate_test_db.py` to create test DB
3. Validate with queries
4. Merge into production `galaxy_ai_tools.db`
