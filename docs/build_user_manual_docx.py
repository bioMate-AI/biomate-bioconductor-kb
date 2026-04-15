"""
Build BioMate User Manual as a Word document (.docx).
Run: python3 build_user_manual_docx.py
Output: docs/20260403_BIOMATE_USER_MANUAL.docx
"""

from docx import Document
from docx.shared import Inches, Pt, RGBColor, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml.ns import qn
from docx.oxml import OxmlElement
import copy, os

OUT = os.path.join(os.path.dirname(__file__), "20260403_BIOMATE_USER_MANUAL.docx")

doc = Document()

# ── Page margins ──────────────────────────────────────────────────────────────
section = doc.sections[0]
section.page_width  = Cm(21)
section.page_height = Cm(29.7)
section.left_margin = section.right_margin = Cm(2.5)
section.top_margin  = section.bottom_margin = Cm(2.5)

# ── Helpers ───────────────────────────────────────────────────────────────────

BLUE   = RGBColor(0x1a, 0x56, 0xdb)
GRAY   = RGBColor(0x6b, 0x72, 0x80)
SILVER = RGBColor(0xf3, 0xf4, 0xf6)

def h1(text):
    p = doc.add_heading(text, level=1)
    p.runs[0].font.color.rgb = BLUE
    p.runs[0].font.size = Pt(20)
    return p

def h2(text):
    p = doc.add_heading(text, level=2)
    p.runs[0].font.color.rgb = BLUE
    p.runs[0].font.size = Pt(14)
    return p

def h3(text):
    p = doc.add_heading(text, level=3)
    p.runs[0].font.color.rgb = RGBColor(0x37, 0x41, 0x51)
    p.runs[0].font.size = Pt(12)
    return p

def body(text, bold_parts=None):
    p = doc.add_paragraph(text)
    p.style.font.size = Pt(10.5)
    return p

def note(text):
    p = doc.add_paragraph()
    p.paragraph_format.left_indent = Cm(0.8)
    run = p.add_run(text)
    run.font.color.rgb = GRAY
    run.font.italic = True
    run.font.size = Pt(10)
    return p

def code_block(text):
    p = doc.add_paragraph()
    p.paragraph_format.left_indent = Cm(0.8)
    p.paragraph_format.right_indent = Cm(0.8)
    # Gray shading
    pPr = p._p.get_or_add_pPr()
    shd = OxmlElement('w:shd')
    shd.set(qn('w:val'), 'clear')
    shd.set(qn('w:color'), 'auto')
    shd.set(qn('w:fill'), 'F3F4F6')
    pPr.append(shd)
    run = p.add_run(text)
    run.font.name = 'Courier New'
    run.font.size = Pt(9)
    return p

def table(headers, rows, col_widths=None):
    t = doc.add_table(rows=1 + len(rows), cols=len(headers))
    t.style = 'Table Grid'
    t.alignment = WD_TABLE_ALIGNMENT.LEFT
    # Header row
    hdr = t.rows[0]
    for i, h in enumerate(headers):
        cell = hdr.cells[i]
        cell.text = h
        run = cell.paragraphs[0].runs[0]
        run.font.bold = True
        run.font.size = Pt(10)
        run.font.color.rgb = RGBColor(0xff, 0xff, 0xff)
        # Blue header background
        tc = cell._tc
        tcPr = tc.get_or_add_tcPr()
        shd = OxmlElement('w:shd')
        shd.set(qn('w:val'), 'clear')
        shd.set(qn('w:color'), 'auto')
        shd.set(qn('w:fill'), '1A56DB')
        tcPr.append(shd)
    # Data rows
    for ri, row_data in enumerate(rows):
        row = t.rows[ri + 1]
        for ci, cell_text in enumerate(row_data):
            cell = row.cells[ci]
            cell.text = cell_text
            cell.paragraphs[0].runs[0].font.size = Pt(10)
            if ri % 2 == 1:
                tc = cell._tc
                tcPr = tc.get_or_add_tcPr()
                shd = OxmlElement('w:shd')
                shd.set(qn('w:val'), 'clear')
                shd.set(qn('w:color'), 'auto')
                shd.set(qn('w:fill'), 'F9FAFB')
                tcPr.append(shd)
    if col_widths:
        for ri, row in enumerate(t.rows):
            for ci, cell in enumerate(row.cells):
                cell.width = Cm(col_widths[ci])
    return t

