#!/usr/bin/env python3
"""Write updated benchmark matrix Excel v3 with 4 sheets."""

import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

OUTPUT = "docs/20260416_biomate_benchmark_matrix_v3.xlsx"

# --- Style helpers ---
HEADER_FILL  = PatternFill("solid", fgColor="1F4E79")   # dark navy
SUBHDR_FILL  = PatternFill("solid", fgColor="2E75B6")   # mid blue
ALT_FILL     = PatternFill("solid", fgColor="D6E4F0")   # light blue
WHITE_FILL   = PatternFill("solid", fgColor="FFFFFF")
GAP_FILL     = PatternFill("solid", fgColor="FCE4D6")   # salmon
OK_FILL      = PatternFill("solid", fgColor="E2EFDA")   # light green

HEADER_FONT  = Font(bold=True, color="FFFFFF", size=11)
SUBHDR_FONT  = Font(bold=True, color="FFFFFF", size=10)
BOLD         = Font(bold=True, size=10)
NORMAL       = Font(size=10)
TITLE_FONT   = Font(bold=True, size=13, color="1F4E79")

thin = Side(style="thin", color="AAAAAA")
BORDER = Border(left=thin, right=thin, top=thin, bottom=thin)

def hdr_cell(ws, row, col, value, fill=None, font=None, align="center"):
    c = ws.cell(row=row, column=col, value=value)
    c.fill  = fill  or HEADER_FILL
    c.font  = font  or HEADER_FONT
    c.alignment = Alignment(horizontal=align, vertical="center", wrap_text=True)
    c.border = BORDER
    return c

def data_cell(ws, row, col, value, fill=None, font=None, align="left", bold=False):
    c = ws.cell(row=row, column=col, value=value)
    c.fill  = fill  or WHITE_FILL
    c.font  = Font(bold=bold, size=10)
    c.alignment = Alignment(horizontal=align, vertical="center", wrap_text=True)
    c.border = BORDER
    return c

def set_col_widths(ws, widths):
    for i, w in enumerate(widths, 1):
        ws.column_dimensions[get_column_letter(i)].width = w

def freeze(ws, cell="A2"):
    ws.freeze_panes = cell

# ============================================================
# SHEET 1 — BioMate Results
# ============================================================

wb = openpyxl.Workbook()
ws1 = wb.active
ws1.title = "BioMate Results"

# Title row
ws1.merge_cells("A1:G1")
tc = ws1["A1"]
tc.value = "BioMate Benchmark Results — 2026-04-16"
tc.font  = TITLE_FONT
tc.alignment = Alignment(horizontal="center", vertical="center")
ws1.row_dimensions[1].height = 28

# Header row 2
headers1 = ["Benchmark", "Task Type", "N", "BioMate Score",
            "Best Competitor", "BioMate vs Competitor", "Status"]
for col, h in enumerate(headers1, 1):
    hdr_cell(ws1, 2, col, h)
ws1.row_dimensions[2].height = 36

# Data rows
rows1 = [
    ("SGI-Bench",                       "deep_research",           30, "10–17%",
     "GPT-4o: ~15%",           "Competitive",       "Track 1 added"),
    ("BiomniEval1",                     "gwas_causal_gene",         30, "26.7%",
     "Biomni-R0-32B: >80%",    "Gap",               "Routing fix applied"),
    ("BiomniEval1",                     "screen_gene_retrieval",    30, "40.0%",
     "Biomni-R0-32B: >80%",    "Gap",               "Format fix applied"),
    ("BiomniEval1",                     "gwas_variant_prioritization", 30, "13.3%",
     "Biomni-R0-32B: >80%",    "Gap",               "Knowledge-limited"),
    ("BiomniEval1",                     "patient_gene_detection",   30, "40.0%",
     "Biomni-R0-32B: >80%",    "Gap",               "DB lookup added"),
    ("BiomniEval1",                     "rare_disease_diagnosis",   30, "40.0%",
     "Biomni-R0-32B: >80%",    "Gap",               "DB lookup added"),
    ("BiomniEval1 OVERALL",             "avg (5 tasks)",            30, "32.0%",
     "Biomni-R0-32B: >80%",    "Gap",               "Mean of above 5"),
    ("BixBench",                        "MCQ mode",                 30, "26.7%",
     "Published (exec): 88.7%","Gap",               "Need exec mode"),
    ("Routing Benchmark",               "variant_calling",          30, "93.3% (post-patch)",
     "N/A",                    "N/A",               "Patch applied"),
    ("Routing Benchmark",               "atac_seq / cutandrun",     30, "88.2% (post-patch)",
     "N/A",                    "N/A",               "Patch applied"),
    ("Routing Benchmark",               "overall v9",              120, "93.3%",
     "N/A",                    "N/A",               "Baseline"),
]

