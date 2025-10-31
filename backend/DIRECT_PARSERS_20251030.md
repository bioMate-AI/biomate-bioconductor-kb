# Direct Instrument Parsers

**Document Created:** 2025-10-30 14:25:00 UTC
**Last Updated:** 2025-10-30 14:25:00 UTC
**Author:** bioMate Development Team
**Version:** 1.0.0

---

## Overview

Direct parsers provide GPL-free parsing of sequencing data from major Next-Generation Sequencing (NGS) platforms. These parsers are implemented as native Python code under the MIT license and avoid GPL dependencies.

## Supported Platforms

### 1. Illumina Sequencers

**Supported Instruments:**
- NovaSeq (6000, X, X Plus)
- NextSeq (500/550, 1000/2000)
- MiSeq
- HiSeq (2500, 3000, 4000, X)
- iSeq 100
- MiniSeq

**Data Format:** FASTQ (gzipped or uncompressed)

**Features:**
- Paired-end and single-end reads
- Automatic instrument model detection from headers
- Quality score calculation (Phred+33/64 auto-detection)
- GC content analysis
- Sample demultiplexing from barcode indices

**Header Format:**
```
@Instrument:RunID:FlowCellID:Lane:Tile:X:Y ReadNum:FilterFlag:0:SampleNumber
```

**Example:**
```
@M00001:1:000000000-A1234:1:1101:15000:1000 1:N:0:1
AGCTTAGCTAGCTACGATCGATCGATCGATCGATCG
+
IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
```

### 2. Oxford Nanopore Technologies (ONT)

**Supported Instruments:**
- MinION (portable sequencer)
- GridION (5-flowcell benchtop)
- PromethION (24-48 flowcell high-throughput)
- Flongle (small flowcell adapter)

**Data Format:** FASTQ (from Guppy/Dorado basecalling)

**Features:**
- Long-read support (1kb-2Mb+)
- N50 calculation
- Run metadata extraction
- Channel and read tracking
- Barcode demultiplexing

**Header Format:**
```
@read_id runid=xxx sampleid=xxx read=N ch=N start_time=xxx barcode=xxx
```

**Example:**
```
@read_001 runid=abc123 sampleid=sample_A read=1 ch=100 barcode=barcode01
ATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCG
+
IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
```

### 3. PacBio (Pacific Biosciences)

**Supported Instruments:**
- Revio (latest generation)
- Sequel II / Sequel IIe
- Sequel

**Data Format:** FASTQ (HiFi/CCS reads)

**Features:**
- HiFi read accuracy calculation (>99.9%)
- Movie name parsing
- ZMW (Zero-Mode Waveguide) tracking
- N50 calculation
- Read quality metrics (rq scores)

**Header Format:**
```
@movieName/zmw/ccs rq=0.999 np=10
```

**Example:**
```
@m64011_190830_220126/4194918/ccs rq=0.999 np=10
ATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCG
+
IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Unified Instrument Service            │
│                                                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │         InstrumentOrchestrator                   │  │
│  │  (Auto-routes by instrument type)                │  │
│  └──────────────────────────────────────────────────┘  │
│           │              │              │               │
│           ▼              ▼              ▼               │
│    ┌──────────┐   ┌──────────┐   ┌──────────────┐     │
│    │ SENAITE  │   │ OpenELIS │   │   Direct     │     │
│    │  Client  │   │  Client  │   │   Parsers    │     │
│    │  (GPL)   │   │  (MPL)   │   │   (MIT)      │     │
│    └──────────┘   └──────────┘   └──────────────┘     │
│                                          │               │
│                         ┌────────────────┴─────────┐    │
│                         ▼                ▼         ▼    │
│                   IlluminaParser   ONTParser  PacBioParser
└─────────────────────────────────────────────────────────┘
```

## Parser Implementation

### Base Parser Interface

All parsers inherit from `BaseInstrumentParser`:

```python
from galaxy.instruments.parsers.base import BaseInstrumentParser, ParserResult

class MyParser(BaseInstrumentParser):
    def parse(self, file_path: str, **kwargs) -> ParserResult:
        """Parse instrument data file"""
        pass

    def validate(self, file_path: str) -> bool:
        """Validate file format"""
        pass

    def get_metadata(self, file_path: str) -> InstrumentMetadata:
        """Extract instrument metadata"""
        pass
```

### Common Helper Methods

The base parser provides helper methods:

- `_open_file()` - Open files with automatic gzip detection
- `_calculate_gc_content()` - Calculate GC percentage
- `_calculate_mean_quality()` - Calculate mean Phred quality
- `_parse_illumina_header()` - Parse standard Illumina headers
- `_calculate_sample_stats()` - Calculate per-sample statistics
- `_summarize_results()` - Calculate overall statistics

## Usage Examples

### Python API