def screenshot_placeholder(caption, height_cm=7):
    """Draws a gray bordered box as a screenshot placeholder."""
    # Use a 1-cell table as the box
    t = doc.add_table(rows=1, cols=1)
    t.style = 'Table Grid'
    cell = t.rows[0].cells[0]
    cell.height = Cm(height_cm)
    # Gray fill
    tc = cell._tc
    tcPr = tc.get_or_add_tcPr()
    shd = OxmlElement('w:shd')
    shd.set(qn('w:val'), 'clear')
    shd.set(qn('w:color'), 'auto')
    shd.set(qn('w:fill'), 'E5E7EB')
    tcPr.append(shd)
    p = cell.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run(f"[ SCREENSHOT: {caption} ]")
    run.font.color.rgb = GRAY
    run.font.italic = True
    run.font.size = Pt(10)
    doc.add_paragraph()  # spacer
    cap = doc.add_paragraph(f"Figure: {caption}")
    cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
    cap.runs[0].font.italic = True
    cap.runs[0].font.size = Pt(9)
    cap.runs[0].font.color.rgb = GRAY
    doc.add_paragraph()

def bullet(text, level=0):
    p = doc.add_paragraph(text, style='List Bullet')
    p.paragraph_format.left_indent = Cm(0.5 + level * 0.5)
    p.runs[0].font.size = Pt(10.5)
    return p

def hr():
    p = doc.add_paragraph()
    pPr = p._p.get_or_add_pPr()
    pb = OxmlElement('w:pBdr')
    bottom = OxmlElement('w:bottom')
    bottom.set(qn('w:val'), 'single')
    bottom.set(qn('w:sz'), '6')
    bottom.set(qn('w:space'), '1')
    bottom.set(qn('w:color'), 'D1D5DB')
    pb.append(bottom)
    pPr.append(pb)
    return p

# ══════════════════════════════════════════════════════════════════════════════
# COVER PAGE
# ══════════════════════════════════════════════════════════════════════════════

doc.add_paragraph()
doc.add_paragraph()
doc.add_paragraph()

title_p = doc.add_paragraph()
title_p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = title_p.add_run("BioMate")
run.font.size = Pt(40)
run.font.bold = True
run.font.color.rgb = BLUE

sub_p = doc.add_paragraph()
sub_p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = sub_p.add_run("User Manual")
run.font.size = Pt(22)
run.font.color.rgb = GRAY

doc.add_paragraph()
screenshot_placeholder("BioMate main interface — chat window, workflow card, and output panel", height_cm=9)

ver_p = doc.add_paragraph()
ver_p.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = ver_p.add_run("Version April 2026  •  For researchers, structural biologists, and drug discovery scientists")
run.font.size = Pt(10)
run.font.color.rgb = GRAY

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 1 — What is BioMate
# ══════════════════════════════════════════════════════════════════════════════

h1("1. What Is BioMate?")
body(
    "BioMate is a conversational AI platform for structural biology and life sciences research. "
    "You describe what you want to do in plain language, and BioMate understands your scientific goal, "
    "selects the right workflow from a library of 200+ validated bioinformatics pipelines, validates "
    "your inputs, runs the analysis, and shows you the results through interactive visualizations "
    "and downloadable files."
)
doc.add_paragraph()
body(
    "BioMate reasons like a domain expert — it knows when to use saposin versus MSP nanodisc, "
    "when local refinement is needed, when a functional assay is required before cryo-EM, and how "
    "to choose structure prediction tools based on your license situation."
)
doc.add_paragraph()
screenshot_placeholder("BioMate recognizing a scientific query and generating a workflow card", height_cm=7)

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 2 — Quick Start
# ══════════════════════════════════════════════════════════════════════════════

h1("2. Quick Start — Your First Analysis in 5 Minutes")

