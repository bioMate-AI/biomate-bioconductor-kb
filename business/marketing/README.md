# BioMate Marketing Outreach Agent
**Created:** 2026-02-25

## What's in this folder

```
marketing/
├── outreach_agent.py                          # Main CLI agent
├── outreach_templates.py                      # Personalized email generator
├── TEXAS_STRATEGY_20260225.md                 # Full strategy + energy-biology analysis
├── README.md                                  # This file
└── targets/
    ├── texas_targets.json                     # ~82 Texas targets
    ├── doe_labs_targets.json                  # ~16 DOE National Lab targets
    ├── gulf_coast_targets.json                # ~18 Gulf Coast targets
    ├── agricultural_genomics_targets.json     # ~22 Ag genomics targets
    └── clinical_cro_targets.json             # ~18 Clinical lab / CRO targets
```

**Total: ~156 curated targets** across 5 segments, all with priority scores (A/B/C), domain tags, BioMate workflow mapping, and key contacts.

---

## Quick Start

```bash
cd /home/yzhang/biomate/business/marketing

# See what we've got
python outreach_agent.py --stats

# Export all Texas targets as CSV
python outreach_agent.py --output csv --segment texas --save texas_targets.csv

# Generate Priority-A personalized email drafts for Texas
python outreach_agent.py --output emails --segment texas --priority A

# All energy-linked targets (cross-file)
python outreach_agent.py --output emails --segment energy

# DOE labs (metagenomics + bioenergy focus)
python outreach_agent.py --output emails --segment doe_labs --priority A,B

# Clinical CROs (21 CFR Part 11 angle)
python outreach_agent.py --output emails --segment cro --priority A
```

---

## Priority Definitions

| Priority | Criteria |
|---|---|
| **A** | Dedicated bioinformatics dept/core, >10 researchers, strong multi-domain overlap. Send email this week. |
| **B** | Active computational biology lab, known PI, specific workflow overlap. Send email this month. |
| **C** | Emerging program, smaller lab, or company without confirmed bioinformatics infrastructure. Send next quarter. |

---

## The Energy-Biology Opportunity

Texas has a **unique** intersection of oil & gas industry and genomics:

1. **MEOR** — 16S/WGS metagenomics for oil reservoir microbiome characterization
2. **Bioremediation** — functional annotation to identify petroleum-degrading microbes
3. **Algae biofuels** — RNA-seq + comparative genomics for strain optimization
4. **Industrial fermentation QC** — proteomics + RNA-seq with FDA audit trails

No other bioinformatics platform is targeting this market. See `TEXAS_STRATEGY_20260225.md` for the full analysis.

---

## Don't Just Use Email

Cold email alone has <1% conversion. Prioritize:
1. **GitHub** — tag repo, contribute to nf-core, open-source a utility
2. **Twitter/X `@BiomateAI`** — bioinformatics community is very active there
3. **r/bioinformatics** — 120K members, "Show HN"-style launch post
4. **nf-core Slack** — 10,000+ Nextflow users
5. **bioRxiv preprint** — pulls inbound academic traffic
6. **Conference posters** — ISMB 2026, Texas Biotech Forum, TMC Innovation Symposium

See `TEXAS_STRATEGY_20260225.md` → "Public & Inbound Discovery Channels" for the full playbook.

---

## Adding New Targets

Edit any JSON file in `targets/`. Each entry needs:

```json
{
  "id": "unique-slug",
  "name": "Institution/Company Name",
  "city": "City", "state": "TX",
  "segment": "academic|medical|biotech|energy|doe_labs|...",
  "sub_segment": "description",
  "key_contacts": [
    {"name": "PI Name", "title": "Professor", "email_hint": "pi@university.edu"}
  ],
  "domains": ["rnaseq", "metagenomics"],
  "biomate_workflows": ["rnaseq", "metagenomics"],
  "priority": "A",
  "reach_channel": "cold-email",
  "notes": "Why this target matters",
  "energy_link": false,
  "website": "https://..."
}
```