for r_idx, row in enumerate(rows1, 3):
    alt = ALT_FILL if r_idx % 2 == 0 else WHITE_FILL
    # highlight gap rows in salmon, competitive rows in green, N/A rows default
    vs = row[5]
    if vs == "Gap":
        row_fill = GAP_FILL
    elif vs == "Competitive":
        row_fill = OK_FILL
    else:
        row_fill = alt

    # Bold for OVERALL row
    is_overall = "OVERALL" in row[0]

    for col_idx, val in enumerate(row, 1):
        bold_flag = is_overall
        data_cell(ws1, r_idx, col_idx, val, fill=row_fill, bold=bold_flag,
                  align="center" if col_idx == 3 else "left")

set_col_widths(ws1, [26, 28, 6, 22, 28, 22, 24])
freeze(ws1, "A3")

# ============================================================
# SHEET 2 — Root Causes
# ============================================================

ws2 = wb.create_sheet("Root Causes")

ws2.merge_cells("A1:E1")
tc2 = ws2["A1"]
tc2.value = "Root Cause Analysis & Fixes — 2026-04-16"
tc2.font  = TITLE_FONT
tc2.alignment = Alignment(horizontal="center", vertical="center")
ws2.row_dimensions[1].height = 28

headers2 = ["Benchmark", "Root Cause", "Fix Applied", "Remaining Gap", "Next Action"]
for col, h in enumerate(headers2, 1):
    hdr_cell(ws2, 2, col, h)
ws2.row_dimensions[2].height = 36

rows2 = [
    ("SGI-Bench",
     "No full-text paper data; only abstracts available",
     "Track 1: PMC BioC JSON + Semantic Scholar full-text added to ResearchAgent",
     "PDF figures still inaccessible (bot gates on NCBI/EuropePMC)",
     "Try alternative PDF sources; consider Unpaywall"),
    ("BiomniEval1: gwas_causal_gene",
     "Workflow routing for knowledge queries; boilerplate appended to answer",
     "Intent-type routing fix (galaxy-assistant.ts); first-line extraction fix",
     "30% still route to workflow despite fix",
     "Strengthen format instructions; add negative few-shot examples"),
    ("BiomniEval1: screen_gene_retrieval",
     "Tool-use attempts despite explicit instructions to answer directly",
     "Stronger format instructions; forced direct-answer path",
     "40% cap — appears knowledge-limited",
     "N/A"),
    ("BiomniEval1: gwas_variant_prioritization",
     "Wrong rsID selected from candidate list; limited fine-grained variant knowledge",
     "(none applied this session)",
     "Knowledge-limited — variant↔gene mapping accuracy",
     "few-shot examples with correct selection logic"),
    ("BiomniEval1: patient_gene_detection",
     "No live DB lookups; LLM-only recall insufficient",
     "DB lookup clients added (MyGene.info, Ensembl, Monarch HPO)",
     "40% cap — architecture + context-window limit",
     "Architecture unification with rare_disease path"),
    ("BiomniEval1: rare_disease_diagnosis",
     "No live DB lookups; rare disease ontology not in base LLM",
     "DB lookup clients added (ClinVar, Monarch HPO, OMIM fallback)",
     "40% cap — same as patient_gene_detection",
     "Architecture unification; OMIM API key"),
    ("BixBench",
     "MCQ proxy only; no code execution environment; capsule data not loaded",
     "Code execution enabled (run_code tool); HuggingFace capsule data confirmed",
     "Need full capsule dataset + sandbox execution",
     "Download HuggingFace capsule data; end-to-end exec mode test"),
    ("Routing: variant_calling",
     "Sarek / GATK descriptions ambiguous; epigenomics descriptions too broad",
     "4 structural fixes: sarek exclusions, gatk description, atacseq/cutandrun rewrites",
     "None known",
     "Monitor next benchmark run"),
]

for r_idx, row in enumerate(rows2, 3):
    alt = ALT_FILL if r_idx % 2 == 0 else WHITE_FILL
    for col_idx, val in enumerate(row, 1):
        data_cell(ws2, r_idx, col_idx, val, fill=alt)

set_col_widths(ws2, [30, 38, 40, 36, 36])
freeze(ws2, "A3")

# ============================================================
# SHEET 3 — Competitor Landscape
# ============================================================

ws3 = wb.create_sheet("Competitor Landscape")

ws3.merge_cells("A1:F1")
tc3 = ws3["A1"]
tc3.value = "Competitor Landscape — Key Benchmarks (2026-04-16)"
tc3.font  = TITLE_FONT
tc3.alignment = Alignment(horizontal="center", vertical="center")
ws3.row_dimensions[1].height = 28

headers3 = ["System", "SGI-Bench", "BiomniEval1 Avg", "Architecture", "Notes", "Status"]
for col, h in enumerate(headers3, 1):
    hdr_cell(ws3, 2, col, h)
ws3.row_dimensions[2].height = 36