h3("Step 1 — Describe your experiment")
body("Type what you want to do in plain language:")
code_block('"I have raw cryo-EM movies of a membrane transporter in saposin nanodisc. I want to determine its structure."')
code_block('"Dock these 20 drug candidates into the ATP-binding pocket of my kinase structure."')
code_block('"Run germline variant calling on these WGS FASTQ files from a trio."')

h3("Step 2 — Answer clarifying questions (if any)")
body(
    "BioMate may ask one focused question to choose the right pipeline. "
    "Answer briefly — it will not ask for information you already provided."
)
screenshot_placeholder("BioMate asking one clarifying question about SPA vs cryo-ET", height_cm=4)

h3("Step 3 — Review the workflow card")
body("BioMate shows a workflow card with parameters, input slots, prerequisites, and expected outputs. Adjust any value directly.")
screenshot_placeholder("Workflow card with parameters, input slots, and Confirm & Run button", height_cm=7)

h3("Step 4 — Upload your files")
body("Drag and drop files, provide S3 paths, or give public accession numbers (SRR…, PDB ID, etc.).")

h3("Step 5 — Confirm & Run")
body("Click Confirm & Run. BioMate validates inputs, launches the pipeline, and shows real-time progress.")
screenshot_placeholder("Live progress timeline during workflow execution", height_cm=5)

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 3 — How to talk to BioMate
# ══════════════════════════════════════════════════════════════════════════════

h1("3. How to Talk to BioMate")

body(
    "BioMate is designed for natural, scientific language. You do not need to know workflow names "
    "or command syntax."
)
doc.add_paragraph()

table(
    ["Instead of…", "Say…"],
    [
        ["run cryosparc_standard_spa", "I have K3 movies of a GPCR-Gi complex in MSP nanodisc at 0.83 Å/pix. Determine the structure."],
        ["run alphafold3", "Predict the structure of this protein with its ATP ligand co-folded in."],
        ["run sarek", "Germline variant calling on these WGS FASTQ files from a trio (proband + parents)."],
        ["run gromacs --mode md", "Run 100 ns MD simulation on my top docking hit and calculate binding affinity."],
    ],
    col_widths=[5.5, 10.5]
)
doc.add_paragraph()

h3("Effective query patterns")
body("Include the key facts BioMate needs:")
bullet("Sample type (globular protein, membrane transporter, GPCR complex, viral capsid…)")
bullet("Sample preparation (saposin nanodisc, MSP nanodisc, detergent, liposome…)")
bullet("Data parameters (pixel size, voltage, dose) — for cryo-EM queries")
bullet("Scientific question (structure determination, drug binding, heterogeneity, signatures…)")

doc.add_paragraph()
body("Example of a complete, unambiguous query that runs without clarification:")
code_block(
    '"I have 2,000 tif movies from a 300 kV Titan Krios, 0.83 Å/pix, of CaV1.2 '
    'in GDN detergent (~400 kDa). Run full SPA and give me the final map."'
)

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 4 — Inputs
# ══════════════════════════════════════════════════════════════════════════════

h1("4. Inputs — What You Can Upload")

table(
    ["Category", "Accepted formats"],
    [
        ["Raw cryo-EM movies", ".tif, .mrc, .eer"],
        ["Electron density maps", ".mrc, .map"],
        ["Protein structures", ".pdb, .cif, .mmcif"],
        ["Sequences", ".fasta, .fa"],
        ["Short reads (genomics)", ".fastq, .fastq.gz, .bam, .cram"],
        ["Variant files", ".vcf, .vcf.gz"],
        ["Small molecules / ligands", ".sdf, .mol2, SMILES strings"],
        ["Tables / metadata", ".csv, .tsv, .xlsx"],
        ["Mass spectrometry", ".mzML, .mzXML"],
    ],
    col_widths=[5.5, 10.5]
)
doc.add_paragraph()

h3("Ways to provide inputs")
bullet("Drag and drop files directly into the chat window")
bullet("Type S3 paths: s3://my-bucket/my-data/movies/")
bullet("Type accession numbers: SRR1518169, PDB:6DDF, EMDB:1234")
bullet('Say "use the output from my last run" to chain workflows')

