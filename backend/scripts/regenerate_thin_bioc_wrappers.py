#!/usr/bin/env python3
"""
Regenerate thin Bioconductor Nextflow wrappers from their source vignettes.

A "thin" wrapper has 0 or 1 real step sections (# --- Step Name [] ---).
This script:
  1. Reads /tmp/thin_ranked.txt (packages sorted by 2025 download rank)
  2. For each package: reads Source URL from main.nf
  3. Fetches the vignette R file from Bioconductor
  4. Parses chunks into logical workflow steps
  5. Rewrites the script block in main.nf with proper step annotations

Usage:
    cd /Users/kky/biomate/backend
    python3 scripts/regenerate_thin_bioc_wrappers.py [--limit N] [--pkg PKGNAME]
"""

import re
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path
from typing import List, Tuple, Optional

BIOC_DIR = Path("/Users/kky/biomate/backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor")
RANKED_FILE = Path("/tmp/thin_ranked.txt")

# ── Chunk name → human-readable step name ────────────────────────────────────

WORD_REPLACEMENTS = {
    "sce": "SCE", "scrnaseq": "scRNA-seq", "rnaseq": "RNA-seq",
    "qc": "Quality Control", "pca": "PCA", "umap": "UMAP", "tsne": "t-SNE",
    "de": "Differential Expression", "deg": "DEG", "dea": "DEA",
    "go": "GO", "kegg": "KEGG", "gsea": "GSEA",
    "db": "Database", "io": "I/O", "api": "API",
    "se": "SummarizedExperiment", "gr": "GRanges",
    "tx": "Transcript", "bs": "BSgenome", "grl": "GRangesList",
}

def chunk_name_to_step(name: str) -> str:
    """Convert camelCase or snake_case chunk name to a readable step name."""
    # Replace underscores/dots with spaces
    name = re.sub(r'[_\-.]', ' ', name)
    # Split camelCase
    name = re.sub(r'([a-z])([A-Z])', r'\1 \2', name)
    # Title case
    words = name.strip().split()
    result = []
    for w in words:
        wl = w.lower()
        if wl in WORD_REPLACEMENTS:
            result.append(WORD_REPLACEMENTS[wl])
        else:
            result.append(w.capitalize())
    return " ".join(result)


# ── Vignette fetching ─────────────────────────────────────────────────────────

def fetch_url(url: str, retries: int = 3) -> Optional[str]:
    """Fetch URL, return text or None on failure."""
    headers = {"User-Agent": "Mozilla/5.0 BioMate-KB/1.0"}
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=20) as resp:
                raw = resp.read()
                try:
                    return raw.decode("utf-8")
                except UnicodeDecodeError:
                    return raw.decode("latin-1")
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            time.sleep(1)
        except Exception:
            time.sleep(1)
    return None


def parse_html_vignette(html_text: str) -> List[Tuple[str, str]]:
    """
    Parse code blocks from an HTML vignette.
    Returns list of (auto_name, code) tuples.
    """
    # Strip HTML entities
    html_text = html_text.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&").replace("&quot;", '"').replace("&#39;", "'")

    chunks = []
    # Extract code blocks from <pre><code> sections
    code_blocks = re.findall(r'<pre[^>]*><code[^>]*>(.*?)</code></pre>', html_text, re.DOTALL)
    for i, block in enumerate(code_blocks):
        # Strip remaining HTML tags
        code = re.sub(r'<[^>]+>', '', block).strip()
        if code and len(code) > 10:
            # Filter out R output lines (## output, session info, pure comment lines)
            lines = code.split('\n')
            r_lines = [l for l in lines
                       if l.strip()
                       and not re.match(r'^##\s+[A-Z]\s+[-\d\. ]', l.strip())   # matrix output
                       and not re.match(r'^##\s+R version', l.strip())           # session info
                       and not re.match(r'^##\s+Platform:', l.strip())]
            if r_lines:
                chunks.append((f"block_{i+1}", '\n'.join(r_lines)))

    return chunks


