"""
Base Parser Interface for Instrument Data

Defines the common interface for all instrument parsers.
"""

from abc import ABC, abstractmethod
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
import gzip
import io


class InstrumentType(str, Enum):
    """Types of instruments"""
    SEQUENCER = "sequencer"
    CHEMISTRY = "chemistry"
    HEMATOLOGY = "hematology"
    FLOW_CYTOMETRY = "flow_cytometry"
    MASS_SPEC = "mass_spectrometry"
    GENERIC = "generic"


class DataFormat(str, Enum):
    """Data formats"""
    FASTQ = "fastq"
    FASTA = "fasta"
    BAM = "bam"
    FAST5 = "fast5"
    CSV = "csv"
    TSV = "tsv"
    JSON = "json"
    XML = "xml"


@dataclass
class InstrumentMetadata:
    """Metadata about the instrument"""
    manufacturer: str
    model: str
    serial_number: Optional[str] = None
    software_version: Optional[str] = None
    run_id: Optional[str] = None
    flowcell_id: Optional[str] = None
    timestamp: Optional[datetime] = None
    additional: Dict[str, Any] = field(default_factory=dict)


@dataclass
class SequenceRead:
    """Single sequencing read"""
    read_id: str
    sequence: str
    quality: str
    length: int
    mean_quality: float
    gc_content: float
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class Sample:
    """Sample data"""
    sample_id: str
    sample_name: Optional[str] = None
    barcode: Optional[str] = None
    reads: List[SequenceRead] = field(default_factory=list)
    read_count: int = 0
    total_bases: int = 0
    mean_read_length: float = 0.0
    mean_quality: float = 0.0
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ParserResult:
    """Result from parsing instrument data"""
    success: bool
    instrument_type: InstrumentType
    data_format: DataFormat
    instrument_metadata: InstrumentMetadata
    samples: List[Sample]
    total_reads: int = 0
    total_bases: int = 0
    errors: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    processing_time: float = 0.0
    raw_data: Optional[Dict[str, Any]] = None


class BaseInstrumentParser(ABC):
    """
    Abstract base class for all instrument parsers

    All parsers must implement:
    - parse(): Parse instrument data
    - validate(): Validate file format
    - get_metadata(): Extract instrument metadata
    """

    def __init__(self):
        self.instrument_type = InstrumentType.GENERIC
        self.supported_formats = []

    @abstractmethod
    def parse(self, file_path: str, **kwargs) -> ParserResult:
        """
        Parse instrument data file

        Args:
            file_path: Path to data file
            **kwargs: Parser-specific options

        Returns:
            ParserResult with parsed data
        """
        pass

    @abstractmethod
    def validate(self, file_path: str) -> bool:
        """
        Validate file format

        Args:
            file_path: Path to data file

        Returns:
            True if valid, False otherwise
        """
        pass

    @abstractmethod
    def get_metadata(self, file_path: str) -> InstrumentMetadata:
        """
        Extract instrument metadata from file

        Args:
            file_path: Path to data file

        Returns:
            InstrumentMetadata object
        """
        pass

    # ========================================================================
    # Helper Methods
    # ========================================================================

    def _open_file(self, file_path: str, mode: str = 'rt'):
        """
        Open file, handling gzip compression automatically

        Args:
            file_path: Path to file
            mode: Open mode (default: 'rt' for text)

        Returns:
            File handle
        """
        if file_path.endswith('.gz'):
            return gzip.open(file_path, mode)
        else:
            return open(file_path, mode)

    def _is_gzipped(self, file_path: str) -> bool:
        """Check if file is gzip compressed"""
        return file_path.endswith('.gz')

    def _calculate_gc_content(self, sequence: str) -> float:
        """Calculate GC content of sequence"""
        if not sequence:
            return 0.0

        gc_count = sequence.upper().count('G') + sequence.upper().count('C')
        return (gc_count / len(sequence)) * 100.0

    def _calculate_mean_quality(self, quality_string: str, offset: int = 33) -> float:
        """
        Calculate mean quality score from Phred quality string

        Args:
            quality_string: ASCII quality string
            offset: Phred offset (33 for Phred+33, 64 for Phred+64)

        Returns:
            Mean quality score
        """
        if not quality_string:
            return 0.0

        scores = [ord(c) - offset for c in quality_string]
        return sum(scores) / len(scores) if scores else 0.0

    def _quality_to_error_rate(self, quality: float) -> float:
        """Convert Phred quality to error rate"""
        return 10 ** (-quality / 10)

    def _detect_phred_offset(self, quality_string: str) -> int:
        """
        Auto-detect Phred offset (33 or 64)

        Args:
            quality_string: Sample quality string

        Returns:
            33 or 64
        """
        if not quality_string:
            return 33

        min_char = min(ord(c) for c in quality_string)

        if min_char < 64:
            return 33  # Phred+33 (Sanger, Illumina 1.8+)
        else:
            return 64  # Phred+64 (Illumina 1.3-1.7)

    def _parse_illumina_header(self, header: str) -> Dict[str, Any]:
        """
        Parse Illumina FASTQ header

        Format: @Instrument:RunID:FlowCellID:Lane:Tile:X:Y ReadNum:FilterFlag:0:SampleNumber

        Args:
            header: FASTQ header line

        Returns:
            Dictionary with parsed fields
        """
        metadata = {}

        try:
            # Remove @ prefix
            header = header.lstrip('@')

            # Split into components
            parts = header.split(':')

            if len(parts) >= 7:
                metadata['instrument'] = parts[0]
                metadata['run_id'] = parts[1]
                metadata['flowcell_id'] = parts[2]
                metadata['lane'] = parts[3]
                metadata['tile'] = parts[4]
                metadata['x_pos'] = parts[5]
                metadata['y_pos'] = parts[6]

                # Additional fields if present
                if len(parts) >= 11:
                    metadata['read_num'] = parts[7]
                    metadata['filter_flag'] = parts[8]
                    metadata['control_bits'] = parts[9]
                    metadata['sample_number'] = parts[10]

        except Exception:
            # Fallback: store raw header
            metadata['raw_header'] = header

        return metadata

    def _calculate_sample_stats(self, sample: Sample) -> Sample:
        """
        Calculate aggregate statistics for a sample

        Args:
            sample: Sample object with reads

        Returns:
            Updated sample with calculated stats
        """
        if not sample.reads:
            return sample

        sample.read_count = len(sample.reads)
        sample.total_bases = sum(read.length for read in sample.reads)
        sample.mean_read_length = sample.total_bases / sample.read_count
        sample.mean_quality = sum(read.mean_quality for read in sample.reads) / sample.read_count

        return sample

    def _summarize_results(self, result: ParserResult) -> ParserResult:
        """
        Calculate summary statistics for parser result

        Args:
            result: ParserResult object

        Returns:
            Updated result with summary stats
        """
        result.total_reads = sum(sample.read_count for sample in result.samples)
        result.total_bases = sum(sample.total_bases for sample in result.samples)

        return result