screenshot_placeholder("File upload dialog and accession number input", height_cm=4)

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 5 — Workflow Cards
# ══════════════════════════════════════════════════════════════════════════════

h1("5. Understanding Workflow Cards")

body(
    "When BioMate selects a workflow, it presents a workflow card before running anything. "
    "You can review, edit, and approve before any compute runs."
)
doc.add_paragraph()
screenshot_placeholder("Full workflow card: parameters, inputs, prerequisites, and outputs", height_cm=9)

h3("Editing parameters")
body("Click Edit Parameters, or describe the change in chat:")
code_block('"Change the pixel size to 0.649 and set total dose to 60 e−/Å²."')
code_block('"This sample is radiation-sensitive — reduce the dose to 40 e−/Å²."')

h3("Prerequisites")
body(
    "Blocked prerequisites (shown with a red ✗) must be resolved before the Run button enables. "
    "Common prerequisites:"
)
bullet("Missing input files — upload or provide a path")
bullet("License required — BioMate will guide you to add your license key")
bullet("Functional assay confirmation — for pore-forming proteins or GPCR complexes, BioMate asks you to confirm the sample is biologically active before cryo-EM")

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 6 — Running a Workflow
# ══════════════════════════════════════════════════════════════════════════════

h1("6. Running a Workflow")

table(
    ["Execution mode", "When used", "Speed"],
    [
        ["Mock / Dry-run", "No data provided, or explicitly requested", "Instant — synthetic outputs for testing"],
        ["Local", "Small datasets, development", "Minutes to hours"],
        ["Cloud (AWS Batch)", "Large datasets, GPU-intensive steps", "Scales automatically"],
    ],
    col_widths=[4, 7, 5]
)
doc.add_paragraph()
body('BioMate selects the mode automatically. Override by saying: "Run this locally" or "Submit to cloud."')
doc.add_paragraph()

h3("Pausing and resuming")
body("If a run is interrupted, BioMate resumes from the last completed step:")
code_block('"Resume my interrupted cryo-EM run."')

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 7 — Outputs and Visualization
# ══════════════════════════════════════════════════════════════════════════════

h1("7. Outputs and Visualization")

table(
    ["Output type", "How BioMate displays it"],
    [
        ["Protein structure (.pdb, .cif)", "Interactive 3D viewer — rotate, zoom, color by chain or property"],
        ["Electron density map (.mrc)", "2D slice viewer with contour control"],
        ["FSC curve", "Interactive chart — 0.143 resolution threshold highlighted"],
        ["Tables (.csv, .tsv, .json)", "Sortable, searchable table viewer"],
        ["Images (.png, .jpg)", "Inline image display"],
        ["Sequences (.fasta)", "Sequence viewer with annotation"],
        ["QC reports (.json, .html)", "Formatted summary with key metrics"],
    ],
    col_widths=[5.5, 10.5]
)
doc.add_paragraph()
screenshot_placeholder("Interactive 3D structure viewer with electron density map overlay", height_cm=7)
screenshot_placeholder("FSC curve chart with 0.143 threshold and resolution annotation", height_cm=6)

h3("Downloading outputs")
bullet("Click any output file to download it individually")
bullet("Download all outputs as a ZIP package")
bullet("Sync to your S3 bucket — BioMate generates the exact sync command")

screenshot_placeholder("Download panel showing output files, ZIP button, and cloud sync command", height_cm=5)

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 8 — Tracking Intermediate Steps
# ══════════════════════════════════════════════════════════════════════════════

h1("8. Tracking Intermediate Steps")

body(
    "BioMate shows real-time progress with per-step timing. "
    "Intermediate outputs are available as each step completes — "
    "you do not have to wait for the full pipeline."
)
doc.add_paragraph()
screenshot_placeholder("Step-by-step execution timeline with completed, running, and pending states", height_cm=6)

h3("Asking questions mid-run")
body("While a workflow runs, you can query the current state:")
code_block('"How many particles were picked in step 5?"')
code_block('"Show me the CTF quality plots."')
code_block('"The 2D classes look poor — should I change the box size?"')

