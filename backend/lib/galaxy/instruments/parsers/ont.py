"""
Oxford Nanopore Technologies (ONT) Parser

Parses FASTQ files from ONT sequencing platforms:
- MinION, GridION, PromethION, Flongle

Supports:
- FASTQ (gzipped or uncompressed)
- Long reads (1kb-2Mb+)
- Base-called data from Guppy/Dorado

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


class ONTParser(BaseInstrumentParser):
    """Parser for Oxford Nanopore FASTQ files"""

    def __init__(self):
        super().__init__()
        self.instrument_type = InstrumentType.SEQUENCER
        self.supported_formats = [DataFormat.FASTQ]

    def parse(self, file_path: str, max_reads: Optional[int] = None, **kwargs) -> ParserResult:
        """
        Parse ONT FASTQ file

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
                manufacturer="Oxford Nanopore Technologies",
                model="Unknown"
            ),
            samples=[]
        )

        try:
            if not self.validate(file_path):
                result.errors.append(f"Invalid FASTQ file: {file_path}")
                return result

            result.instrument_metadata = self.get_metadata(file_path)
            reads_by_sample = self._parse_ont_fastq(file_path, max_reads)

            for sample_id, reads in reads_by_sample.items():
                # Calculate N50 for long reads
                n50 = self._calculate_n50([r.length for r in reads])

                sample = Sample(
                    sample_id=sample_id,
                    sample_name=sample_id,
                    reads=reads,
                    metadata={'n50': n50}
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
        """Validate ONT FASTQ file"""
        try:
            path = Path(file_path)
            if not path.exists():
                return False

            with self._open_file(file_path) as f:
                lines = [f.readline() for _ in range(4)]

            if not lines[0].startswith('@'):
                return False

            if not lines[2].startswith('+'):
                return False

            # ONT reads are typically long (>1kb)
            seq_len = len(lines[1].strip())
            qual_len = len(lines[3].strip())

            return seq_len == qual_len and seq_len > 0

        except Exception:
            return False

    def get_metadata(self, file_path: str) -> InstrumentMetadata:
        """
        Extract ONT metadata from FASTQ headers

        ONT header format:
        @read_id runid=xxx sampleid=xxx read=N ch=N start_time=xxx
        """
        metadata = InstrumentMetadata(
            manufacturer="Oxford Nanopore Technologies",
            model="Unknown"
        )

        try:
            with self._open_file(file_path) as f:
                header = f.readline().strip()
                ont_metadata = self._parse_ont_header(header)

                metadata.run_id = ont_metadata.get('runid')
                metadata.flowcell_id = ont_metadata.get('flow_cell_id')
                metadata.serial_number = ont_metadata.get('device_id')
                metadata.software_version = ont_metadata.get('basecall_model_version_id')
                metadata.additional = ont_metadata

                # Guess device type
                metadata.model = self._guess_ont_device(ont_metadata)

        except Exception:
            pass

        return metadata

    def _parse_ont_fastq(
        self,
        file_path: str,
        max_reads: Optional[int] = None
    ) -> Dict[str, List[SequenceRead]]:
        """Parse ONT FASTQ into reads by sample"""
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

                # Parse ONT header
                ont_metadata = self._parse_ont_header(header.strip())

                # Extract sample ID
                sample_id = ont_metadata.get('sampleid', 'sample_1')
                if not sample_id:
                    sample_id = ont_metadata.get('barcode', 'sample_1')

                # Create read
                read = SequenceRead(
                    read_id=ont_metadata.get('read_id', header.strip().lstrip('@')),
                    sequence=sequence,
                    quality=quality,
                    length=len(sequence),
                    mean_quality=self._calculate_mean_quality(quality),
                    gc_content=self._calculate_gc_content(sequence),
                    metadata=ont_metadata
                )

                if sample_id not in reads_by_sample:
                    reads_by_sample[sample_id] = []
                reads_by_sample[sample_id].append(read)

                read_count += 1
                if max_reads and read_count >= max_reads:
                    break

        return reads_by_sample

    def _parse_ont_header(self, header: str) -> Dict:
        """
        Parse ONT FASTQ header

        Format: @read_id key1=value1 key2=value2 ...

        Common keys:
        - runid: Run ID
        - sampleid: Sample ID
        - read: Read number
        - ch: Channel number
        - start_time: Start time
        - barcode: Barcode/sample assignment
        """
        metadata = {}

        try:
            # Remove @ prefix
            header = header.lstrip('@')

            # Split into read ID and key=value pairs
            parts = header.split()
            if parts:
                metadata['read_id'] = parts[0]

                # Parse key=value pairs
                for part in parts[1:]:
                    if '=' in part:
                        key, value = part.split('=', 1)
                        metadata[key] = value

        except Exception:
            metadata['raw_header'] = header

        return metadata

    def _guess_ont_device(self, metadata: Dict) -> str:
        """
        Guess ONT device type from metadata

        Devices:
        - MinION: Portable sequencer
        - GridION: Benchtop 5-flowcell system
        - PromethION: High-throughput 24-48 flowcells
        - Flongle: Small flowcell adapter for MinION
        """
        device_id = metadata.get('device_id', '').upper()
        flow_cell_id = metadata.get('flow_cell_id', '').upper()

        if 'PROM' in device_id or 'PROM' in flow_cell_id:
            return 'PromethION'
        elif 'GRID' in device_id:
            return 'GridION'
        elif 'FLO-FLG' in flow_cell_id:
            return 'Flongle'
        elif 'MIN' in device_id or 'MN' in device_id:
            return 'MinION'
        else:
            return 'Unknown ONT Device'

    def _calculate_n50(self, lengths: List[int]) -> int:
        """
        Calculate N50 (length at which 50% of bases are in longer reads)

        Args:
            lengths: List of read lengths

        Returns:
            N50 value
        """
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
