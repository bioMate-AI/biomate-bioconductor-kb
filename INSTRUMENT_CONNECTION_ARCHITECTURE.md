# Instrument Connection Architecture for bioMate

**Document Created:** 2025-10-29
**Purpose:** Explain how clinical/research instruments connect to the bioMate platform

---

## The Core Question: How Do Instruments Connect?

Laboratory instruments (analyzers, sequencers, spectrometers) generate data that needs to flow into bioMate for analysis. Here's the complete architecture.

---

## 1. What Instruments Actually Produce

### Clinical Analyzers (Hematology, Chemistry, etc.)
**Output:** Structured result files containing sample measurements

Example from a **Sysmex XN Hematology Analyzer**:
```csv
Sample ID,Test,Result,Unit,Flags
SAM001,WBC,7.2,10^3/uL,N
SAM001,RBC,4.5,10^6/uL,N
SAM001,HGB,14.2,g/dL,N
SAM001,HCT,42.1,%,N
```

Example from a **Roche Cobas Chemistry Analyzer**:
```
^H|\^&|||Roche Diagnostics^COBAS c111^001|||||||P|1|
P|1||SAM001||Smith^John||19800101|M
O|1|SAM001||^^^GLU\^^^CREA\^^^BUN|R||20251029093000
R|1|^^^GLU|120|mg/dL|||N|||
R|2|^^^CREA|1.1|mg/dL|||N|||
L|1|N
```

### Sequencing Instruments (Illumina, ONT, PacBio)
**Output:** FASTQ files with sequencing reads

Example from **Illumina NovaSeq**:
```
@Instrument:RunID:FlowCell:Lane:Tile:X:Y
AGCTGATCGATCGATCGATCG
+
IIIIIIIIIIIIIIIIIIIII
```

### Mass Spectrometry (LCMS, GCMS)
**Output:** Proprietary or standard formats (mzML, mzXML)

Example from **Thermo Fisher LCMS**:
- `.RAW` files (proprietary)
- Can be converted to `.mzML` (open format)

---

## 2. Current Industry Standard: File-Based Transfer

Most instruments use **file-based data export**:

```
┌─────────────────────────────────────────────────────────┐
│                  INSTRUMENT                              │
│  ┌────────────┐                                          │
│  │  Analyzer  │ ──> Measurement                          │
│  │  Hardware  │                                          │
│  └────────────┘                                          │
│        ↓                                                 │
│  ┌────────────┐                                          │
│  │  Internal  │ ──> Data Processing                      │
│  │  Software  │                                          │
│  └────────────┘                                          │
│        ↓                                                 │
│  ┌────────────┐                                          │
│  │   Export   │ ──> Writes file to:                      │
│  │            │     • Network share                      │
│  │            │     • USB drive                          │
│  │            │     • Serial port (ASTM)                 │
│  └────────────┘                                          │
└─────────────────────────────────────────────────────────┘
```

### Connection Methods:

1. **Network File Share** (Most Common)
   - Instrument writes to `\\server\share\results\`
   - LIMS polls directory for new files

2. **USB/Local Disk**
   - Instrument writes to local USB drive
   - Manual or automated transfer to LIMS

3. **Serial/ASTM Protocol** (Real-time)
   - Bi-directional communication
   - Instrument sends results over serial/TCP
   - LIMS can send orders to instrument

4. **Direct Database** (Rare)
   - Instrument writes to database
   - LIMS queries database

---

## 3. Three Architecture Options for bioMate

### Option 1: Direct File Import (Simplest, P1 Priority)

```
┌────────────────────────────────────────────────────────────────┐
│                     DIRECT FILE IMPORT                          │
└────────────────────────────────────────────────────────────────┘

Instrument
    ↓
Exports File (CSV, ASTM, FASTQ, etc.)
    ↓