h3("QC gates")
body(
    "Some pipelines have automatic QC gates that pause execution and show you the current "
    "quality metric before continuing:"
)
bullet("Reconstitution QC (cryo-EM nanodisc): validates NS-EM particle size and SEC peak shape")
bullet("Functional assay gate: confirms sample is biologically active before committing to data collection")
bullet("Low particle yield warning: warns if particle count is below the threshold for target resolution")
screenshot_placeholder("QC gate dialog showing NS-EM nanodisc size check with pass/fail result", height_cm=5)

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 9A — Cryo-EM SPA
# ══════════════════════════════════════════════════════════════════════════════

h1("9. Domain Tutorials")
h2("9A. Cryo-EM — Standard Single Particle Analysis")

body(
    "BioMate runs a full 23-step CryoSPARC SPA pipeline: motion correction → CTF estimation → "
    "particle picking (blob picker + TOPAZ deep learning) → 2D classification → ab-initio reconstruction → "
    "non-uniform refinement → local resolution → map sharpening → FSC validation."
)
doc.add_paragraph()
note("License: CryoSPARC requires a license (from Structura Biotechnology). You provide it once; BioMate reuses it automatically.")
doc.add_paragraph()

h3("Example query")
code_block(
    '"I have 3,000 movies of my 120 kDa ion channel in GDN detergent. '
    '300 kV, 0.83 Å/pix, 50 e−/Å², 50 frames. Run full SPA."'
)
doc.add_paragraph()

h3("Pixel size guide")
table(
    ["Sample type / molecular weight", "Pixel size"],
    [
        ["Protein < 60 kDa (e.g. saposin nanodisc)", "0.649 Å/pix"],
        ["Most membrane proteins, complexes 60–500 kDa", "0.83 Å/pix"],
        ["Large complexes 500–1,500 kDa", "1.06 Å/pix"],
        ["Viral capsids, ribosomes > 1,500 kDa", "1.30 Å/pix"],
    ],
    col_widths=[9, 7]
)
doc.add_paragraph()
note("Pixel size is the single most critical parameter — it is set at data collection and cannot be corrected afterward.")
doc.add_paragraph()

h3("Particle count targets")
table(
    ["Target resolution", "Minimum particles"],
    [
        ["4–5 Å (secondary structure visible)", "50,000"],
        ["3–4 Å (side chains resolved)", "100,000"],
        ["< 3 Å (high resolution)", "200,000+"],
    ],
    col_widths=[9, 7]
)
doc.add_paragraph()

h3("Key outputs")
bullet("final_map_sharpened.mrc — submission-ready map")
bullet("fsc_curve.png + fsc_data.csv — gold-standard FSC at 0.143")
bullet("local_resolution.mrc — per-voxel resolution estimate")
bullet("half_map_A.mrc, half_map_B.mrc — for EMDB deposition")
bullet("qc_report.json — machine-readable quality metrics")

screenshot_placeholder("Cryo-EM SPA workflow card showing all 23 steps and parameters", height_cm=7)
screenshot_placeholder("2D class averages showing secondary structure (helices visible)", height_cm=5)
screenshot_placeholder("Final 3D map in the density viewer with local resolution coloring", height_cm=6)

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 9B — Specialized Cryo-EM Protocols
# ══════════════════════════════════════════════════════════════════════════════

h2("9B. Cryo-EM — Specialized Protocols")

h3("Saposin Nanodisc SPA (membrane proteins < 60 kDa)")
body(
    "For small membrane proteins (transporters, channel subunits) that are too small to give "
    "good signal in standard conditions. Saposin A wraps tightly around the protein, creating a "
    "~10 nm disc with minimal background."
)
doc.add_paragraph()
body("Example:")
code_block('"My target is a 45 kDa lipid transporter reconstituted in saposin nanodisc. Run SPA."')
doc.add_paragraph()
body("What BioMate does differently:")
bullet("Enforces 0.649 Å/pix and 60 e−/Å² (you cannot accidentally use wrong values)")
bullet("Runs a reconstitution QC gate before data collection: validates NS-EM nanodisc size (~10 nm) and SEC peak")
bullet("Runs TOPAZ training on your dataset after initial 2D classification (critical for small, low-contrast particles)")
bullet("Generates a saposin reconstitution protocol card as a run output")

