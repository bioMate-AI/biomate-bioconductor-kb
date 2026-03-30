"""
CSV schema definition and validator for BioMate assay data ingestion.
"""
import csv
from datetime import datetime
from typing import Optional

REQUIRED_COLUMNS = {"compound_id", "assay_type", "value", "unit", "assay_date"}
OPTIONAL_COLUMNS = {"smiles", "operator", "operator_note"}

SUPPORTED_ASSAY_TYPES = {
    "IC50", "Ki", "Kd", "EC50", "hERG", "DILI", "Ames",
    "ClinTox", "solubility", "permeability", "cell_viability",
    "selectivity_ratio", "custom",
}

VALID_OPERATORS = {"<", ">", "=", "~"}

UNIT_NORMALIZATION = {
    "nM": 1e-3,   # divide by 1000 → uM
    "mM": 1e3,    # multiply by 1000 → uM
    "uM": 1.0,
}


class AssayCSVValidator:
    """Validate and normalise assay CSV files."""

    def validate(self, csv_path: str) -> tuple[list[dict], list[str]]:
        """Parse and validate a CSV file.

        Returns:
            (valid_rows, error_messages) where valid_rows are dicts with
            normalised fields including `value_uM`.
        """
        valid_rows: list[dict] = []
        errors: list[str] = []

        try:
            with open(csv_path, newline="", encoding="utf-8") as f:
                reader = csv.DictReader(f)
                if reader.fieldnames is None:
                    errors.append("CSV file is empty or has no header row.")
                    return valid_rows, errors

                headers = {h.strip() for h in reader.fieldnames if h}
                missing = REQUIRED_COLUMNS - headers
                if missing:
                    errors.append(f"Missing required columns: {', '.join(sorted(missing))}")
                    return valid_rows, errors

                for row_num, raw_row in enumerate(reader, start=2):
                    row = {k.strip(): (v.strip() if v else "") for k, v in raw_row.items() if k}
                    row_errors = self._validate_row(row, row_num)
                    if row_errors:
                        errors.extend(row_errors)
                        continue
                    valid_rows.append(self._normalise_row(row))

        except FileNotFoundError:
            errors.append(f"File not found: {csv_path}")
        except Exception as exc:
            errors.append(f"Unexpected error reading CSV: {exc}")

        return valid_rows, errors

    def _validate_row(self, row: dict, row_num: int) -> list[str]:
        errs: list[str] = []

        compound_id = row.get("compound_id", "")
        if not compound_id:
            errs.append(f"Row {row_num}: compound_id is required.")

        assay_type = row.get("assay_type", "")
        if assay_type not in SUPPORTED_ASSAY_TYPES:
            errs.append(
                f"Row {row_num}: unsupported assay_type '{assay_type}'. "
                f"Supported: {', '.join(sorted(SUPPORTED_ASSAY_TYPES))}"
            )

        raw_value = row.get("value", "")
        try:
            float(raw_value)
        except (ValueError, TypeError):
            errs.append(f"Row {row_num}: value '{raw_value}' is not a valid number.")

        unit = row.get("unit", "")
        if unit not in UNIT_NORMALIZATION:
            errs.append(
                f"Row {row_num}: unsupported unit '{unit}'. "
                f"Supported: {', '.join(UNIT_NORMALIZATION)}"
            )

        assay_date = row.get("assay_date", "")
        try:
            datetime.strptime(assay_date, "%Y-%m-%d")
        except ValueError:
            errs.append(f"Row {row_num}: assay_date '{assay_date}' must be YYYY-MM-DD.")

        operator = row.get("operator", "")
        if operator and operator not in VALID_OPERATORS:
            errs.append(
                f"Row {row_num}: operator '{operator}' must be one of "
                f"{', '.join(sorted(VALID_OPERATORS))} or empty."
            )

        return errs

    def _normalise_row(self, row: dict) -> dict:
        unit = row["unit"]
        raw_value = float(row["value"])
        factor = UNIT_NORMALIZATION.get(unit, 1.0)
        value_uM = raw_value * factor

        return {
            "compound_id": row["compound_id"],
            "smiles": row.get("smiles", ""),
            "assay_type": row["assay_type"],
            "value": raw_value,
            "value_uM": value_uM,
            "unit": unit,
            "unit_normalized": "uM",
            "operator": row.get("operator", ""),
            "operator_note": row.get("operator_note", ""),
            "assay_date": row["assay_date"],
        }
