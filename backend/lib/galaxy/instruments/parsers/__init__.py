"""
Direct Instrument Parsers for bioMate

Custom parsers for sequencing instruments with no external dependencies.
These parsers are completely independent and GPL-free.

Supported Instruments:
- Illumina (FASTQ, BCL)
- Oxford Nanopore Technologies (FAST5, FASTQ)
- PacBio (BAM, FASTQ)

License: MIT (bioMate proprietary)
"""

__version__ = "1.0.0"
__license__ = "MIT"

from .base import BaseInstrumentParser, ParserResult, InstrumentMetadata
from .illumina import IlluminaParser
from .ont import ONTParser
from .pacbio import PacBioParser

__all__ = [
    'BaseInstrumentParser',
    'ParserResult',
    'InstrumentMetadata',
    'IlluminaParser',
    'ONTParser',
    'PacBioParser',
]