```python
from galaxy.instruments.parsers import IlluminaParser, ONTParser, PacBioParser

# Parse Illumina data
parser = IlluminaParser()
result = parser.parse('/path/to/reads.fastq.gz', max_reads=10000)

if result.success:
    print(f"Parsed {result.total_reads} reads from {len(result.samples)} samples")
    for sample in result.samples:
        print(f"Sample {sample.sample_id}: {sample.read_count} reads, "
              f"{sample.mean_read_length:.1f}bp average length")
else:
    print(f"Errors: {result.errors}")

# Parse ONT data
ont_parser = ONTParser()
ont_result = ont_parser.parse('/path/to/ont_reads.fastq')

for sample in ont_result.samples:
    print(f"N50: {sample.metadata['n50']}bp")

# Parse PacBio HiFi data
pb_parser = PacBioParser()
pb_result = pb_parser.parse('/path/to/hifi_reads.fastq')

for sample in pb_result.samples:
    print(f"Mean HiFi accuracy: {sample.metadata['mean_accuracy']:.2f}%")
```

### REST API (via Unified Service)

```bash
# Import Illumina data
curl -X POST http://localhost:8000/import \
  -F "file=@reads.fastq.gz" \
  -F "instrument=Illumina_NovaSeq" \
  -F "backend=direct"

# Import ONT data (auto-routes to direct parser)
curl -X POST http://localhost:8000/import \
  -F "file=@ont_reads.fastq.gz" \
  -F "instrument=ONT_MinION" \
  -F "backend=auto"

# Import PacBio data
curl -X POST http://localhost:8000/import \
  -F "file=@hifi_reads.fastq" \
  -F "instrument=PacBio_Revio" \
  -F "backend=direct"
```

### Response Format

```json
{
  "success": true,
  "message": "Parsed 1000 reads",
  "backend_used": "direct",
  "samples": [
    {
      "sample_id": "sample_1",
      "sample_name": "sample_1",
      "read_count": 1000,
      "total_bases": 150000,
      "mean_read_length": 150.0,
      "mean_quality": 35.5,
      "results": [
        {
          "test_code": "READ_COUNT",
          "test_name": "Total Reads",
          "value": "1000",
          "unit": "reads"
        },
        {
          "test_code": "TOTAL_BASES",
          "test_name": "Total Bases",
          "value": "150000",
          "unit": "bp"
        },
        {
          "test_code": "MEAN_LENGTH",
          "test_name": "Mean Read Length",
          "value": "150.0",
          "unit": "bp"
        },
        {
          "test_code": "MEAN_QUALITY",
          "test_name": "Mean Quality Score",
          "value": "35.5",
          "unit": "Q"
        }
      ]
    }
  ],
  "galaxy_dataset_id": "f597429621d6eb2b",
  "s3_url": "s3://biomate-instruments/2025/10/30/reads.fastq.gz",
  "errors": []
}
```

## Data Models

### SequenceRead

```python
@dataclass
class SequenceRead:
    read_id: str              # Unique read identifier
    sequence: str             # DNA/RNA sequence
    quality: str              # Phred quality string
    length: int               # Sequence length
    mean_quality: float       # Mean quality score
    gc_content: float         # GC percentage
    metadata: Dict[str, Any]  # Platform-specific metadata
```

### Sample

```python
@dataclass
class Sample:
    sample_id: str                      # Sample identifier
    sample_name: Optional[str]          # Human-readable name
    barcode: Optional[str]              # Barcode sequence
    reads: List[SequenceRead]           # List of reads
    read_count: int                     # Total read count
    total_bases: int                    # Total bases sequenced
    mean_read_length: float             # Average read length
    mean_quality: float                 # Average quality score
    metadata: Dict[str, Any]            # Sample-specific metadata
```

### ParserResult

```python
@dataclass
class ParserResult:
    success: bool                       # Parse success flag
    instrument_type: InstrumentType     # Type of instrument
    data_format: DataFormat             # Data format (FASTQ, etc.)
    instrument_metadata: InstrumentMetadata
    samples: List[Sample]               # Parsed samples
    total_reads: int                    # Total reads across all samples
    total_bases: int                    # Total bases across all samples
    errors: List[str]                   # Error messages
    warnings: List[str]                 # Warning messages
    processing_time: float              # Parse time in seconds
```

## Quality Metrics

### Phred Quality Scores

All parsers calculate Phred quality scores (Q scores):

```
Q = -10 * log10(P)
```

Where P is the probability of an incorrect base call.

| Q Score | Error Rate | Accuracy |
|---------|------------|----------|
| Q10     | 10%        | 90%      |
| Q20     | 1%         | 99%      |
| Q30     | 0.1%       | 99.9%    |
| Q40     | 0.01%      | 99.99%   |
| Q50     | 0.001%     | 99.999%  |

### N50 Metric (Long Reads)

For ONT and PacBio data, N50 is calculated:

> N50 is the read length at which 50% of the total bases are in reads of that length or longer.

This metric is important for assessing long-read sequencing quality.

### HiFi Accuracy (PacBio)

