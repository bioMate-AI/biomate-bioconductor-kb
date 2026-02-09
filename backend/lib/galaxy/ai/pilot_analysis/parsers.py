"""
Domain-specific output parsers for pilot analyzers.

Each domain can implement custom parsers for complex tool outputs.
These override the generic parser in the executor.
"""

import re
import json
from typing import Dict, Any, Optional
from pathlib import Path


class OutputParser:
    """Base class for domain-specific output parsers."""

    @staticmethod
    def parse(stdout: str, stderr: str, output_files: Dict[str, Path]) -> Dict[str, Any]:
        """
        Parse analyzer output.

        Args:
            stdout: Standard output from command
            stderr: Standard error from command
            output_files: Dict of output file paths created by analyzer

        Returns:
            Dict of extracted values
        """
        raise NotImplementedError


class SamtoolsStatsParser(OutputParser):
    """Parser for samtools stats output."""

    @staticmethod
    def parse(stdout: str, stderr: str, output_files: Dict[str, Path]) -> Dict[str, Any]:
        """Extract insert size and other metrics from samtools stats."""
        extracted = {}

        for line in stdout.splitlines():
            line = line.strip()

            # Summary number lines start with "SN"
            if line.startswith("SN"):
                parts = line.split("\t")
                if len(parts) >= 3:
                    metric_name = parts[1].strip().rstrip(":")
                    value_str = parts[2].strip()

                    # Extract specific metrics
                    if "insert size average" in metric_name.lower():
                        extracted["insert_size_average"] = int(float(value_str))
                    elif "total reads" in metric_name.lower():
                        extracted["total_reads"] = int(value_str)
                    elif "reads mapped" in metric_name.lower():
                        extracted["mapped_reads"] = int(value_str)

        return extracted


class SamtoolsFlagstatParser(OutputParser):
    """Parser for samtools flagstat output."""

    @staticmethod
    def parse(stdout: str, stderr: str, output_files: Dict[str, Path]) -> Dict[str, Any]:
        """Extract alignment statistics from flagstat."""
        extracted = {}

        for line in stdout.splitlines():
            line = line.strip()

            # Format: "12345 + 0 in total (QC-passed reads + QC-failed reads)"
            match = re.match(r"(\d+)\s+\+\s+\d+\s+(.*)", line)
            if match:
                count = int(match.group(1))
                description = match.group(2)

                if "in total" in description:
                    extracted["total_reads"] = count
                elif "mapped" in description and "mate mapped" not in description:
                    extracted["mapped_reads"] = count
                elif "properly paired" in description:
                    extracted["properly_paired"] = count

        return extracted


class PhantomPeakQualToolsParser(OutputParser):
    """Parser for phantompeakqualtools (SPP) output."""

    @staticmethod
    def parse(stdout: str, stderr: str, output_files: Dict[str, Path]) -> Dict[str, Any]:
        """
        Extract cross-correlation metrics from SPP output.

        SPP output format (tab-separated):
        filename, numReads, estFragLen, corr_estFragLen, phantomPeak, corr_phantomPeak,
        argmin_corr, min_corr, NSC, RSC, QualityTag
        """
        extracted = {}

        # Try to find output file or parse stdout
        output_text = stdout

        # Look for tab-separated line with metrics
        for line in output_text.splitlines():
            if "\t" in line:
                parts = line.split("\t")
                if len(parts) >= 11:
                    try:
                        extracted["strand_shift"] = int(parts[2])  # estFragLen
                        extracted["nsc"] = float(parts[8])  # NSC
                        extracted["rsc"] = float(parts[9])  # RSC
                        extracted["quality_tag"] = int(parts[10])  # QualityTag
                        break
                    except (ValueError, IndexError):
                        continue

        return extracted


class FastQCParser(OutputParser):
    """Parser for FastQC output."""

    @staticmethod
    def parse(stdout: str, stderr: str, output_files: Dict[str, Path]) -> Dict[str, Any]:
        """Extract quality metrics from FastQC output."""
        extracted = {}

        # FastQC creates a data file with metrics
        # For now, parse from summary if available
        for line in stdout.splitlines():
            line = line.strip()

            if "Total Sequences" in line:
                match = re.search(r"(\d+)", line)
                if match:
                    extracted["total_sequences"] = int(match.group(1))

            elif "Sequence length" in line:
                match = re.search(r"(\d+)", line)
                if match:
                    extracted["sequence_length"] = int(match.group(1))

            elif "%GC" in line or "GC content" in line:
                match = re.search(r"(\d+\.?\d*)", line)
                if match:
                    extracted["gc_content"] = float(match.group(1))

        return extracted


class SeqKitParser(OutputParser):
    """Parser for seqkit output."""

    @staticmethod
    def parse(stdout: str, stderr: str, output_files: Dict[str, Path]) -> Dict[str, Any]:
        """Extract sequence statistics from seqkit."""
        extracted = {}

        # seqkit fx2tab --gc output format: seq_name \t gc_percentage
        for line in stdout.splitlines():
            if "\t" in line:
                parts = line.split("\t")
                if len(parts) >= 2:
                    try:
                        extracted["gc_percentage"] = float(parts[1])
                        extracted["sequence_name"] = parts[0]
                    except (ValueError, IndexError):
                        continue

        return extracted


