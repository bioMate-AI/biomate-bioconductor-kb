"""
PacBio Parser

Parses FASTQ/BAM files from PacBio sequencing platforms:
- Sequel, Sequel II, Sequel IIe, Revio

Supports:
- FASTQ (HiFi reads)
- BAM (with CCS/HiFi data)

License: MIT (bioMate proprietary)
"""

import re
from typing import Dict, List, Optional
from datetime import datetime
from pathlib import Path
import time

from .base import (
    BaseInstrumentParser,
    ParserResult,
    InstrumentMetadata,
    Sample,
    SequenceRead,
    InstrumentType,
    DataFormat
)


class PacBioParser(BaseInstrumentParser):
    """Parser for PacBio FASTQ files (HiFi reads)"""

    def __init__(self):
        super().__init__()
        self.instrument_type = InstrumentType.SEQUENCER
        self.supported_formats = [DataFormat.FASTQ, DataFormat.BAM]

    def parse(self, file_path: str, max_reads: Optional[int] = None, **kwargs) -> ParserResult:
        """
        Parse PacBio FASTQ file

        Args:
            file_path: Path to FASTQ file
            max_reads: Maximum reads to parse (None = all)
            **kwargs: Additional options

        Returns:
            ParserResult with parsed reads
        """
        start_time = time.time()

        result = ParserResult(
            success=False,
            instrument_type=self.instrument_type,
            data_format=DataFormat.FASTQ,
            instrument_metadata=InstrumentMetadata(
                manufacturer="Pacific Biosciences",
                model="Unknown"
            ),
            samples=[]
        )

        try:
            if not self.validate(file_path):
                result.errors.append(f"Invalid FASTQ file: {file_path}")
                return result

            result.instrument_metadata = self.get_metadata(file_path)
            reads_by_sample = self._parse_pacbio_fastq(file_path, max_reads)

            for sample_id, reads in reads_by_sample.items():
                # Calculate HiFi-specific metrics
                n50 = self._calculate_n50([r.length for r in reads])
                mean_accuracy = self._calculate_hifi_accuracy(reads)

                sample = Sample(
                    sample_id=sample_id,
                    sample_name=sample_id,
                    reads=reads,
                    metadata={
                        'n50': n50,
                        'mean_accuracy': mean_accuracy,
                        'technology': 'HiFi'
                    }
                )
                sample = self._calculate_sample_stats(sample)
                result.samples.append(sample)

            result = self._summarize_results(result)
            result.success = True

        except Exception as e:
            result.errors.append(f"Parsing error: {str(e)}")

        result.processing_time = time.time() - start_time
        return result

    def validate(self, file_path: str) -> bool:
        """Validate PacBio FASTQ file"""
        try:
            path = Path(file_path)
            if not path.exists():
                return False

            # Check if it's BAM
            if file_path.endswith('.bam'):
                # Would need pysam to validate BAM
                return True

            # Validate FASTQ
            with self._open_file(file_path) as f:
                lines = [f.readline() for _ in range(4)]

            if not lines[0].startswith('@'):
                return False

            if not lines[2].startswith('+'):
                return False

            seq_len = len(lines[1].strip())
            qual_len = len(lines[3].strip())

            return seq_len == qual_len and seq_len > 0

        except Exception:
            return False

    def get_metadata(self, file_path: str) -> InstrumentMetadata:
        """
        Extract PacBio metadata from FASTQ headers

        PacBio HiFi header format:
        @movieName/zmw/ccs [various_tags]
        """
        metadata = InstrumentMetadata(
            manufacturer="Pacific Biosciences",
            model="Unknown"
        )

        try:
            with self._open_file(file_path) as f:
                header = f.readline().strip()
                pb_metadata = self._parse_pacbio_header(header)

                metadata.run_id = pb_metadata.get('movie_name')
                metadata.additional = pb_metadata
                metadata.model = self._guess_pacbio_instrument(pb_metadata)

        except Exception:
            pass

        return metadata

    def _parse_pacbio_fastq(
        self,
        file_path: str,
        max_reads: Optional[int] = None
    ) -> Dict[str, List[SequenceRead]]:
        """Parse PacBio FASTQ into reads by sample"""
        reads_by_sample = {}
        read_count = 0

        with self._open_file(file_path) as f:
            while True:
                header = f.readline()
                if not header:
                    break

                sequence = f.readline().strip()
                plus = f.readline()
                quality = f.readline().strip()

                # Parse header
                pb_metadata = self._parse_pacbio_header(header.strip())

                # Extract sample ID (usually from barcode)
                sample_id = pb_metadata.get('barcode', 'sample_1')
                if not sample_id or sample_id == 'unknown':
                    sample_id = 'sample_1'

                # Calculate accuracy from quality
                accuracy = self._quality_to_accuracy(quality)

                # Create read
                read = SequenceRead(
                    read_id=pb_metadata.get('zmw_id', header.strip().lstrip('@')),
                    sequence=sequence,
                    quality=quality,
                    length=len(sequence),
                    mean_quality=self._calculate_mean_quality(quality),
                    gc_content=self._calculate_gc_content(sequence),
                    metadata={**pb_metadata, 'accuracy': accuracy}
                )

                if sample_id not in reads_by_sample:
                    reads_by_sample[sample_id] = []
                reads_by_sample[sample_id].append(read)

                read_count += 1
                if max_reads and read_count >= max_reads:
                    break

        return reads_by_sample

    def _parse_pacbio_header(self, header: str) -> Dict:
        """
        Parse PacBio FASTQ header

        Format: @movieName/zmw/ccs additional_info

        Example: @m64011_190830_220126/4194918/ccs rq=0.999
        """
        metadata = {}

        try:
            header = header.lstrip('@')

            # Split into ID and tags
            parts = header.split()
            if parts:
                # Parse ID: movieName/zmw/ccs
                id_parts = parts[0].split('/')
                if len(id_parts) >= 2:
                    metadata['movie_name'] = id_parts[0]
                    metadata['zmw_id'] = parts[0]  # Full ID
                    metadata['zmw'] = id_parts[1]
                    if len(id_parts) >= 3:
                        metadata['read_type'] = id_parts[2]  # Usually 'ccs' for HiFi

                # Parse tags (rq=0.999, np=10, etc.)
                for part in parts[1:]:
                    if '=' in part:
                        key, value = part.split('=', 1)
                        try:
                            # Try to convert to number
                            metadata[key] = float(value)
                        except:
                            metadata[key] = value

        except Exception:
            metadata['raw_header'] = header

        return metadata

    def _guess_pacbio_instrument(self, metadata: Dict) -> str:
        """
        Guess PacBio instrument from movie name

        Movie name format: m[instrument_id]_[date]_[time]

        Instrument prefixes:
        - m64xxx: Sequel II/IIe
        - m54xxx: Sequel
        - m84xxx: Revio
        """
        movie_name = metadata.get('movie_name', '')

        if movie_name.startswith('m84'):
            return 'Revio'
        elif movie_name.startswith('m64'):
            return 'Sequel II/IIe'
        elif movie_name.startswith('m54'):
            return 'Sequel'
        else:
            return 'Unknown PacBio'

    def _calculate_n50(self, lengths: List[int]) -> int:
        """Calculate N50"""
        if not lengths:
            return 0

        sorted_lengths = sorted(lengths, reverse=True)
        total_bases = sum(sorted_lengths)
        cumulative = 0

        for length in sorted_lengths:
            cumulative += length
            if cumulative >= total_bases / 2:
                return length

        return 0

    def _quality_to_accuracy(self, quality_string: str) -> float:
        """
        Convert quality string to read accuracy

        PacBio HiFi reads typically have Q30-Q50 (99.9-99.999% accuracy)
        """
        mean_q = self._calculate_mean_quality(quality_string)
        # Accuracy = 1 - error_rate
        error_rate = self._quality_to_error_rate(mean_q)
        return (1 - error_rate) * 100  # As percentage

    def _calculate_hifi_accuracy(self, reads: List[SequenceRead]) -> float:
        """Calculate mean HiFi accuracy across reads"""
        if not reads:
            return 0.0

        accuracies = [r.metadata.get('accuracy', 0) for r in reads]
        return sum(accuracies) / len(accuracies) if accuracies else 0.0
