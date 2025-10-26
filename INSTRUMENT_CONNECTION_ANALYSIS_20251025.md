# Instrument Connection Systems Analysis

**Document Created:** 2025-10-25
**Repositories Analyzed:**
- `bioMate-AI/connect_biomate` (Mirth Connect)
- `bioMate-AI/OpenELIS-Global-2-biomate` (OpenELIS Global 2)

---

## Executive Summary

Both repositories provide **laboratory instrument integration capabilities** that could potentially serve as a bridge between clinical laboratory instruments and the bioMate platform:

1. **Mirth Connect (connect_biomate)**: Healthcare integration engine for HL7 messaging and data transformation
2. **OpenELIS Global 2 (OpenELIS-Global-2-biomate)**: Laboratory Information System (LIS) with built-in analyzer interface capabilities

**Key Finding:** OpenELIS Global 2 is more directly suited for instrument connections, supporting **8+ core analyzers** plus unlimited plugin-based analyzers. Mirth Connect serves as a general-purpose healthcare data integration middleware.

---

## Table of Contents

1. [Mirth Connect Analysis](#1-mirth-connect-analysis)
2. [OpenELIS Global 2 Analysis](#2-openelis-global-2-analysis)
3. [Supported Instruments](#3-supported-instruments)
4. [Connection Mechanisms](#4-connection-mechanisms)
5. [Integration with bioMate Platform](#5-integration-with-biomate-platform)
6. [Recommendations](#6-recommendations)

---

## 1. Mirth Connect Analysis

### 1.1 What is Mirth Connect?

**Mirth Connect** (formerly known as Mirth) is an open-source **healthcare integration engine** developed by NextGen Healthcare. It's essentially a healthcare-specific ETL (Extract, Transform, Load) tool.

**Repository:** `bioMate-AI/connect_biomate`
- **Original Project:** NextGen Healthcare's Mirth Connect
- **License:** Mozilla Public License 2.0
- **Language:** Java
- **Type:** Healthcare data integration middleware

### 1.2 Core Capabilities

Mirth Connect specializes in:

1. **Message Translation**
   - Converts between different healthcare message formats (HL7, XML, JSON, FHIR, etc.)
   - Supports custom transformations using JavaScript

2. **Protocol Support**
   - HL7 v2.x (Primary healthcare messaging standard)
   - HL7 FHIR
   - XML
   - JSON
   - Database connectivity (JDBC)
   - File-based transfers
   - HTTP/HTTPS
   - TCP/MLLP (Minimal Lower Layer Protocol)
   - SOAP/REST web services

3. **Data Routing**
   - Route messages to multiple destinations
   - Filter messages based on content
   - Queue management
   - Error handling and retry logic

4. **Channel-based Architecture**
   - Each integration pathway is a "channel"
   - Channels have: Source → Transformer → Filter → Destination

### 1.3 Key Features

```
┌─────────────────────────────────────────────────────────────┐
│                    Mirth Connect                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────┐      ┌──────────────┐      ┌─────────────┐   │
│  │  Source  │ -->  │ Transformer  │ -->  │ Destination │   │
│  │          │      │   (Filter)   │      │             │   │
│  └──────────┘      └──────────────┘      └─────────────┘   │
│                                                              │
│  Sources:                 Transformations:    Destinations: │
│  • File Reader            • HL7 → XML         • Database    │
│  • Database Reader        • XML → JSON        • File Writer │
│  • TCP Listener           • Custom JS         • HL7 Sender  │
│  • HTTP Listener          • Field mapping     • HTTP POST   │
│  • DICOM                  • Validation        • SOAP        │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 1.4 Relevance to Instrument Connection

**Direct Instrument Support:** ❌ **None**
- Mirth Connect does NOT directly connect to laboratory instruments
- It's a **middleware layer** for data exchange between systems

**Potential Use Cases:**
1. **Receive HL7 results** from a LIS (like OpenELIS) and forward to bioMate
2. **Transform data formats** from various sources into bioMate-compatible formats
3. **Route laboratory data** from multiple sources to bioMate
4. **Bridge systems** that speak different protocols

**Example Workflow:**
```
Instrument → OpenELIS → Mirth Connect → bioMate Platform
            (via ASTM)  (HL7 to REST)   (REST API)
```

---

## 2. OpenELIS Global 2 Analysis

### 2.1 What is OpenELIS Global 2?

**OpenELIS Global** is an enterprise-level **Laboratory Information System (LIS)** designed for public health laboratories.

**Repository:** `bioMate-AI/OpenELIS-Global-2-biomate`
- **Original Project:** University of Washington / I-TECH
- **License:** MPL 2.0
- **Language:** Java (backend), React (frontend)
- **Type:** Laboratory Information Management System (LIMS/LIS)

### 2.2 Core Capabilities

OpenELIS Global provides comprehensive laboratory management:

1. **Sample Management**
   - Sample registration and tracking
   - Barcode support
   - Sample routing and workflows

2. **Test Management**
   - Test ordering and scheduling
   - Test result entry (manual and automated)
   - Quality control
   - Validation workflows

3. **Analyzer Integration** ⭐ **KEY FEATURE**
   - Import results from clinical analyzers
   - Bi-directional communication (send orders, receive results)
   - Plugin-based architecture for adding new analyzers
   - File-based and ASTM protocol support

4. **Reporting**
   - Patient results
   - Statistical reports
   - Quality metrics

5. **Standards Compliance**
   - ISO accreditation support
   - SLIPTA compliance
   - FHIR interoperability

### 2.3 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   OpenELIS Global 2                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              Frontend (React)                        │   │
│  │  • Sample Registration  • Results Review             │   │
│  │  • Test Ordering        • Reports                    │   │
│  └──────────────────────────────────────────────────────┘   │
│                          ↕                                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │           Backend (Java/Spring Boot)                 │   │
│  │  • Business Logic  • Workflows  • Validation         │   │
│  └──────────────────────────────────────────────────────┘   │
│                          ↕                                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │             Analyzer Interface Layer                 │   │
│  │  ┌────────────┐  ┌────────────┐  ┌───────────────┐  │   │
│  │  │ Core       │  │ Plugin     │  │ ASTM Bridge   │  │   │
│  │  │ Analyzers  │  │ Analyzers  │  │ (External)    │  │   │
│  │  └────────────┘  └────────────┘  └───────────────┘  │   │
│  └──────────────────────────────────────────────────────┘   │
│                          ↕                                   │
│           ┌──────────────┴──────────────┐                   │
│           ↓                             ↓                   │
│  ┌─────────────────┐         ┌──────────────────┐          │
│  │  File Import    │         │  ASTM Protocol   │          │
│  │  (CSV, Excel)   │         │  (Serial/TCP)    │          │
│  └─────────────────┘         └──────────────────┘          │
│           ↓                             ↓                   │
└───────────┼─────────────────────────────┼───────────────────┘
            ↓                             ↓
    Laboratory Analyzers          Laboratory Analyzers
    (File export)                 (ASTM bi-directional)
```

---

## 3. Supported Instruments

### 3.1 OpenELIS Core Analyzers (Built-in Support)

OpenELIS Global 2 includes **built-in readers** for the following analyzers:

| # | Analyzer Name | Manufacturer | Type | Protocol | File Format |
|---|---------------|--------------|------|----------|-------------|
| 1 | **Cobas C311** | Roche | Chemistry | File | Custom |
| 2 | **Cobas Integra** | Roche | Chemistry | File | Custom |
| 3 | **Cobas TaqMan** | Roche | Molecular (PCR) | File | Custom |
| 4 | **Cobas TaqMan DBS** | Roche | Molecular (DBS) | File | Custom |
| 5 | **Evolis** | Bio-Rad | Immunology | File | Custom |
| 6 | **FACSCalibur** | BD Biosciences | Flow Cytometry | File | Custom |
| 7 | **FACSCanto** | BD Biosciences | Flow Cytometry | File | Custom |
| 8 | **Sysmex XN Series** | Sysmex | Hematology | File | Custom |

**Source Location:**
```
/src/main/java/org/openelisglobal/analyzerimport/analyzerreaders/
├── CobasC311Reader.java
├── CobasReader.java
├── CobasTaqmanReader.java
├── CobasTaqmanDBSReader.java
├── EvolisReader.java
├── FacscaliburReader.java
├── FACSCantoReader.java
└── SysmexReader.java
```

### 3.2 Plugin-Based Analyzers (Extensible)

OpenELIS supports **unlimited additional analyzers** via a plugin system:

| Analyzer | Protocol | Status |
|----------|----------|--------|
| **Aquios CL** | ASTM (Bi-directional) | Plugin available |
| **GeneXpert** | File | Configured in test data |
| **PocH-100i** | File | Configured in test data |
| **Any ASTM-compatible analyzer** | ASTM | Via ASTM bridge |
| **Custom analyzers** | File/ASTM | Via plugin development |

**Plugin Repository:** `https://github.com/openelisglobal/openelisglobal-plugins`

**Precompiled Plugins Available:**
- Available from Dropbox: [Plugin Repository](https://www.dropbox.com/sh/xzjxca5ya73dylt/AACf35yDhjerS1V-C1SVNgJ2a?dl=0)
- Example: Aquios-0.0.2.jar

### 3.3 Generic Support

**ASTM E1394 Protocol Support:**
- Via `astm-http-bridge` external service
- Supports any analyzer that implements ASTM protocol
- Bi-directional communication (send orders, receive results)

**File-based Support:**
- CSV import via `AnalyzerXLSLineReader`
- Excel import via `AnalyzerXLSLLineReader`
- Custom format parsers can be developed

---

## 4. Connection Mechanisms

### 4.1 File-Based Import (Most Common)

**Workflow:**
```
┌─────────────────────────────────────────────────────────────┐
│                    File-Based Import                         │
└─────────────────────────────────────────────────────────────┘

1. Analyzer exports results to file
   ↓
2. File written to "staging directory"
   ↓
3. Perl script monitors staging directory
   ↓
4. Script copies file to "transmissionQueue"
   ↓
5. Script POSTs file to OpenELIS via curl
   URL: https://localhost:8443/api/OpenELIS-Global/importAnalyzer
   ↓
6. OpenELIS processes file with appropriate reader
   ↓
7. Results imported and matched to existing orders
   ↓
8. File deleted from transmissionQueue
```

**Key Components:**

1. **Staging Directory**: Where analyzer writes files
2. **TransmissionQueue**: Temporary storage before import
3. **Perl Script**: `FlatFileTransport.pl`
   - Monitors staging directory
   - Uses curl to POST files to OpenELIS
   - Handles authentication
   - Manages timestamps to avoid duplicates

**Configuration:**
```perl
# Example configuration
my $curlExe = 'C:\curl\curl.exe';
my $upLoadtargetURL = 'https://localhost:8443/OpenELIS-Global/importAnalyzer';
my $upLoadUserName = 'analyzer_user';
my $upLoadPassword = 'password';
my $stagingDir1 = ".\\staging";  # Windows
# my $stagingDir1 = ".//staging";  # Linux
```

### 4.2 ASTM Protocol (Bi-directional)

**ASTM E1394 Standard:**
- Industry standard for clinical laboratory instrument communication
- Serial (RS-232) or TCP/IP transport
- Bi-directional: Send orders TO analyzer, receive results FROM analyzer

**Workflow:**
```
┌─────────────────────────────────────────────────────────────┐
│               ASTM Bi-directional Workflow                   │
└─────────────────────────────────────────────────────────────┘

OpenELIS → ASTM-HTTP Bridge → Analyzer (Order)
   ↑              ↑                ↓
   └──────────────┴────────────────┘ (Result)

Components:
1. OpenELIS with Analyzer Plugin (e.g., Aquios)
2. ASTM-HTTP Bridge Service
   - Receives HTTP requests from OpenELIS
   - Converts to ASTM protocol messages
   - Sends via serial/TCP to analyzer
   - Receives ASTM responses
   - Forwards back to OpenELIS via HTTP
3. Analyzer workstation
```

**ASTM-HTTP Bridge:**
- External service: `https://github.com/CalebSLane/astm-http-bridge`
- Docker-based deployment
- Configuration file defines:
  - Serial port or TCP connection
  - Message format details
  - Timeouts and retry logic

**Example: Aquios Workflow**
1. Create order in OpenELIS with sample ID
2. OpenELIS plugin sends order to analyzer via ASTM bridge
3. Lab runs sample on Aquios analyzer
4. On Aquios: Navigate to Review → Select sample → "Send to LIS"
5. OpenELIS polls for result (via "Poll for Result" action)
6. Result imported and matched to order

### 4.3 Plugin Architecture

**How Plugins Work:**

1. **Plugin Directory:** `/var/lib/openelis-global/plugins/`
2. **Plugin Format:** JAR file containing analyzer-specific code
3. **Auto-discovery:** Plugins loaded at application startup
4. **Interface Implementation:** Must implement analyzer plugin interface

**Creating a Plugin:**
```java
// Example structure
public class MyAnalyzerPlugin implements AnalyzerPlugin {

    @Override
    public String getAnalyzerName() {
        return "My Custom Analyzer";
    }

    @Override
    public AnalyzerResults importResults(InputStream dataStream) {
        // Parse analyzer-specific format
        // Map to OpenELIS test codes
        // Return standardized results
    }

    @Override
    public List<AnalyzerAction> getSupportedActions() {
        // Define available actions (import, export, poll, etc.)
    }
}
```

**Mapping Test Names:**
```java
// Example from Aquios plugin
// Analyzer test name → LOINC code → OpenELIS test
"CD3PCT" → LOINC: 8122-4 → OpenELIS test: "CD3 percentage"
```

---

## 5. Integration with bioMate Platform

### 5.1 Potential Integration Architectures

#### Option 1: OpenELIS as Middleware

```
┌─────────────────────────────────────────────────────────────┐
│            Option 1: OpenELIS as Middleware                  │
└─────────────────────────────────────────────────────────────┘

Laboratory Instruments
    ↓ (ASTM / File export)
OpenELIS Global 2
    - Import analyzer results
    - Validate and normalize data
    - Map to standard test codes (LOINC)
    ↓ (REST API / FHIR)
bioMate Platform
    - Receive standardized results
    - Integrate with workflows
    - Analysis and visualization
```

**Pros:**
- ✅ Direct instrument support (8+ analyzers built-in)
- ✅ Proven, production-ready system
- ✅ Handles complex lab workflows
- ✅ Data validation and QC
- ✅ LOINC standardization
- ✅ FHIR interoperability

**Cons:**
- ❌ Heavy system (full LIS)
- ❌ Requires database and infrastructure
- ❌ May have features bioMate doesn't need

#### Option 2: Extract Analyzer Readers Only

```
┌─────────────────────────────────────────────────────────────┐
│         Option 2: Extract Analyzer Readers Only              │
└─────────────────────────────────────────────────────────────┘

Laboratory Instruments
    ↓ (File export)
Extracted Analyzer Readers
    - Lightweight Java services
    - Parse instrument-specific formats
    - No database required
    ↓ (REST API)
bioMate Platform
    - Direct integration
    - Custom workflow handling
```

**Pros:**
- ✅ Lightweight
- ✅ Only necessary components
- ✅ Easy to customize
- ✅ Direct control

**Cons:**
- ❌ Requires significant refactoring
- ❌ Lose validation and QC features
- ❌ Need to reimplement mappings
- ❌ Maintenance burden

#### Option 3: Mirth Connect as Integration Layer

```
┌─────────────────────────────────────────────────────────────┐
│       Option 3: Mirth Connect as Integration Layer           │
└─────────────────────────────────────────────────────────────┘

Laboratory Instruments
    ↓ (ASTM / HL7)
Hospital/Lab LIS (e.g., OpenELIS, Cerner, Epic)
    ↓ (HL7 v2/FHIR)
Mirth Connect
    - Transform HL7 to JSON/REST
    - Route to multiple destinations
    - Handle errors and retries
    ↓ (REST API / Custom format)
bioMate Platform
```

**Pros:**
- ✅ Handles multiple data sources
- ✅ Protocol transformation
- ✅ Enterprise-grade routing
- ✅ Works with existing hospital systems

**Cons:**
- ❌ No direct instrument connection
- ❌ Requires existing LIS
- ❌ Complex setup
- ❌ Another system to maintain

#### Option 4: Hybrid Approach (RECOMMENDED)

```
┌─────────────────────────────────────────────────────────────┐
│              Option 4: Hybrid Approach                       │
└─────────────────────────────────────────────────────────────┘

Laboratory Instruments (Direct)
    ↓ (ASTM / File)
OpenELIS Analyzer Plugins (Microservice)
    - Lightweight Docker containers
    - Only analyzer import functionality
    - Expose REST API
    ↓
         ↓ (JSON/REST)                 ↓ (JSON/REST)
         ↓                             ↓
    bioMate Platform  ←──────  Mirth Connect (Optional)
                                       ↑
                                       ↓ (HL7)
                              External Lab Systems
```

**Pros:**
- ✅ Direct instrument support via OpenELIS plugins
- ✅ Lightweight (containerized microservices)
- ✅ Optional Mirth for hospital system integration
- ✅ Flexible and scalable
- ✅ Best of both worlds

**Cons:**
- ❌ Custom development required
- ❌ Need to maintain plugin microservices

### 5.2 Implementation Recommendations

#### Phase 1: Proof of Concept (2-4 weeks)

1. **Set up OpenELIS in Docker**
   ```bash
   git clone https://github.com/bioMate-AI/OpenELIS-Global-2-biomate.git
   cd OpenELIS-Global-2-biomate
   docker-compose up -d
   ```

2. **Test with Sample Analyzer**
   - Use Sysmex or Cobas file import
   - Validate data mapping
   - Test API integration with bioMate

3. **Evaluate Integration Approaches**
   - Test OpenELIS REST API
   - Test FHIR endpoints
   - Determine data mapping requirements

#### Phase 2: Develop Adapter Layer (4-6 weeks)

1. **Create bioMate Analyzer Adapter Service**
   ```
   /biomate-analyzer-adapter
   ├── /plugins
   │   ├── SysmexPlugin.jar
   │   ├── CobasPlugin.jar
   │   └── FacsPlugin.jar
   ├── /api
   │   ├── /import         POST /api/import/sysmex
   │   ├── /status         GET  /api/status
   │   └── /mappings       GET  /api/mappings
   └── docker-compose.yml
   ```

2. **Implement REST API**
   - Endpoint to upload analyzer files
   - Endpoint to query import status
   - Endpoint to retrieve parsed results
   - Webhook support for real-time notifications

3. **Data Mapping Layer**
   - Map analyzer test codes to bioMate ontology
   - Handle unit conversions
   - Validate result ranges

#### Phase 3: Production Deployment (2-4 weeks)

1. **Containerize Services**
   - Docker images for each component
   - Kubernetes deployment configs
   - Health checks and monitoring

2. **Security**
   - Authentication and authorization
   - Encrypted communication
   - Audit logging

3. **Documentation**
   - API documentation
   - Supported analyzer list
   - Setup guides for new analyzers

### 5.3 API Design Example

**bioMate Analyzer Adapter REST API:**

```yaml
# Import analyzer results
POST /api/v1/analyzer/import
Content-Type: multipart/form-data

Parameters:
  - analyzer_type: string (sysmex, cobas, facs, etc.)
  - file: binary
  - metadata: json (optional)

Response:
  {
    "import_id": "uuid",
    "status": "processing",
    "analyzer": "Sysmex XN-1000",
    "sample_count": 24,
    "timestamp": "2025-10-25T15:30:00Z"
  }

# Check import status
GET /api/v1/analyzer/import/{import_id}

Response:
  {
    "import_id": "uuid",
    "status": "completed",
    "results": [
      {
        "sample_id": "12345",
        "tests": [
          {
            "test_code": "WBC",
            "test_name": "White Blood Cell Count",
            "value": 7.5,
            "unit": "10^9/L",
            "reference_range": "4.0-11.0",
            "flag": "normal"
          }
        ]
      }
    ],
    "errors": [],
    "completed_at": "2025-10-25T15:31:23Z"
  }

# List supported analyzers
GET /api/v1/analyzer/supported

Response:
  {
    "analyzers": [
      {
        "name": "Sysmex XN-1000",
        "type": "hematology",
        "manufacturer": "Sysmex",
        "protocols": ["file"],
        "file_formats": [".csv", ".txt"],
        "tests_supported": 30
      },
      {
        "name": "Cobas C311",
        "type": "chemistry",
        "manufacturer": "Roche",
        "protocols": ["file"],
        "file_formats": [".dat"],
        "tests_supported": 50
      }
    ]
  }
```

---

## 6. Recommendations

### 6.1 Short-term (Next 3 months)

1. **Evaluate OpenELIS**
   - Set up test instance
   - Import sample data from target analyzers
   - Test API integration
   - **Estimated effort:** 1-2 weeks

2. **Identify Priority Analyzers**
   - Survey bioMate target labs
   - Determine most common analyzers
   - Prioritize based on:
     - Market penetration
     - Ease of integration
     - bioMate use case importance

3. **Develop PoC Integration**
   - Build simple adapter for 1-2 analyzers
   - Test end-to-end workflow
   - Validate data accuracy
   - **Estimated effort:** 3-4 weeks

### 6.2 Medium-term (3-6 months)

1. **Productionize Adapter Service**
   - Containerize
   - Add monitoring and logging
   - Implement error handling
   - Security hardening
   - **Estimated effort:** 4-6 weeks

2. **Expand Analyzer Support**
   - Add 5-10 most common analyzers
   - Develop plugin framework
   - Create documentation for adding new analyzers
   - **Estimated effort:** 6-8 weeks

3. **Optional: Mirth Connect Integration**
   - Set up Mirth Connect instance
   - Create channels for hospital system integration
   - Test HL7 transformations
   - **Estimated effort:** 2-4 weeks

### 6.3 Long-term (6-12 months)

1. **Enterprise Features**
   - Multi-tenant support
   - Advanced analytics on import data
   - Automated anomaly detection
   - Real-time streaming support

2. **Standards Compliance**
   - FHIR R4 support
   - IHE LAB profiles
   - Regulatory compliance (CLIA, CAP)

3. **Marketplace**
   - Community plugin repository
   - Vendor-certified analyzers
   - Third-party integrations

---

## 7. Supported Analyzer Summary

### 7.1 Confirmed Supported Analyzers

| Category | Manufacturer | Analyzer | Support Type |
|----------|--------------|----------|--------------|
| **Hematology** | Sysmex | XN Series (XN-1000, etc.) | ✅ Core |
| **Chemistry** | Roche | Cobas Integra | ✅ Core |
| **Chemistry** | Roche | Cobas C311 | ✅ Core |
| **Molecular** | Roche | Cobas TaqMan | ✅ Core |
| **Molecular** | Roche | Cobas TaqMan DBS | ✅ Core |
| **Molecular** | Cepheid | GeneXpert | ✅ Configured |
| **Immunology** | Bio-Rad | Evolis | ✅ Core |
| **Flow Cytometry** | BD Biosciences | FACSCalibur | ✅ Core |
| **Flow Cytometry** | BD Biosciences | FACSCanto | ✅ Core |
| **Flow Cytometry** | Beckman Coulter | Aquios CL | ✅ Plugin (ASTM) |
| **Hematology** | Sysmex | PocH-100i | ✅ Configured |
| **Generic** | Any | ASTM-compatible | ✅ Via ASTM Bridge |
| **Generic** | Any | File-based (CSV/Excel) | ✅ Core |

**Total:** 13+ specific analyzers + unlimited via plugins and ASTM

### 7.2 Easily Extendable To

Based on the plugin architecture and ASTM support:

- **Abbott:** Architect series, Alinity, m2000
- **Beckman Coulter:** DxH series, AU series
- **Siemens:** ADVIA series, Atellica
- **Ortho Clinical Diagnostics:** VITROS series
- **bioMérieux:** VITEK systems
- **Any ASTM E1394-compliant analyzer**

---

## 8. Technical Details

### 8.1 OpenELIS Database Schema

**Relevant Tables:**

```sql
-- Analyzers
CREATE TABLE analyzer (
    id INTEGER PRIMARY KEY,
    name VARCHAR(255),
    machine_id VARCHAR(255),
    analyzer_type VARCHAR(50),
    description TEXT,
    location VARCHAR(255),
    is_active BOOLEAN,
    has_setup_page BOOLEAN,
    lastupdated TIMESTAMP
);

-- Analyzer Test Mappings
CREATE TABLE analyzer_test_mapping (
    analyzer_id INTEGER REFERENCES analyzer(id),
    analyzer_test_name VARCHAR(255),
    test_id INTEGER REFERENCES test(id),
    lastupdated TIMESTAMP,
    PRIMARY KEY (analyzer_id, analyzer_test_name)
);

-- Analyzer Results
CREATE TABLE analyzer_results (
    id INTEGER PRIMARY KEY,
    analyzer_id INTEGER REFERENCES analyzer(id),
    sample_id VARCHAR(255),
    test_id INTEGER,
    result_value VARCHAR(255),
    units VARCHAR(50),
    result_timestamp TIMESTAMP,
    import_timestamp TIMESTAMP,
    status VARCHAR(50)
);
```

### 8.2 File Format Examples

**Sysmex XN-1000 Export Format:**
```csv
Sample ID,Test Code,Result,Unit,Flag,Timestamp
12345,WBC,7.5,10^9/L,,2025-10-25 10:30:00
12345,RBC,4.8,10^12/L,,2025-10-25 10:30:00
12345,HGB,14.2,g/dL,,2025-10-25 10:30:00
```

**Cobas Export Format:**
```
@@@ RESULTS
Sample ID: 12345
Test: GLU, Result: 95, Unit: mg/dL, Status: F
Test: CREA, Result: 1.1, Unit: mg/dL, Status: F
@@@ END
```

### 8.3 ASTM Message Example

```
STX
H|\^&|||Aquios^CL^001|||||||P|1|20251025103000
P|1|||12345
O|1|12345||^^^CD3PCT|R||||||||||||||||||||||F
R|1|^^^CD3PCT|65.5|%||N||F||||20251025103000
L|1|N
ETX
```

---

## 9. Conclusion

### Key Findings

1. **OpenELIS Global 2** provides **direct instrument connectivity** for 8+ clinical analyzers with built-in support and unlimited extensibility via plugins.

2. **Mirth Connect** is a **general-purpose healthcare integration engine** that does NOT directly connect to instruments but can transform and route data from other systems.

3. **Best approach for bioMate:** Use OpenELIS analyzer plugins as a **lightweight microservice** to handle instrument connections, optionally with Mirth Connect for hospital system integration.

4. **Supported instruments:** Comprehensive support for major clinical analyzers including:
   - Hematology: Sysmex XN series, PocH-100i
   - Chemistry: Roche Cobas series
   - Molecular: Cepheid GeneXpert, Roche TaqMan
   - Flow Cytometry: BD FACS series, Beckman Aquios
   - Immunology: Bio-Rad Evolis

5. **Integration mechanisms:**
   - File-based import (most common)
   - ASTM bi-directional protocol
   - Plugin architecture for custom analyzers

### Next Steps

1. **Immediate:** Set up OpenELIS test environment and validate analyzer import for bioMate's target instruments
2. **Short-term:** Develop lightweight adapter service using OpenELIS analyzer readers
3. **Medium-term:** Expand support to 10+ most common analyzers in target markets
4. **Long-term:** Build comprehensive instrument connectivity platform with community plugin ecosystem

---

**Document Version:** 1.0
**Last Updated:** 2025-10-25
**Status:** Analysis Complete - Ready for Planning
