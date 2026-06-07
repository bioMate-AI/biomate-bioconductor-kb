# BioMate MCP + /biomate Skill — E2E Test Recording
**Date:** 2026-06-05  
**Backend:** dev EC2 (52.42.49.175), `biomate-dev-frontend` port 3000, Galaxy port 8080  
**Auth:** JWT for xiaoni5122@gmail.com (dev account)

---

## Setup

```
SSH tunnel: local:13000 → EC2:3000 (Node.js frontend)
MCP server: python3 biomate_mcp_server.py
           BIOMATE_API_URL=http://localhost:13000
           BIOMATE_API_KEY=<JWT>
Skill:     ~/.claude/plugins/marketplaces/biomate/plugins/biomate/commands/biomate.md
```

## Command Invoked

```bash
echo "Screen aspirin (CC(=O)Oc1ccccc1C(=O)O) for ADMET properties and hERG cardiac liability" | \
claude -p \
  --dangerously-skip-permissions \
  --mcp-config /tmp/biomate_mcp.json \
  --system-prompt "$(skill prompt from biomate.md)"
```

## Full Output

```
Here's the live BioMate session for aspirin:

---

▶ Workflow selected: predict_admet_properties — screening aspirin across 6 ADMET and cardiac safety endpoints

✓ Input parsed: CC(=O)Oc1ccccc1C(=O)O (Aspirin)

▶ ADMET & hERG screening starting…

✓ SMILES → DILI hepatotoxicity scoring
✓ Caco-2 permeability prediction
✓ BBB (blood-brain barrier) penetration
✓ Aqueous solubility
✓ Ames mutagenicity
✓ hERG cardiac liability scoring
✓ Risk aggregation → traffic-light flags (GREEN / YELLOW / RED per endpoint)

---

Key Findings — Aspirin (CC(=O)Oc1ccccc1C(=O)O)

Endpoint               | Prediction                 | Flag
hERG Cardiac Liability | Low inhibitory potency     | GREEN
Caco-2 Permeability    | Moderate intestinal abs.   | YELLOW
BBB Penetration        | Low CNS penetrance         | GREEN
Aqueous Solubility     | Moderate (log S ≈ −2.1)    | YELLOW
Ames Mutagenicity      | Non-mutagenic              | GREEN
DILI Hepatotoxicity    | Low risk                   | GREEN

Summary:
Aspirin shows a favorable overall ADMET profile. Its most notable safety
characteristic is negligible hERG liability — the acetylsalicylate scaffold
lacks the structural features (basic nitrogen, hydrophobic bulk) associated
with hERG channel blockade, making it essentially free of cardiac QT
prolongation risk. Oral absorption is adequate but moderate due to its
carboxylic acid group. The compound is non-mutagenic, non-hepatotoxic, and
does not meaningfully cross the blood-brain barrier.

View full results → biomate.ai/panel/run/admet-aspirin-CC_OC

Workflow: predict_admet_properties
Outputs: admet_results.csv · risk_summary.json
```

## Issues Found and Fixed

| Issue | Fix |
|-------|-----|
| Galaxy bound to `localhost:8080` inside container — cross-container requests refused | Restarted gunicorn with `-b 0.0.0.0:8080` |
| `galaxy_ai_tools.db` on dev missing `workflows` table (only FTS indexes) | `scp` + `docker cp` local DB (2632 workflows) into Galaxy container |
| `/biomate` skill not resolving — `biomate` marketplace not in `known_marketplaces.json` | Workaround: pass skill body as `--system-prompt` directly |

## Skill Resolution Status

The `/biomate` slash command doesn't resolve yet because the `biomate` marketplace
isn't registered in a way the `claude plugin install` CLI accepts (requires `source.source`
to be `git-subdir` or `github`, not `local`). The skill prompt works correctly when
passed as `--system-prompt`.

**To properly install:** publish the skill to a GitHub repo and register via:
```json
{
  "source": "git-subdir",
  "url": "https://github.com/biomate-AI/claude-plugins.git",
  "path": "plugins/biomate"
}
```

## MCP Unit Tests (25/25)

All 25 checks passed in `backend/tests/test_mcp_e2e.py`:
- initialize (protocol handshake)
- tools/list (all 14 mcp__biomate__* tools)  
- biomate_session (3-phase ADMET flow: chat stream → execute → events)
- search_workflow (catalog search)
- skill file format (YAML frontmatter, 14 tools, local install)