doc.add_paragraph()
screenshot_placeholder("Saposin nanodisc QC gate showing NS-EM particle size validation", height_cm=5)

hr()
doc.add_paragraph()

h3("GPCR-G Protein Complex SPA")
body(
    "For G protein-coupled receptors in complex with Gi, Gs, Gq, or arrestin, "
    "reconstituted in MSP1D1ΔH5 nanodisc (~120–150 kDa total)."
)
doc.add_paragraph()
body("Example:")
code_block(
    '"I have μ-opioid receptor in complex with Gi1, stabilized with scFv16, '
    'in MSP1D1ΔH5 nanodisc. DAMGO as agonist. Determine the structure."'
)
doc.add_paragraph()
body("What BioMate does differently:")
bullet("Validates complex assembly: scFv16 confirmed, nucleotide removed by apyrase, SEC shows stoichiometric peak")
bullet("Warns if scFv16 is missing for a Gi-coupled GPCR (complex yield drops 10x without it)")
bullet("Dual local refinement: separate focused refinements on the receptor TM bundle and the G protein")
bullet("Generates an assembly protocol card: expression, apyrase timing, MSP nanodisc reconstitution")

doc.add_paragraph()
screenshot_placeholder("GPCR complex assembly QC report: SEC peak, SDS-PAGE band check, scFv16 confirmation", height_cm=5)
screenshot_placeholder("Dual local refinement result: receptor TM domain (left) and G protein (right)", height_cm=6)

hr()
doc.add_paragraph()

h3("Multi-Drug Atlas (pharmacology studies)")
body(
    "Process apo reference + multiple drug-bound datasets through identical SPA pipelines, "
    "then generate drug-minus-apo difference maps at ±3σ to show where each drug binds."
)
doc.add_paragraph()
body("Example:")
code_block(
    '"I have CaV1.2 datasets with and without 7 calcium channel blockers. '
    'Generate a drug atlas showing each binding site."'
)
doc.add_paragraph()
body("Critical requirement: All datasets must share identical pixel size, defocus range, and dose.")
bullet("BioMate warns you if parameters differ across datasets")
bullet("Difference maps validated by occupancy check (reports if a drug has <60% occupancy)")
bullet("Output: side-by-side atlas comparing all drug binding sites")

doc.add_paragraph()
screenshot_placeholder("Multi-drug atlas: apo + 3 drug difference maps shown side by side", height_cm=7)

hr()
doc.add_paragraph()

h3("Conformational Heterogeneity — 3DVA")
body(
    "Resolve multiple conformational states from a single particle dataset. "
    "One collection session can yield 5–6 simultaneous structures showing a functional trajectory."
)
body("Example:")
code_block(
    '"I processed my spliceosome dataset. Now resolve the different '
    'activation states in the same particle stack using 3DVA."'
)
doc.add_paragraph()

h3("Cryo-ET (In-Cell / In-Situ)")
body(
    "For proteins that cannot be purified, or that you want to study in native cellular context. "
    "FIB-milled lamellae → tilt series → subtomogram averaging."
)
body("Example:")
code_block('"I have tilt series from FIB-milled lamellae. Run subtomogram averaging."')

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 9C — Drug Discovery
# ══════════════════════════════════════════════════════════════════════════════

h2("9C. Drug Discovery")

h3("Typical workflow")
body("BioMate can chain these steps automatically based on your goal:")
code_block(
    "Target structure (or predict)  →  Pocket detection  →  Docking\n"
    "→  ADMET screening  →  Lead optimization  →  MD / binding affinity"
)
doc.add_paragraph()
body("Full pipeline example:")
code_block(
    '"Screen these 50 compounds against my kinase structure for ATP-site binding, '
    'filter out hERG liabilities, and rank the survivors by docking score."'
)
doc.add_paragraph()