┌─────────────────────────────────────┐
│   File Transfer to bioMate          │
│   • Network share                   │
│   • Web upload UI                   │
│   • S3 bucket upload                │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│   bioMate Instrument Parser Service │  ← NEW SERVICE (Python)
│   ┌───────────────────────────────┐ │
│   │ Roche Cobas Parser            │ │
│   │ Sysmex XN Parser              │ │
│   │ Illumina FASTQ Parser         │ │
│   │ Generic CSV Parser            │ │
│   └───────────────────────────────┘ │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│   Normalized Data (JSON)            │
│   {                                 │
│     "sample_id": "SAM001",          │
│     "results": [{                   │
│       "test": "WBC",                │
│       "value": 7.2,                 │
│       "unit": "10^3/uL"             │
│     }]                              │
│   }                                 │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│   bioMate Galaxy Workflow           │
│   • Upload as dataset               │
│   • Trigger analysis workflow       │
│   • Generate report                 │
└─────────────────────────────────────┘
```

**Pros:**
- ✅ Simple architecture
- ✅ No GPL licensing issues (we write parsers)
- ✅ Fast to implement (2-3 weeks)
- ✅ Full control over data processing

**Cons:**
- ❌ Must implement parsers for each instrument (effort)
- ❌ Limited to file-based instruments
- ❌ No built-in QC/validation

**Implementation Effort:**
- 3-5 parsers: 2-3 weeks
- 10+ parsers: 4-6 weeks

---

### Option 2: SENAITE Microservice (Best Coverage, GPL-Isolated)

```
┌────────────────────────────────────────────────────────────────┐
│              SENAITE MICROSERVICE (GPL-ISOLATED)                │
└────────────────────────────────────────────────────────────────┘

Instrument
    ↓
Exports File
    ↓
┌─────────────────────────────────────┐
│   SENAITE Container (Docker)        │  ← GPL-2.0 CODE (ISOLATED)
│   • 60+ built-in parsers            │
│   • File-based import API           │
│   • ASTM protocol support           │
│   • QC/validation rules             │
└─────────────────────────────────────┘
    ↓ (HTTP/REST API - Network boundary, no code linking)
┌─────────────────────────────────────┐
│   bioMate SENAITE Client            │  ← OUR CODE (MIT/Proprietary)
│   • REST API calls only             │
│   • No SENAITE code import          │
│   • JSON data exchange              │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│   Normalized Data (JSON)            │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│   bioMate Galaxy Workflow           │
└─────────────────────────────────────┘
```

**GPL-2.0 Isolation Strategy:**

The key is **network separation** - SENAITE runs as a completely separate service:

```
┌──────────────────────────────────┐     ┌──────────────────────────┐
│  SENAITE Container (GPL-2.0)     │     │  bioMate (Proprietary)   │
│  ────────────────────────────    │     │  ────────────────────    │
│  • Run in Docker                 │     │  • No SENAITE imports    │
│  • Expose REST API               │◄────┤  • HTTP client only      │
│  • Parse instrument files        │     │  • JSON requests         │
│  • Return JSON results           ├────►│  • No code dependency    │
└──────────────────────────────────┘     └──────────────────────────┘
        (GPL-2.0 isolated)                    (Clean, proprietary)
```

**API Calls (Network communication, not code linking):**

```bash
# Upload instrument file to SENAITE
curl -X POST http://senaite:8080/api/import \
  -F "file=@roche_cobas_results.txt" \
  -F "instrument=Cobas_C311"

# Response (JSON, no GPL contamination)
{
  "success": true,
  "samples": [
    {
      "sample_id": "SAM001",
      "results": [
        {"test": "GLU", "value": 120, "unit": "mg/dL"}
      ]
    }
  ]
}
```

**Pros:**
- ✅ 60+ instruments supported immediately
- ✅ GPL-safe via network API
- ✅ SENAITE's QC/validation included
- ✅ Well-tested parsers (20 years development)

**Cons:**
- ⚠️ Requires running SENAITE container
- ⚠️ Dependency on external system
- ⚠️ API must be carefully designed for isolation

**Implementation Effort:**
- SENAITE Docker setup: 1 week
- REST API wrapper: 2 weeks
- Integration with bioMate: 1 week
- **Total: 4 weeks**

---

### Option 3: OpenELIS Integration (MPL-2.0, Commercial-Friendly)

```
┌────────────────────────────────────────────────────────────────┐
│              OPENELIS INTEGRATION (MPL-2.0)                     │
└────────────────────────────────────────────────────────────────┘