rows3 = [
    ("BioMate (current, 2026-04-16)",
     "10–17%",
     "32.0%",
     "Workflow orchestration + ResearchAgent + BGE retrieval",
     "General-purpose bioinfo AI with Nextflow execution",
     "ACTIVE"),
    ("Biomni-R0-32B",
     "~40%?",
     ">80%",
     "Specialized biomedical LLM (32B parameter scale)",
     "Trained on gene-disease data; no workflow execution",
     "Competitor"),
    ("Claude 3.7 Sonnet",
     "~15%?",
     "~55%?",
     "General-purpose LLM (frontier)",
     "No workflow integration; API-only",
     "Baseline"),
    ("GPT-4o",
     "~15%",
     "~50%?",
     "General-purpose LLM (frontier)",
     "No workflow integration; API-only",
     "Baseline"),
    ("GPT-5",
     "~18%?",
     "~60%?",
     "General-purpose LLM (frontier, projected)",
     "No workflow integration; projected scores",
     "Projected"),
]

for r_idx, row in enumerate(rows3, 3):
    alt = ALT_FILL if r_idx % 2 == 0 else WHITE_FILL
    # Highlight BioMate row
    if "BioMate" in row[0]:
        row_fill = OK_FILL
    else:
        row_fill = alt
    for col_idx, val in enumerate(row, 1):
        data_cell(ws3, r_idx, col_idx, val, fill=row_fill,
                  bold=("BioMate" in row[0]))

set_col_widths(ws3, [32, 14, 18, 44, 44, 12])
freeze(ws3, "A3")

# ============================================================
# SHEET 4 — Session Summary
# ============================================================

ws4 = wb.create_sheet("Session Summary")

ws4.merge_cells("A1:B1")
tc4 = ws4["A1"]
tc4.value = "Session Summary — 2026-04-16"
tc4.font  = TITLE_FONT
tc4.alignment = Alignment(horizontal="center", vertical="center")
ws4.row_dimensions[1].height = 28

hdr_cell(ws4, 2, 1, "Item", fill=HEADER_FILL)
hdr_cell(ws4, 2, 2, "Detail", fill=HEADER_FILL)
ws4.row_dimensions[2].height = 30

rows4 = [
    ("Date",                    "2026-04-16"),
    ("Session work",            "5 parallel tracks implemented"),
    ("Track 1 — Full-text",
     "PMC BioC JSON + Semantic Scholar full-text added to ResearchAgent; "
     "SGI-Bench score 10% baseline → 16.7% with full-text retrieval"),
    ("Track 2 — Routing patches",
     "Sarek, GATK, atacseq, cutandrun descriptions updated; "
     "epigenomics domain 29.4% → 88.2% post-patch"),
    ("Track 3 — BiomniEval1 baseline",
     "All 5 task types now benchmarked (n=30 each); "
     "gwas_causal_gene, screen_gene, gwas_variant_prio, patient_gene_detection, rare_disease_diagnosis"),
    ("Track 4 — BixBench exec",
     "Infrastructure ready; HuggingFace capsule data access confirmed; "
     "code execution (run_code tool) enabled"),
    ("Track 5 — PDF vision",
     "PyMuPDF + Haiku vision added to ResearchAgent pipeline; "
     "blocked by NCBI/EuropePMC bot gates on direct PDF links"),
    ("Key finding 1",
     "gwas_causal_gene: 3.3% → 26.7% via first-line extraction fix "
     "(removed boilerplate appended to answer)"),
    ("Key finding 2",
     "SGI-Bench: 10% baseline; 16.7% with full-text retrieval "
     "(noise range, n=30 — need larger sample for statistical significance)"),
    ("Key finding 3",
     "BiomniEval1 overall: 32.0% (mean of 5 tasks, n=30 each, fresh runs 2026-04-16); "
     "was ~29% in prior session"),
    ("Key finding 4",
     "Routing v9 overall: 93.3% (112/120); variant_calling domain "
     "improved from ~56.7% → 93.3% via description patches (v6→v9)"),
    ("Open items",
     "1. Larger SGI-Bench run (n≥100) for significance\n"
     "2. OMIM API key for rare_disease_diagnosis\n"
     "3. BixBench full exec mode with capsule data\n"
     "4. gwas_variant_prioritization few-shot examples"),
    ("Next benchmark targets",
     "BiomniEval1 overall ≥40%; SGI-Bench ≥20%; BixBench exec ≥40%"),
]

for r_idx, row in enumerate(rows4, 3):
    alt = ALT_FILL if r_idx % 2 == 0 else WHITE_FILL
    bold_flag = row[0] in ("Date", "Session work", "Key finding 1", "Key finding 2",
                            "Key finding 3", "Key finding 4", "Next benchmark targets")
    data_cell(ws4, r_idx, 1, row[0], fill=alt, bold=True)
    data_cell(ws4, r_idx, 2, row[1], fill=alt)
    ws4.row_dimensions[r_idx].height = 40

set_col_widths(ws4, [30, 80])
freeze(ws4, "A3")

# ============================================================
# Save
# ============================================================
wb.save(OUTPUT)
print(f"Saved: {OUTPUT}")

# Verify
wb2 = openpyxl.load_workbook(OUTPUT)
print("Sheets:", wb2.sheetnames)
for sn in wb2.sheetnames:
    ws = wb2[sn]
    print(f"  {sn}: {ws.max_row} rows x {ws.max_column} cols")