h3("Structure prediction")
body("If you do not have an experimental structure:")
code_block('"Predict the structure of this sequence and dock these ligands into the most likely pocket."')
doc.add_paragraph()
table(
    ["Prediction tool", "When to use"],
    [
        ["AlphaFold3", "State-of-the-art; handles ligand co-folding. Requires institutional account."],
        ["Boltz-2", "Open-weights, MIT license; comparable accuracy for most targets."],
        ["Chai-1", "No account required; fastest to run. Good for screening."],
    ],
    col_widths=[5, 11]
)
doc.add_paragraph()

h3("ADMET screening outputs")
table(
    ["Property", "Threshold (flag if…)"],
    [
        ["hERG IC₅₀ (cardiac safety)", "< 1 μM (cardiac liability)"],
        ["DILI (hepatotoxicity)", "Score > 0.5"],
        ["Ames mutagenicity", "Positive"],
        ["Blood-brain barrier", "logBB < −1 (CNS: insufficient penetration)"],
        ["Oral bioavailability", "F < 20%"],
    ],
    col_widths=[7, 9]
)
doc.add_paragraph()
screenshot_placeholder("ADMET results table with flagged compounds highlighted in red", height_cm=6)

h3("MD simulation and binding affinity")
code_block('"Run 100 ns GROMACS MD for my top 3 docked compounds. Calculate MM-GBSA binding affinity."')
doc.add_paragraph()
body("Outputs: RMSD/RMSF stability plots, ΔGbind estimate (kcal/mol), binding pose trajectory in viewer.")
screenshot_placeholder("MD trajectory RMSD plot and MM-GBSA binding affinity table", height_cm=6)

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 9D — Structural Biology
# ══════════════════════════════════════════════════════════════════════════════

h2("9D. Structural Biology — Prediction, Docking & Comparison")

h3("Compare two structures")
code_block('"Compare the apo and drug-bound structures of my channel. Show the RMSD and where it changes most."')
body("Output: superposition image, per-residue RMSD, TM-score, regions of largest deviation highlighted.")
doc.add_paragraph()

h3("Find all binding sites")
code_block('"Find all potential drug binding pockets on this GPCR structure."')
body("P2Rank scores all surface pockets by druggability (volume, hydrophobicity, conservation).")
doc.add_paragraph()

h3("Docking")
code_block('"Dock verapamil into the central cavity of this CaV1.2 structure."')
body("Outputs: top 5 poses ranked by score, 3D interactive viewer, predicted ΔGbind.")
screenshot_placeholder("3D docking pose viewer showing ligand in binding pocket", height_cm=7)

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 9E — Genomics
# ══════════════════════════════════════════════════════════════════════════════

h2("9E. Genomics — Variant Calling & RNA-seq")

h3("Germline variant calling")
code_block('"Germline variant calling on WGS FASTQ files from a trio (proband SRR1234, father SRR1235, mother SRR1236)."')
body("Pipeline: nf-core/sarek (GATK HaplotypeCaller) → de novo variant detection → VCF with inheritance patterns.")
body("Outputs: filtered VCF, annotated TSV (gene, consequence, gnomAD frequency), MultiQC HTML.")
doc.add_paragraph()

h3("Somatic variant calling")
code_block('"Somatic variant calling on matched tumor/normal WGS samples. Calculate TMB."')
body("Pipeline: Mutect2 (matched pair) → NMF mutational signature decomposition → TMB (mut/Mb).")
note("Always provide matched normal. Tumor-only mode has higher false discovery rate.")
doc.add_paragraph()

h3("RNA-seq differential expression")
code_block('"3 treated vs 3 control RNA-seq samples. Find DE genes and enriched pathways."')
body("Outputs: DE gene table (log2FC, adjusted p-value), volcano plot, PCA, GO/KEGG pathway enrichment.")
screenshot_placeholder("Volcano plot of differentially expressed genes, labeled top hits", height_cm=6)

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 10 — Licenses
# ══════════════════════════════════════════════════════════════════════════════

h1("10. Licenses and Credentials")

body(
    "Some tools require institutional or personal licenses. BioMate manages credentials securely. "
    "You add a license once; it is reused automatically for all future runs."
)
doc.add_paragraph()