Instrument
    ↓
Exports File
    ↓
┌─────────────────────────────────────┐
│   OpenELIS Container                │  ← MPL-2.0 (Commercial OK)
│   • 8+ core parsers                 │
│   • Plugin system                   │
│   • FHIR support                    │
└─────────────────────────────────────┘
    ↓ (REST API)
┌─────────────────────────────────────┐
│   bioMate OpenELIS Client           │  ← Can use MPL code directly
│   • Can import MPL code             │     if needed (file-level)
│   • REST API preferred              │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│   bioMate Galaxy Workflow           │
└─────────────────────────────────────┘
```

**Pros:**
- ✅ MPL-2.0 (commercial-friendly, can link code)
- ✅ 8+ core instruments
- ✅ Active development
- ✅ FHIR/LIS integration ready

**Cons:**
- ❌ Fewer instruments than SENAITE (8 vs 60)
- ❌ Less mature than SENAITE for instruments

**Implementation Effort:**
- Similar to SENAITE: 4 weeks

---

## 4. Recommended Hybrid Approach (P1 Strategy)

Combine approaches based on priority:

### **Week 1-2: Quick Start (Direct File Import)**

Implement 3 most common instruments directly:
1. **Illumina Sequencers** (FASTQ) - Research priority
2. **Roche Cobas** (Chemistry) - Clinical priority
3. **Sysmex XN** (Hematology) - Clinical priority

```python
# bioMate direct parsers (no dependencies)
class IlluminaFASTQParser:
    def parse(self, file_path):
        """Parse Illumina FASTQ files"""
        # Simple, no external dependencies

class RocheCobasParser:
    def parse(self, file_path):
        """Parse Roche Cobas chemistry results"""

class SysmexXNParser:
    def parse(self, file_path):
        """Parse Sysmex hematology results"""
```

### **Week 3-6: Add SENAITE Microservice**

Deploy SENAITE for expanded instrument support:

```yaml
# docker-compose.yml
services:
  senaite:
    image: senaite/senaite:latest
    ports:
      - "8080:8080"
    environment:
      - SITE_ID=senaite

  biomate-instrument-service:
    build: ./instrument-service
    depends_on:
      - senaite
    environment:
      - SENAITE_URL=http://senaite:8080
```

```python
# bioMate instrument service (our code)
class InstrumentService:
    def import_file(self, file_path, instrument_type):
        # Try direct parsers first
        if instrument_type in ['illumina', 'cobas', 'sysmex']:
            return self.direct_parse(file_path)

        # Fall back to SENAITE for others
        return self.senaite_parse(file_path, instrument_type)

    def senaite_parse(self, file_path, instrument_type):
        # Network API call (GPL-safe)
        response = requests.post(
            'http://senaite:8080/api/import',
            files={'file': open(file_path, 'rb')},
            data={'instrument': instrument_type}
        )
        return response.json()
```

---

## 5. Data Flow: Complete Example

Let's trace a sample through the system:

### Step 1: Instrument Analysis

```
Lab Technician runs blood sample "SAM001" on Sysmex XN
    ↓
Sysmex XN performs CBC (Complete Blood Count)
    ↓
Sysmex exports results to network share:
  \\lab-server\results\sysmex_20251029_093000.csv
```

### Step 2: File Transfer to bioMate

**Option A: Manual Upload**
```
User uploads file via bioMate web UI
    ↓
File stored in S3: s3://biomate-uploads/instruments/sysmex_20251029_093000.csv
```

**Option B: Automated Polling**
```
bioMate polls network share every 5 minutes
    ↓
Detects new file
    ↓
Copies to S3
```

### Step 3: Parsing

```
bioMate Instrument Service detects new file
    ↓
Identifies instrument type from filename/content: "Sysmex XN"
    ↓
Routes to SysmexXNParser (direct) OR SENAITE (API)
    ↓