class CTFFind4Parser(OutputParser):
    """Parser for CTFFIND4 output."""

    @staticmethod
    def parse(stdout: str, stderr: str, output_files: Dict[str, Path]) -> Dict[str, Any]:
        """Extract CTF parameters from CTFFIND4 output."""
        extracted = {}

        # CTFFIND4 output format (space-separated):
        # micrograph_number defocus1 defocus2 angle cc_value
        for line in stdout.splitlines():
            line = line.strip()
            if line and not line.startswith("#"):
                parts = line.split()
                if len(parts) >= 5:
                    try:
                        extracted["defocus_min"] = float(parts[1]) / 10000  # Convert Å to μm
                        extracted["defocus_max"] = float(parts[2]) / 10000
                        extracted["astigmatism"] = abs(float(parts[1]) - float(parts[2])) / 10000
                        extracted["fit_quality"] = float(parts[4])
                    except (ValueError, IndexError):
                        continue

        return extracted


class AnndataParser(OutputParser):
    """Parser for AnnData/h5ad metadata."""

    @staticmethod
    def parse(stdout: str, stderr: str, output_files: Dict[str, Path]) -> Dict[str, Any]:
        """Extract cell and gene counts from AnnData shape output."""
        extracted = {}

        # Format: "(n_obs, n_vars)" or "n_obs, n_vars"
        for line in stdout.splitlines():
            match = re.search(r"\(?\s*(\d+)\s*,\s*(\d+)\s*\)?", line)
            if match:
                extracted["n_obs"] = int(match.group(1))  # cells
                extracted["n_vars"] = int(match.group(2))  # genes
                break

        return extracted


class NibabelHeaderParser(OutputParser):
    """Parser for nibabel image header info."""

    @staticmethod
    def parse(stdout: str, stderr: str, output_files: Dict[str, Path]) -> Dict[str, Any]:
        """Extract image dimensions and voxel spacing."""
        extracted = {}

        # Format: "shape: (x, y, z), zooms: (vx, vy, vz)"
        for line in stdout.splitlines():
            # Parse shape
            shape_match = re.search(r"\((\d+),\s*(\d+),\s*(\d+)\)", line)
            if shape_match:
                extracted["image_dimensions"] = [
                    int(shape_match.group(1)),
                    int(shape_match.group(2)),
                    int(shape_match.group(3)),
                ]

            # Parse zooms (voxel spacing)
            zooms_match = re.search(r"\((\d+\.?\d*),\s*(\d+\.?\d*),\s*(\d+\.?\d*)\)", line)
            if zooms_match:
                voxel_spacing = [
                    float(zooms_match.group(1)),
                    float(zooms_match.group(2)),
                    float(zooms_match.group(3)),
                ]
                extracted["voxel_spacing"] = voxel_spacing

                # Calculate anisotropy
                extracted["anisotropy_ratio"] = max(voxel_spacing) / min(voxel_spacing)

        return extracted


class RDKitDescriptorsParser(OutputParser):
    """Parser for RDKit molecular descriptors."""

    @staticmethod
    def parse(stdout: str, stderr: str, output_files: Dict[str, Path]) -> Dict[str, Any]:
        """Extract molecular descriptors from RDKit output."""
        # Try JSON format first
        try:
            return json.loads(stdout)
        except json.JSONDecodeError:
            pass

        # Fallback: parse key-value pairs
        extracted = {}
        for line in stdout.splitlines():
            if ":" in line:
                parts = line.split(":", 1)
                key = parts[0].strip().lower().replace(" ", "_")
                value_str = parts[1].strip()

                try:
                    # Try numeric conversion
                    if "." in value_str:
                        extracted[key] = float(value_str)
                    else:
                        extracted[key] = int(value_str)
                except ValueError:
                    extracted[key] = value_str

        return extracted


# Registry of parsers by tool name
PARSER_REGISTRY = {
    "samtools_stats": SamtoolsStatsParser,
    "samtools_flagstat": SamtoolsFlagstatParser,
    "phantompeakqualtools": PhantomPeakQualToolsParser,
    "fastqc_lite": FastQCParser,
    "seqkit_fx2tab": SeqKitParser,
    "ctffind4": CTFFind4Parser,
    "anndata_shape": AnndataParser,
    "nibabel_header": NibabelHeaderParser,
    "rdkit_descriptors": RDKitDescriptorsParser,
}


def get_parser(tool_name: str) -> Optional[type]:
    """Get parser class for a tool."""
    return PARSER_REGISTRY.get(tool_name)


def parse_output(
    tool_name: str, stdout: str, stderr: str, output_files: Optional[Dict[str, Path]] = None
) -> Dict[str, Any]:
    """
    Parse tool output using appropriate parser.

    Args:
        tool_name: Name of tool that generated output
        stdout: Standard output
        stderr: Standard error
        output_files: Optional dict of output file paths

    Returns:
        Dict of extracted values
    """
    parser_class = get_parser(tool_name)
    if parser_class:
        return parser_class.parse(stdout, stderr, output_files or {})
    else:
        # Return empty dict if no parser available
        # Executor will use generic parsing
        return {}