def fetch_html_vignette(pkg_canonical: str) -> Optional[List[Tuple[str, str]]]:
    """Try to fetch the HTML vignette for a package and parse code blocks."""
    pkg_page = fetch_url(f"https://bioconductor.org/packages/3.20/bioc/html/{pkg_canonical}.html")
    if not pkg_page:
        return None

    # Find vignette HTML links
    links = re.findall(r'href="([^"]*\.html)"', pkg_page)
    vignette_links = [l for l in links if 'inst/doc' in l or 'vignette' in l.lower()]

    pkg_page_base = f"https://bioconductor.org/packages/3.20/bioc/html/"
    for link in vignette_links[:3]:  # try up to 3 HTML vignettes
        if link.startswith("http"):
            url = link
        elif link.startswith("../"):
            # Resolve relative to the html/ directory: ../vignettes/... → /packages/3.20/bioc/vignettes/...
            url = f"https://bioconductor.org/packages/3.20/bioc/{link[3:]}"
        else:
            url = f"https://bioconductor.org{link}"

        html = fetch_url(url)
        if html:
            chunks = parse_html_vignette(html)
            if chunks:
                return chunks
    return None


def discover_vignette_url(pkg_lower: str, pkg_canonical: str) -> Optional[str]:
    """Try multiple URL patterns for a package's vignette R file."""
    base = f"https://bioconductor.org/packages/3.20/bioc/vignettes/{pkg_canonical}/inst/doc/"

    # Try common patterns
    candidates = [
        f"{base}{pkg_canonical}.R",
        f"{base}{pkg_lower}.R",
        f"{base}{pkg_canonical}Vignette.R",
        f"{base}{pkg_lower}vignette.R",
        f"{base}{pkg_canonical}Tutorial.R",
        f"{base}introduction.R",
        f"{base}vignette.R",
        f"{base}overview.R",
    ]

    # Also try the Bioconductor HTML vignette listing to find the right URL
    listing_url = f"https://bioconductor.org/packages/3.20/bioc/html/{pkg_canonical}.html"
    html = fetch_url(listing_url)
    if html:
        # Extract .R vignette links from the package HTML page
        r_links = re.findall(
            r'href="[^"]*vignettes/[^"]*\.R"', html, re.IGNORECASE
        )
        for link in r_links:
            url = re.search(r'href="([^"]+)"', link).group(1)
            if url.startswith("http"):
                candidates.insert(0, url)
            else:
                candidates.insert(0, f"https://bioconductor.org{url}")

    for url in candidates:
        content = fetch_url(url)
        if content and len(content) > 100:
            return url
    return None


# ── Vignette chunk parsing ────────────────────────────────────────────────────

def parse_r_vignette(text: str) -> List[Tuple[str, str]]:
    """
    Parse a compiled R vignette (.R file from knitr).
    Returns list of (chunk_name, code) tuples.

    Supports:
      .Rnw format: ## ----chunkname,opts----- or ### code chunk number N: name
      .Rmd format: ## ----chunkname,opts-------
    """
    chunks = []

    # Pattern 1: Rmd/Rnw compiled format — ## ----name,...---
    pattern_rmd = re.compile(
        r'^## ----([^,\n-][^\n-]*?)(?:,.*?)?-{3,}\s*$',
        re.MULTILINE
    )

    # Pattern 2: Rnw compiled format — ### code chunk number N: name
    pattern_rnw_header = re.compile(
        r'^#{2,4}\s+(?:code chunk number \d+:\s*)?([a-zA-Z]\w*)\s*$',
        re.MULTILINE
    )

    # Pattern 3: Rnw separator lines (### followed by ###)
    pattern_rnw_sep = re.compile(
        r'^#{3,}\s*$', re.MULTILINE
    )

    # Detect format
    if pattern_rmd.search(text):
        # Rmd compiled format
        parts = pattern_rmd.split(text)
        # parts: [pre, name1, code1, name2, code2, ...]
        for i in range(1, len(parts) - 1, 2):
            name = parts[i].strip()
            code = parts[i + 1].strip() if i + 1 < len(parts) else ""
            chunks.append((name, code))

    elif "code chunk number" in text:
        # Classic Rnw format
        # Split by separator lines
        sections = pattern_rnw_sep.split(text)
        i = 0
        while i < len(sections):
            sec = sections[i].strip()
            if i + 1 < len(sections):
                # Check if this section is a header
                header_m = re.match(r'^#{2,4}\s+(?:code chunk number \d+:\s*)?(\w+)\s*$', sec)
                if header_m:
                    name = header_m.group(1)
                    code = sections[i + 1].strip() if i + 1 < len(sections) else ""
                    chunks.append((name, code))
                    i += 2
                    continue
            i += 1

    else:
        # Fallback: split by ## ---- or similar comment headers
        lines = text.split("\n")
        current_name = "main"
        current_code = []
        for line in lines:
            m = re.match(r'^##\s*[-=]+\s*(.+?)\s*[-=]*\s*$', line)
            if m:
                if current_code:
                    chunks.append((current_name, "\n".join(current_code).strip()))
                current_name = m.group(1).strip()
                current_code = []
            else:
                current_code.append(line)
        if current_code:
            chunks.append((current_name, "\n".join(current_code).strip()))

    return chunks