Extracts structured data:
{
  "sample_id": "SAM001",
  "instrument": "Sysmex XN",
  "timestamp": "2025-10-29T09:30:00Z",
  "results": [
    {"test": "WBC", "value": 7.2, "unit": "10^3/uL", "ref_range": "4.5-11.0"},
    {"test": "RBC", "value": 4.5, "unit": "10^6/uL", "ref_range": "4.5-5.9"},
    {"test": "HGB", "value": 14.2, "unit": "g/dL", "ref_range": "13.5-17.5"}
  ]
}
```

### Step 4: Upload to Galaxy

```
bioMate creates Galaxy dataset from parsed results
    ↓
POST /api/histories/{history_id}/contents
{
  "type": "dataset",
  "name": "SAM001_CBC_Results",
  "file_content": <JSON above>
}
    ↓
Galaxy dataset ID: "abc123"
```

### Step 5: Trigger Workflow

```
User (or automation) triggers analysis workflow:
"Analyze CBC results and check for anomalies"
    ↓
bioMate AI generates workflow:
1. Load CBC dataset (dataset_id: abc123)
2. Apply reference range checks
3. Flag abnormal values
4. Generate interpretation report
    ↓
Execute on Galaxy backend
    ↓
Results returned to user
```

---

## 6. Implementation Plan for bioMate

### Phase 1: Direct File Import (Week 1-2, P1)

**Deliverables:**
1. Instrument file upload UI
2. 3 direct parsers (Illumina, Roche, Sysmex)
3. Galaxy dataset creation from parsed data
4. Basic workflow integration

**Files to Create:**
```
backend/lib/galaxy/instruments/
├── __init__.py
├── parsers/
│   ├── __init__.py
│   ├── base.py              # Abstract parser
│   ├── illumina_fastq.py    # Illumina FASTQ
│   ├── roche_cobas.py       # Roche Cobas
│   └── sysmex_xn.py         # Sysmex XN
├── service.py               # Main instrument service
└── api.py                   # FastAPI endpoints

frontend/client/src/components/
├── instrument-upload.tsx    # Upload UI
└── instrument-results.tsx   # Results display

frontend/server/routes.ts
└── /api/instruments/*       # New routes
```

### Phase 2: SENAITE Microservice (Week 3-6, P1)

**Deliverables:**
1. SENAITE Docker deployment
2. SENAITE REST API wrapper
3. Expanded to 60+ instruments
4. GPL isolation documentation

**Files to Create:**
```
docker/
├── docker-compose.instruments.yml
└── senaite/
    └── Dockerfile

backend/lib/galaxy/instruments/
├── senaite_client.py        # REST client
└── parsers/
    └── senaite_proxy.py     # SENAITE proxy parser

docs/
└── GPL_ISOLATION_STRATEGY.md
```

---

## 7. Security & Compliance Considerations

### PHI/PII in Instrument Data

Instrument files may contain:
- Patient names
- Medical record numbers
- Dates of birth
- Test results

**Requirements:**
- ✅ HIPAA-compliant storage (encrypted S3)
- ✅ Access controls (RBAC)
- ✅ Audit logging
- ✅ De-identification options

### Data Retention

- **Raw instrument files:** 7 years (regulatory)
- **Parsed data:** Indefinite
- **Analysis results:** Indefinite

---

## 8. Key Takeaways

1. **Instruments produce files** (CSV, ASTM, FASTQ, etc.)
2. **File transfer** is standard (network share, upload, polling)
3. **Parsing** extracts structured data
4. **bioMate receives** normalized JSON
5. **Galaxy workflows** analyze the data

**Three approaches:**
- **Direct (Week 1-2):** 3 instruments, simple, no dependencies
- **SENAITE (Week 3-6):** 60+ instruments, GPL-isolated via API
- **OpenELIS (Alternative):** 8+ instruments, MPL-2.0 friendly

**Recommended:** Start with direct parsers (fast), add SENAITE microservice (comprehensive coverage).

---

**Document Version:** 1.0
**Next Steps:** Implement Phase 1 direct file import