table(
    ["Tool", "License type", "Open-source alternative"],
    [
        ["CryoSPARC", "License key (Structura Bio). Each user needs own key.", "RELION (fully open-source SPA)"],
        ["Schrödinger Glide", "License server URL (institutional)", "AutoDock Vina, DiffDock"],
        ["MOE Covalent Docking", "License server URL (Chemical Computing Group)", "AutoDock Vina + custom warhead"],
        ["AlphaFold3", "Docker account (alphafold.ebi.ac.uk)", "Boltz-2 (MIT), Chai-1 (Apache 2.0)"],
        ["AMBER pmemd", "AMBER license agreement", "GROMACS (GPL)"],
    ],
    col_widths=[4.5, 6, 5.5]
)
doc.add_paragraph()
screenshot_placeholder("License gate dialog showing how to add a CryoSPARC license key", height_cm=4)

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# SECTION 11 — Tips
# ══════════════════════════════════════════════════════════════════════════════

h1("11. Tips and Best Practices")

h3("Provide context upfront")
body("The more you tell BioMate, the fewer clarifying questions it asks and the better parameters it sets.")
bullet("Molecular weight or complex composition")
bullet("Sample preparation method (nanodisc type, detergent, stabilizer)")
bullet("Data collection parameters (pixel size, voltage, dose) if already collected")
bullet("Scientific question: structure, mechanism, drug binding, heterogeneity, signatures")

h3("Never skip the functional assay")
body(
    "For membrane proteins, GPCRs, and pore-forming proteins: confirm your sample is functional "
    "before cryo-EM data collection. Non-functional samples produce poor 2D classes regardless of data quality."
)
bullet("Transport assay for transporters (radioactive or fluorescent)")
bullet("Patch clamp or flux assay for ion channels")
bullet("ANTS/DPX lysis assay for pore-forming proteins (>50% lysis required)")
bullet("BRET or cAMP assay for GPCR signaling")

h3("Validate by NS-EM before cryo-EM")
body(
    "Negative stain EM takes 1–2 hours and prevents wasted cryo-EM sessions. "
    "BioMate's reconstitution QC step can analyze your NS-EM image automatically. "
    "Expected nanodisc size: saposin ~10 nm, MSP1D1ΔH5 ~9 nm."
)

h3("For multi-drug studies: collect apo first")
body(
    "Collect and process the apo dataset before drug datasets. Use the apo structure for template-based "
    "picking in drug datasets, and as the reference for difference map subtraction. "
    "All datasets must use identical pixel size, defocus, and dose."
)

h3("Use intermediate outputs to make decisions")
body(
    "After 2D classification, inspect the classes before committing to full refinement. "
    'Ask BioMate: "The 2D classes look blurry — what should I try?" '
    "BioMate will suggest adjustments (concentration, blot conditions, detergent, or re-picking)."
)

doc.add_paragraph()
hr()
doc.add_paragraph()

h2("Common Failure Modes and Solutions")
table(
    ["Symptom", "Likely cause", "What to do"],
    [
        ["2D classes are featureless", "Sample aggregated or wrong concentration", "Optimize by NS-EM; try lower protein concentration"],
        ["CTF estimation fails", "Thick ice or wrong pixel size", "Check pixel size in acquisition software metadata"],
        ["Very few particles", "Blob picker parameters wrong for your particle size", "Switch to TOPAZ; adjust particle diameter estimate"],
        ["Resolution plateaus at 4–5 Å", "Too few particles or preferred orientation", "Collect more; try tilted stage"],
        ["Drug difference map shows no density", "Low occupancy or mismatched collection params", "Check drug Kd; verify identical collection parameters"],
        ["MolProbity > 2.5", "Map resolution insufficient or clashes in model", "Collect more data; run additional refinement cycles"],
    ],
    col_widths=[4, 5.5, 6.5]
)

doc.add_paragraph()
doc.add_paragraph()
footer_p = doc.add_paragraph("BioMate — developed by the BioMate team  •  April 2026")
footer_p.alignment = WD_ALIGN_PARAGRAPH.CENTER
footer_p.runs[0].font.color.rgb = GRAY
footer_p.runs[0].font.size = Pt(9)

# ── Save ──────────────────────────────────────────────────────────────────────
doc.save(OUT)
print(f"Saved: {OUT}")