# ── Step filtering ────────────────────────────────────────────────────────────

# Chunk names that are purely setup/configuration — skip or merge
SKIP_NAMES_PATTERNS = [
    r'^style$', r'^setup$', r'^config$', r'^options$', r'^knitr',
    r'^echo', r'^message', r'^fig\.', r'^opts', r'^libs$',
    r'^suppress', r'^session[_\s]?info', r'^sessionInfo',
    r'^toLatex', r'^install', r'^help$', r'^R\.version',
]

SKIP_CODE_PATTERNS = [
    r'knitr::opts_chunk',
    r'options\(width',
    r'options\(continue',
    r'BiocManager::install',
    r'^library\(\w+\)\s*$',
    r'^require\(\w+\)\s*$',
    r'^suppressMessages',
    r'^suppressWarnings',
    r'^set\.seed',
    r'sessionInfo\(\)',
    r'toLatex\(sessionInfo',
    r'packageVersion',
]

def is_skip_chunk(name: str, code: str) -> bool:
    """Return True if this chunk should be skipped (setup/config/trivial)."""
    nl = name.lower()
    for pat in SKIP_NAMES_PATTERNS:
        if re.search(pat, nl, re.IGNORECASE):
            return True

    code_stripped = code.strip()
    if not code_stripped:
        return True

    # If ALL lines match skip patterns, skip
    non_comment_lines = [l for l in code_stripped.split("\n")
                         if l.strip() and not l.strip().startswith("#")]
    if not non_comment_lines:
        return True

    substantive = [l for l in non_comment_lines
                   if not any(re.search(p, l) for p in SKIP_CODE_PATTERNS)]
    if not substantive:
        return True

    # Skip if code is only library() or require() calls
    if all(re.match(r'(?:library|require)\s*\(', l.strip()) for l in non_comment_lines):
        return True

    return False


def extract_key_functions(code: str, pkg_name: str) -> List[str]:
    """Extract likely key function names from R code."""
    # Match function calls: identifier followed by (
    candidates = re.findall(r'\b([a-zA-Z][a-zA-Z0-9_.]+)\s*(?=\()', code)

    # Also extract quoted strings that look like function names (e.g., in matrices listing API)
    # e.g., "collapse", "expand", "groupOTU" in documentation tables
    quoted = re.findall(r'"([a-zA-Z][a-zA-Z0-9_.]+)"', code)
    candidates.extend([q for q in quoted if '_' in q or q[0].islower()])

    # Filter: remove base R, common utilities, lowercase single words
    base_r = {
        'c', 'list', 'data', 'data.frame', 'matrix', 'head', 'tail',
        'print', 'cat', 'message', 'warning', 'stop', 'return',
        'paste', 'paste0', 'sprintf', 'format', 'nchar', 'toupper', 'tolower',
        'which', 'any', 'all', 'sum', 'mean', 'sd', 'var', 'median',
        'min', 'max', 'range', 'length', 'nrow', 'ncol', 'dim', 'names',
        'colnames', 'rownames', 'as.character', 'as.numeric', 'as.integer',
        'as.logical', 'as.factor', 'as.data.frame', 'as.matrix', 'as.list',
        'is.na', 'is.null', 'is.numeric', 'is.character', 'is.factor',
        'apply', 'lapply', 'sapply', 'tapply', 'mapply', 'Map',
        'subset', 'merge', 'rbind', 'cbind', 'table', 'sort', 'order',
        'unique', 'duplicated', 'rev', 'seq', 'seq_len', 'seq_along',
        'Reduce', 'Filter', 'intersect', 'union', 'setdiff',
        'tryCatch', 'try', 'on.exit', 'local', 'eval', 'parse',
        'system.file', 'file.path', 'read.csv', 'write.csv', 'readRDS', 'saveRDS',
        'library', 'require', 'install.packages',
        'knitr', 'kable', 'options', 'set.seed',
        'suppressMessages', 'suppressWarnings', 'requireNamespace',
        'factor', 'levels', 'relevel', 'droplevels', 'interaction',
        'Sys.time', 'proc.time', 'date', 'format.Date',
        'sprintf', 'format', 'strsplit', 'grep', 'grepl', 'sub', 'gsub',
        'regexpr', 'regmatches', 'startsWith', 'endsWith',
        'writeLines', 'readLines', 'scan', 'readline',
        'invisible', 'identity', 'do.call',
        'environment', 'parent.env', 'new.env', 'assign', 'get', 'exists',
        'round', 'floor', 'ceiling', 'abs', 'sqrt', 'exp', 'log', 'log2', 'log10',
        'cor', 'cor.test', 't.test', 'wilcox.test', 'chisq.test', 'fisher.test',
        'lm', 'glm', 'anova', 'aov', 'residuals', 'fitted', 'coef',
        'ggplot', 'aes', 'geom_point', 'geom_line', 'geom_bar', 'geom_boxplot',
        'geom_histogram', 'geom_density', 'geom_violin', 'geom_heatmap',
        'theme', 'theme_bw', 'theme_classic', 'scale_color_manual',
        'facet_wrap', 'facet_grid', 'labs', 'ggtitle', 'xlab', 'ylab',
        'ggsave', 'pdf', 'png', 'dev.off', 'plot', 'points', 'lines', 'legend',
        'barplot', 'boxplot', 'hist', 'image',
    }
    seen = set()
    result = []
    for f in candidates:
        fl = f.lower()
        if fl not in base_r and f not in seen and len(f) > 2:
            seen.add(f)
            result.append(f)
    return result[:8]  # cap at 8 key functions


