"""
Illumina Sequencer Parser

Parses FASTQ files from Illumina sequencing platforms:
- NovaSeq, NextSeq, MiSeq, HiSeq, iSeq, MiniSeq

Supports:
- FASTQ (gzipped or uncompressed)
- Paired-end and single-end reads
- Demultiplexed and multiplexed data

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


class IlluminaParser(BaseInstrumentParser):
    """Parser for Illumina FASTQ files"""

    def __init__(self):
        super().__init__()
        self.instrument_type = InstrumentType.SEQUENCER
        self.supported_formats = [DataFormat.FASTQ]

    def parse(self, file_path: str, max_reads: Optional[int] = None, **kwargs) -> ParserResult:
        """
        Parse Illumina FASTQ file

        Args:
            file_path: Path to FASTQ file
            max_reads: Maximum reads to parse (None = all)
            **kwargs: Additional options

        Returns:
            ParserResult with parsed reads
        """
        start_time = time.time()

        # Initialize result
        result = ParserResult(
            success=False,
            instrument_type=self.instrument_type,
            data_format=DataFormat.FASTQ,
            instrument_metadata=InstrumentMetadata(
                manufacturer="Illumina",
                model="Unknown"
            ),
            samples=[]
        )

        try:
            # Validate file
            if not self.validate(file_path):
                result.errors.append(f"Invalid FASTQ file: {file_path}")
                return result

            # Get metadata
            result.instrument_metadata = self.get_metadata(file_path)

            # Parse reads
            reads_by_sample = self._parse_fastq_file(file_path, max_reads)

            # Convert to Sample objects
            for sample_id, reads in reads_by_sample.items():
                sample = Sample(
                    sample_id=sample_id,
                    sample_name=sample_id,
                    reads=reads
                )
                sample = self._calculate_sample_stats(sample)
                result.samples.append(sample)

            # Calculate summary
            result = self._summarize_results(result)
            result.success = True

        except Exception as e:
            result.errors.append(f"Parsing error: {str(e)}")

        result.processing_time = time.time() - start_time
        return result

    def validate(self, file_path: str) -> bool:
        """
        Validate FASTQ file format

        Checks:
        - File exists
        - Starts with @ (FASTQ header)
        - Has 4-line structure
        """
        try:
            path = Path(file_path)
            if not path.exists():
                return False

            # Read first few lines
            with self._open_file(file_path) as f:
                lines = [f.readline() for _ in range(4)]

            # Check FASTQ structure
            if not lines[0].startswith('@'):
                return False

            if not lines[2].startswith('+'):
                return False

            # Check sequence and quality have same length
            seq_len = len(lines[1].strip())
            qual_len = len(lines[3].strip())

            return seq_len == qual_len and seq_len > 0

        except Exception:
            return False

    def get_metadata(self, file_path: str) -> InstrumentMetadata:
        """
        Extract Illumina instrument metadata from FASTQ headers

        Illumina header format:
        @Instrument:RunID:FlowCellID:Lane:Tile:X:Y ReadNum:FilterFlag:0:SampleNumber
        """
        metadata = InstrumentMetadata(
            manufacturer="Illumina",
            model="Unknown"
        )

        try:
            with self._open_file(file_path) as f:
                # Parse first header
                header = f.readline().strip()
                header_info = self._parse_illumina_header(header)

                metadata.serial_number = header_info.get('instrument')
                metadata.run_id = header_info.get('run_id')
                metadata.flowcell_id = header_info.get('flowcell_id')
                metadata.additional = header_info

                # Guess instrument model from header format
                metadata.model = self._guess_instrument_model(header_info)

        except Exception:
            pass

        return metadata

    def _parse_fastq_file(
        self,
        file_path: str,
        max_reads: Optional[int] = None
    ) -> Dict[str, List[SequenceRead]]:
        """
        Parse FASTQ file into reads grouped by sample

        Args:
            file_path: Path to FASTQ file
            max_reads: Max reads to parse

        Returns:
            Dictionary: sample_id -> list of reads
        """
        reads_by_sample = {}
        read_count = 0

        with self._open_file(file_path) as f:
            while True:
                # Read 4 lines (FASTQ record)
                header = f.readline()
                if not header:
                    break  # EOF

                sequence = f.readline().strip()
                plus = f.readline()
                quality = f.readline().strip()

                # Parse header
                header_info = self._parse_illumina_header(header.strip())

                # Extract sample ID
                sample_id = header_info.get('sample_number', 'default')
                if not sample_id or sample_id == '0':
                    sample_id = 'sample_1'

                # Create SequenceRead
                read = SequenceRead(
                    read_id=header.strip().lstrip('@'),
                    sequence=sequence,
                    quality=quality,
                    length=len(sequence),
                    mean_quality=self._calculate_mean_quality(quality),
                    gc_content=self._calculate_gc_content(sequence),
                    metadata=header_info
                )

                # Add to sample
                if sample_id not in reads_by_sample:
                    reads_by_sample[sample_id] = []
                reads_by_sample[sample_id].append(read)

                read_count += 1
                if max_reads and read_count >= max_reads:
                    break

        return reads_by_sample

    def _guess_instrument_model(self, header_info: Dict) -> str:
        """
        Guess Illumina instrument model from header

        Instrument naming conventions:
        - M: MiSeq
        - D: HiSeq 2500
        - K: HiSeq 4000
        - A: NovaSeq
        - NS: NextSeq
        - VH: NextSeq 2000
        - LH: NextSeq 1000/2000
        - FS: iSeq 100
        - MN: MiniSeq
        """
        instrument = header_info.get('instrument', '').upper()

        if instrument.startswith('M'):
            return 'MiSeq'
        elif instrument.startswith('D'):
            return 'HiSeq 2500'
        elif instrument.startswith('K'):
            return 'HiSeq 4000'
        elif instrument.startswith('A'):
            return 'NovaSeq'
        elif instrument.startswith('NS'):
            return 'NextSeq 500/550'
        elif instrument.startswith('VH') or instrument.startswith('LH'):
            return 'NextSeq 1000/2000'
        elif instrument.startswith('FS'):
            return 'iSeq 100'
        elif instrument.startswith('MN'):
            return 'MiniSeq'
        else:
            return 'Unknown Illumina'


class IlluminaPairedEndParser(IlluminaParser):
    """
    Parser for Illumina paired-end data (R1/R2 files)

    Usage:
        parser = IlluminaPairedEndParser()
        result = parser.parse_paired(r1_file, r2_file)
    """

    def parse_paired(
        self,
        r1_file: str,
        r2_file: str,
        max_reads: Optional[int] = None
    ) -> ParserResult:
        """
        Parse paired-end FASTQ files

        Args:
            r1_file: Read 1 FASTQ file
            r2_file: Read 2 FASTQ file
            max_reads: Max read pairs to parse

        Returns:
            ParserResult with paired reads
        """
        start_time = time.time()

        result = ParserResult(
            success=False,
            instrument_type=self.instrument_type,
            data_format=DataFormat.FASTQ,
            instrument_metadata=self.get_metadata(r1_file),
            samples=[]
        )

        try:
            # Validate both files
            if not self.validate(r1_file) or not self.validate(r2_file):
                result.errors.append("Invalid FASTQ file(s)")
                return result

            # Parse both files
            r1_reads = self._parse_fastq_file(r1_file, max_reads)
            r2_reads = self._parse_fastq_file(r2_file, max_reads)

            # Combine into samples
            all_sample_ids = set(r1_reads.keys()) | set(r2_reads.keys())

            for sample_id in all_sample_ids:
                reads = r1_reads.get(sample_id, []) + r2_reads.get(sample_id, [])

                sample = Sample(
                    sample_id=sample_id,
                    sample_name=sample_id,
                    reads=reads,
                    metadata={
                        'paired_end': True,
                        'r1_count': len(r1_reads.get(sample_id, [])),
                        'r2_count': len(r2_reads.get(sample_id, []))
                    }
                )
                sample = self._calculate_sample_stats(sample)
                result.samples.append(sample)

            result = self._summarize_results(result)
            result.success = True

        except Exception as e:
            result.errors.append(f"Paired parsing error: {str(e)}")

        result.processing_time = time.time() - start_time
        return result
