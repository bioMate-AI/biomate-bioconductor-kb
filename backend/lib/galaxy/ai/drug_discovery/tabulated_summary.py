"""
ICH M4S(R2) §2.6.7 tabulated-summary verifier — checker A2 from FDA reviewer
checklist v2.

Encodes the 5 highest-impact §2.6.7 templates (out of 34) as required-column
specifications, with a markdown-table parser and a column-presence verifier.

Templates encoded:
  2.6.7.7  — Repeat-Dose Toxicity
  2.6.7.8  — Genotoxicity: In Vitro
  2.6.7.9  — Genotoxicity: In Vivo
  2.6.7.10 — Carcinogenicity
  2.6.7.11 — Reproductive and Developmental Toxicity

Reference: ICH M4S(R2) Section 4 (templates), CTD Module 2.6.7 examples.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

# Required columns per template. Header matching is fuzzy (case-insensitive,
# substring). Column order is enforced.
TEMPLATE_COLUMNS: dict[str, list[str]] = {
    "2.6.7.7": [
        "study", "species", "method of administration",
        "duration", "doses", "noael", "findings",
    ],
    "2.6.7.8": [
        "study", "test system", "concentration", "metabolic activation",
        "result",
    ],
    "2.6.7.9": [
        "study", "species", "method of administration",
        "doses", "result",
    ],
    "2.6.7.10": [
        "study", "species", "method of administration",
        "duration", "doses", "tumor findings", "noael",
    ],
    "2.6.7.11": [
        "study", "species", "method of administration",
        "doses", "noael", "developmental findings",
    ],
}

TEMPLATE_NAMES: dict[str, str] = {
    "2.6.7.7":  "Repeat-Dose Toxicity",
    "2.6.7.8":  "Genotoxicity: In Vitro",
    "2.6.7.9":  "Genotoxicity: In Vivo",
    "2.6.7.10": "Carcinogenicity",
    "2.6.7.11": "Reproductive and Developmental Toxicity",
}


@dataclass
class TabulatedResult:
    template_id: str
    has_table: bool
    found_headers: list[str] = field(default_factory=list)
    missing_columns: list[str] = field(default_factory=list)
    out_of_order: list[tuple[str, str]] = field(default_factory=list)
    n_data_rows: int = 0

    @property
    def passed(self) -> bool:
        return (self.has_table
                and not self.missing_columns
                and not self.out_of_order
                and self.n_data_rows >= 1)


def parse_markdown_table(text: str) -> tuple[list[str], list[list[str]]] | None:
    """
    Find first markdown table in text. Returns (headers, data_rows) or None.
    Markdown table format:
        | col1 | col2 |
        |------|------|
        | a    | b    |
    """
    lines = [ln.strip() for ln in text.splitlines() if "|" in ln]
    if len(lines) < 3:
        return None
    # Header is first line; separator is second line (---|---|---).
    header_line = lines[0]
    sep_line = lines[1]
    if not re.match(r"^\|?[\s|:-]+\|?$", sep_line):
        return None
    headers = [c.strip().lower() for c in header_line.strip("|").split("|")]
    headers = [h for h in headers if h]

    data: list[list[str]] = []
    for ln in lines[2:]:
        cells = [c.strip() for c in ln.strip("|").split("|")]
        if any(cells):
            data.append(cells)
    return headers, data


def verify_table(text: str, template_id: str) -> TabulatedResult:
    required = TEMPLATE_COLUMNS.get(template_id)
    if required is None:
        raise ValueError(f"Unknown template {template_id}")

    parsed = parse_markdown_table(text)
    if parsed is None:
        return TabulatedResult(template_id=template_id, has_table=False,
                                missing_columns=required)

    headers, data = parsed

    # Match each required column to some header (substring, case-insensitive).
    found_indices: list[int] = []
    missing: list[str] = []
    for req in required:
        idx = next((i for i, h in enumerate(headers) if req in h), -1)
        if idx == -1:
            missing.append(req)
        else:
            found_indices.append(idx)

    # Order check: matched indices must be monotonically increasing.
    out_of_order: list[tuple[str, str]] = []
    for i in range(len(found_indices) - 1):
        if found_indices[i] > found_indices[i + 1]:
            out_of_order.append((required[i], required[i + 1]))

    return TabulatedResult(
        template_id=template_id,
        has_table=True,
        found_headers=headers,
        missing_columns=missing,
        out_of_order=out_of_order,
        n_data_rows=len(data),
    )


if __name__ == "__main__":
    good_repeat_dose = """
    Repeat-dose toxicity studies are summarized below.

    | Study | Species | Method of Administration | Duration | Doses (mg/kg/day) | NOAEL (mg/kg/day) | Findings |
    |-------|---------|--------------------------|----------|-------------------|-------------------|----------|
    | RTX-101 | Sprague-Dawley rat | oral gavage | 28 days | 0, 30, 100, 300 | 100 | mild liver enzyme elevation at 300 mg/kg/day |
    | RTX-102 | beagle dog | oral gavage | 28 days | 0, 10, 30, 100 | 30 | emesis at 100 mg/kg/day |
    """
    bad_missing_col = """
    | Study | Species | Doses |
    |-------|---------|-------|
    | A | rat | 100 |
    """

    for label, t, tid in [
        ("good", good_repeat_dose, "2.6.7.7"),
        ("missing-cols", bad_missing_col, "2.6.7.7"),
    ]:
        r = verify_table(t, tid)
        print(f"[{label}] passed={r.passed} missing={r.missing_columns} "
              f"out_of_order={r.out_of_order} rows={r.n_data_rows}")