def group_chunks_into_steps(
    chunks: List[Tuple[str, str]], pkg_name: str, max_steps: int = 6
) -> List[Tuple[str, str, List[str]]]:
    """
    Filter and group chunks into workflow steps.
    Returns list of (step_name, combined_code, key_functions).
    """
    # Filter trivial chunks
    filtered = [(name, code) for name, code in chunks if not is_skip_chunk(name, code)]

    if not filtered:
        return []

    # Trim code to reasonable length, never cutting inside an open expression.
    def trim_code(code: str, max_lines: int = 15) -> str:
        lines = code.strip().split("\n")
        if len(lines) <= max_lines:
            return code.strip()
        # Walk up to max_lines (then up to +20 more) tracking bracket depth.
        # Only cut at a line where depth == 0 (complete expression boundary).
        depth = 0
        last_safe = 0  # last index (exclusive) where depth dropped back to 0
        for i, line in enumerate(lines):
            depth += line.count('(') + line.count('[') + line.count('{')
            depth -= line.count(')') + line.count(']') + line.count('}')
            if depth <= 0:
                depth = 0
                last_safe = i + 1
            if i + 1 >= max_lines and depth == 0:
                break  # reached target length at a safe boundary
            if i + 1 >= max_lines + 20:
                break  # give up extending; use last safe point found
        cut = last_safe if last_safe > 0 else max_lines
        return "\n".join(lines[:cut])

    # If few chunks, keep them all as separate steps
    if len(filtered) <= max_steps:
        steps = []
        for name, code in filtered:
            step_name = chunk_name_to_step(name)
            code_trimmed = trim_code(code)
            fns = extract_key_functions(code_trimmed, pkg_name)
            steps.append((step_name, code_trimmed, fns))
        return steps

    # Group consecutive chunks into max_steps groups
    group_size = max(1, len(filtered) // max_steps)
    steps = []
    i = 0
    while i < len(filtered) and len(steps) < max_steps:
        group = filtered[i:i + group_size]
        # Use the first chunk's name for the step
        step_name = chunk_name_to_step(group[0][0])
        combined_code = "\n".join(trim_code(code, 10) for _, code in group)
        combined_code = trim_code(combined_code, 20)
        fns = []
        for _, code in group:
            fns.extend(extract_key_functions(code, pkg_name))
        # Deduplicate functions
        seen = set()
        fns_dedup = []
        for f in fns:
            if f not in seen:
                seen.add(f)
                fns_dedup.append(f)
        steps.append((step_name, combined_code, fns_dedup[:8]))
        i += group_size

    return steps


# ── main.nf regeneration ──────────────────────────────────────────────────────

def extract_header_section(content: str) -> str:
    """Extract the header (comment block + process setup) from main.nf."""
    # Everything up to and including the """ (triple-quote script block start)
    m = re.search(r'^(\s*"""\s*$)', content, re.MULTILINE)
    if m:
        return content[:m.end()]
    return content


def extract_footer_section(content: str) -> str:
    """Extract the footer section (Save outputs + versions + stub + workflow block)."""
    # Find the last substantive step marker, then grab save outputs onward
    save_marker = re.search(r'\n\s*# --- Save outputs ---', content)
    if save_marker:
        return content[save_marker.start():]

    # Fallback: find the closing """
    m = re.search(r'\n\s*"""\s*\n', content)
    if m:
        return content[m.start():]
    return ""


def build_step_blocks(steps: List[Tuple[str, str, List[str]]], pkg_name: str) -> str:
    """Build the step annotation blocks for the script section."""
    blocks = []
    for step_name, code, fns in steps:
        fn_list = ", ".join(fns) if fns else pkg_name
        block = f"    # --- {step_name} [] ---\n"
        block += f"    # Key functions: {fn_list}\n"
        # Indent code by 4 spaces
        for line in code.split("\n"):
            block += f"    {line}\n" if line.strip() else "\n"
        blocks.append(block)
    return "\n".join(blocks)


def get_library_lines(content: str, pkg_name: str) -> str:
    """
    Build properly indented library() lines for the script block.
    Uses only the Install: comment to determine canonical package name —
    does NOT scrape library() calls from old (possibly broken) step code.
    """
    # Get canonical package name from Install: BiocManager::install("PkgName")
    install_m = re.search(r'BiocManager::install\("([^"]+)"\)', content)
    canonical = install_m.group(1) if install_m else pkg_name.capitalize()

    return f"    library({canonical})\n    library(jsonlite)\n\n"


def regenerate_main_nf(pkg_lower: str, steps: List[Tuple[str, str, List[str]]]) -> Optional[str]:
    """
    Regenerate the script block in main.nf with proper step annotations.
    Returns the new content, or None if regeneration fails.
    """
    nf_path = BIOC_DIR / pkg_lower / "main.nf"
    if not nf_path.exists():
        return None

    content = nf_path.read_text()

    # Find script block bounds
    script_start = re.search(r'\n\s*"""\s*\n\s*#!/usr/bin/env Rscript', content)
    if not script_start:
        return None

    # Find the matching closing """
    script_content_start = script_start.start()
    # Look for the footer section (Save outputs block)
    save_m = re.search(r'\n    # --- Save outputs ---', content)
    if not save_m:
        return None

    # Extract parts
    before_steps = content[:script_start.end()]  # up to #!/usr/bin/env Rscript

    # Get library lines from current content (full file for context)
    lib_lines = get_library_lines(content, pkg_lower)

    # Build new script block
    new_script = "\n" + lib_lines + "\n"
    new_script += build_step_blocks(steps, pkg_lower)

    # Get footer (from Save outputs to end)
    footer = content[save_m.start():]

    new_content = before_steps + new_script + footer
    return new_content


# ── Main ──────────────────────────────────────────────────────────────────────

def process_package(pkg_lower: str) -> Tuple[str, str]:
    """
    Process one thin package. Returns (pkg_lower, status).
    Status: 'ok:N', 'no_url', 'no_vignette', 'no_chunks', 'write_fail'
    """
    nf_path = BIOC_DIR / pkg_lower / "main.nf"
    if not nf_path.exists():
        return (pkg_lower, "no_nf_file")

    content = nf_path.read_text()

    # Extract source URL
    url_m = re.search(r'// Source\s*:\s*(https?://\S+)', content)
    if not url_m:
        return (pkg_lower, "no_url")

    source_url = url_m.group(1)

    # Extract canonical package name from Source URL
    # URL format: .../packages/3.20/bioc/vignettes/PkgName/inst/doc/...
    #              idx:                              7
    url_parts = source_url.split("/")
    pkg_canonical = url_parts[7] if len(url_parts) > 7 else pkg_lower

    # Fetch vignette
    vignette_text = fetch_url(source_url)
    if not vignette_text or len(vignette_text) < 50:
        # Try to discover alternative URL
        alt_url = discover_vignette_url(pkg_lower, pkg_canonical)
        if alt_url:
            vignette_text = fetch_url(alt_url)

    if not vignette_text or len(vignette_text) < 50:
        return (pkg_lower, "no_vignette")

    # Parse chunks from R vignette
    chunks = parse_r_vignette(vignette_text)

    # Group into steps
    steps = group_chunks_into_steps(chunks, pkg_lower)

    # Fallback: try HTML vignette parsing
    if not steps:
        html_chunks = fetch_html_vignette(pkg_canonical)
        if html_chunks:
            steps = group_chunks_into_steps(html_chunks, pkg_lower)

    if not steps:
        return (pkg_lower, "no_chunks")

    # Regenerate main.nf
    new_content = regenerate_main_nf(pkg_lower, steps)
    if not new_content:
        return (pkg_lower, "write_fail")

    nf_path.write_text(new_content)
    return (pkg_lower, f"ok:{len(steps)}")


def count_real_steps(nf_path: Path) -> int:
    """
    Count # --- Step Name [] --- sections.
    Also returns 99 for manually-crafted wrappers that have substantial R code
    but don't use the template pattern (no # --- Save outputs --- marker).
    """
    if not nf_path.exists():
        return 0
    content = nf_path.read_text()
    steps = re.findall(r'# --- .+ \[\] ---', content)
    if steps:
        return len(steps)
    # Check for manually-crafted wrapper: has Rscript block, lacks template markers,
    # but has substantial code (>15 lines in script block)
    script_m = re.search(r'#!/usr/bin/env Rscript\n(.*?)(?:\n    """\n|\Z)', content, re.DOTALL)
    if script_m:
        r_code = script_m.group(1)
        code_lines = [l for l in r_code.split('\n') if l.strip() and not l.strip().startswith('#')]
        if len(code_lines) > 15 and '# --- Save outputs ---' not in content:
            return 99  # manually crafted, don't touch
    return 0


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Regenerate thin Bioconductor wrappers")
    parser.add_argument("--limit", type=int, default=None, help="Process only N packages")
    parser.add_argument("--pkg", type=str, default=None, help="Process only this package (lowercase)")
    parser.add_argument("--dry-run", action="store_true", help="Fetch + parse but don't write")
    parser.add_argument("--force", action="store_true", help="Re-process even if ≥2 steps already exist")
    args = parser.parse_args()

    # Load ranked list
    if not RANKED_FILE.exists():
        print(f"❌ Ranked file not found: {RANKED_FILE}")
        sys.exit(1)

    ranked = []
    with open(RANKED_FILE) as f:
        for line in f:
            parts = line.strip().split("\t")
            if parts:
                ranked.append(parts[0].lower())

    if args.pkg:
        ranked = [args.pkg]
    elif args.limit:
        ranked = ranked[:args.limit]

    print(f"Processing {len(ranked)} packages...")

    ok_count = 0
    skip_count = 0
    fail_count = 0

    for i, pkg in enumerate(ranked, 1):
        # Check if already has 2+ real steps (skip unless forced)
        nf_path = BIOC_DIR / pkg / "main.nf"
        if not args.force and nf_path.exists() and count_real_steps(nf_path) >= 2:
            skip_count += 1
            continue

        print(f"  [{i:3d}/{len(ranked)}] {pkg}: ", end="", flush=True)

        if args.dry_run:
            url_m = re.search(r'// Source\s*:\s*(https?://\S+)', nf_path.read_text()) if nf_path.exists() else None
            if url_m:
                text = fetch_url(url_m.group(1))
                chunks = parse_r_vignette(text) if text else []
                steps = group_chunks_into_steps(chunks, pkg) if chunks else []
                print(f"dry-run: {len(chunks)} chunks → {len(steps)} steps")
            else:
                print("no_url")
            continue

        pkg_lower, status = process_package(pkg)

        if status.startswith("ok:"):
            n = status.split(":")[1]
            print(f"✓ {n} steps written")
            ok_count += 1
        else:
            print(f"✗ {status}")
            fail_count += 1

        # Be polite to Bioconductor servers
        time.sleep(0.5)

    print(f"\nDone: {ok_count} updated, {skip_count} already ok, {fail_count} failed")


if __name__ == "__main__":
    main()