PacBio HiFi reads typically achieve Q30+ (99.9%+ accuracy) through Circular Consensus Sequencing (CCS).

## Testing

### Running Tests

```bash
cd backend
python3 tests/instrument_parsers/test_direct_parsers.py
```

Expected output:
```
======================================================================
Direct Instrument Parser Test Suite
======================================================================

Testing Illumina Parser
✓ File validation passed
✓ Metadata extracted: Illumina MiSeq
✓ Parsing successful
✓ Illumina parser test PASSED

Testing ONT Parser
✓ File validation passed
✓ Metadata extracted: Oxford Nanopore Technologies
✓ Parsing successful
✓ ONT parser test PASSED

Testing PacBio Parser
✓ File validation passed
✓ Metadata extracted: Pacific Biosciences Sequel II/IIe
✓ Parsing successful
✓ PacBio parser test PASSED

======================================================================
Test Summary
======================================================================
Passed: 3/3
Failed: 0/3

✓ All tests PASSED!
```

### Test Files

Test FASTQ files are provided in `tests/instrument_parsers/`:

- `test_illumina.fastq` - 5 Illumina reads
- `test_ont.fastq` - 5 ONT reads with sample barcoding
- `test_pacbio.fastq` - 5 PacBio HiFi reads

## Performance

All parsers support streaming and memory-efficient processing:

- **max_reads parameter:** Limit reads parsed (useful for previews)
- **Streaming:** Process large files without loading all into memory
- **Gzip support:** Automatic decompression of .gz files

Example:
```python
# Parse only first 1000 reads (fast preview)
result = parser.parse('huge_file.fastq.gz', max_reads=1000)
```

## Integration with bioMate

### Workflow Integration

Parsed data automatically integrates with Galaxy:

1. **Dataset Creation:** Results uploaded to Galaxy history
2. **Metadata Tracking:** Run ID, flowcell, instrument model stored
3. **QC Reporting:** Quality metrics available in workflow

### S3 Storage

Original files stored in S3 for audit trail:
```
s3://biomate-instruments/
  ├── 2025/
  │   └── 10/
  │       └── 30/
  │           ├── sample1_illumina.fastq.gz
  │           ├── sample2_ont.fastq.gz
  │           └── sample3_pacbio.fastq
```

## Routing Logic

The unified service auto-routes by instrument type:

```python
routing_map = {
    # Illumina -> direct parsers
    "Illumina": "direct",
    "Illumina_NovaSeq": "direct",
    "Illumina_NextSeq": "direct",
    "Illumina_MiSeq": "direct",

    # ONT -> direct parsers
    "ONT": "direct",
    "ONT_MinION": "direct",
    "ONT_GridION": "direct",
    "ONT_PromethION": "direct",

    # PacBio -> direct parsers
    "PacBio": "direct",
    "PacBio_Sequel": "direct",
    "PacBio_Revio": "direct",

    # Clinical instruments -> LIMS
    "Cobas_C311": "openelis",
    "Sysmex_XN": "senaite",
}
```

## License

All direct parsers are licensed under MIT:

```
MIT License

Copyright (c) 2025 bioMate

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
```

**No GPL dependencies** - Safe for commercial use and proprietary integration.

## Future Enhancements

### Planned Features

1. **BAM/CRAM Support** - Binary alignment formats
2. **FAST5 Support** - ONT raw signal data
3. **Real-time Streaming** - Process data during sequencing
4. **Advanced QC** - Per-base quality, adapter detection, contamination
5. **Variant Calling Integration** - Link to Galaxy variant workflows

### Platform Additions

- MGI/BGI sequencers
- Ion Torrent
- Element Biosciences AVITI
- Singular Genomics G4

## Troubleshooting

### Common Issues

**1. Gzip errors**
```
Solution: Ensure file is valid gzip (gunzip -t file.gz)
```

**2. Memory issues with large files**
```python
# Use max_reads parameter to limit memory
result = parser.parse(file, max_reads=100000)
```

**3. Header parsing failures**
```
Check: Headers must match expected format for each platform
Solution: Set custom metadata extraction in parser subclass
```

**4. Quality encoding issues**
```
Parsers auto-detect Phred+33 vs Phred+64
If issues persist, check for non-standard encoding
```

## Support

For issues or questions:
- GitHub Issues: https://github.com/your-org/biomate/issues
- Documentation: https://docs.biomate.io/instruments/parsers
- Email: support@biomate.io

## References

1. Illumina FASTQ Format: https://support.illumina.com/bulletins/2016/04/fastq-files-explained.html
2. ONT Basecalling: https://nanoporetech.com/nanopore-sequencing-data-analysis
3. PacBio HiFi: https://www.pacb.com/technology/hifi-sequencing/
4. FASTQ Format Specification: https://en.wikipedia.org/wiki/FASTQ_format
5. Phred Quality Scores: https://en.wikipedia.org/wiki/Phred_quality_score
