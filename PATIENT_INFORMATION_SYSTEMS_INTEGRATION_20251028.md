# Patient Information Systems (EMR/EHR) Integration for bioMate
## Clinical Laboratory - EMR Integration Options

**Document Created:** 2025-10-28
**Purpose:** Identify and evaluate patient information systems for integration with bioMate
**Context:** OpenELIS already has proven integrations with several EMR systems via HL7 and FHIR

---

## Executive Summary

**Good News:** OpenELIS (which you're using for clinical lab connectivity) **already has production-ready integrations** with major open-source EMR/EHR systems. You don't need to build these integrations from scratch!

**Best Options for bioMate:**
1. ✅ **OpenMRS + Bahmni** - Production-ready integration with OpenELIS (FHIR + HL7)
2. ✅ **OpenEMR** - Modern FHIR support, widely deployed
3. ⚠️ **GNU Health** - Comprehensive but more complex

---

## Table of Contents

1. [OpenMRS/Bahmni (Recommended)](#1-openmrsbahmni-recommended)
2. [OpenEMR](#2-openemr)
3. [Other Open Source Options](#3-other-open-source-options)
4. [Integration Standards](#4-integration-standards)
5. [Existing OpenELIS Integrations](#5-existing-openelis-integrations)
6. [Implementation Architecture](#6-implementation-architecture)
7. [Quick Start Guide](#7-quick-start-guide)

---

## 1. OpenMRS/Bahmni (Recommended)

### Why This is Your Best Option

**OpenMRS** is the most widely deployed open-source medical record system globally, with **OpenELIS integration already built-in and production-tested**.

### 1.1 OpenMRS Overview

**What is OpenMRS?**
- Open-source medical record system platform
- **2.5 billion patient records** managed globally
- Used in **40+ countries**
- Strong focus on resource-limited settings
- **Built-in HL7 and FHIR support**

**Key Features:**
- Comprehensive patient demographics
- Medical history tracking
- Lab results integration
- Treatment plans
- Drug management
- Reporting and analytics
- Multi-language support

**License:** Mozilla Public License 2.0 (MPL 2.0) ✅ **Commercial-friendly**

**Website:** https://openmrs.org

---

### 1.2 Bahmni (OpenMRS Distribution)

**What is Bahmni?**
- Hospital management system built on OpenMRS
- Integrates EMR + LIMS + imaging + pharmacy
- **OpenELIS bundled by default**
- Production-ready for clinical use

**Components:**
- **Bahmni EMR** (based on OpenMRS)
- **OpenELIS** (laboratory system) - Already integrated!
- **Bahmni Radiology** (PACS integration)
- **Bahmni Pharmacy** (drug dispensing)
- **Odoo ERP** (billing, inventory)

**Integration Features:**
- Doctors order lab tests from EMR
- Tests automatically sync to OpenELIS
- Results flow back to patient record
- Bi-directional real-time sync

**License:** AGPL 3.0 + MPL 2.0 components

**Website:** https://www.bahmni.org

**Deployment Options:**
- Cloud (AWS, Azure, GCP)
- On-premises
- Docker containers
- Kubernetes

---

### 1.3 OpenMRS-OpenELIS Integration

#### **Production-Ready Integration (2025)**

**FHIR Implementation Guide:**
- Official guide published: May 14, 2025
- Website: https://digi-uw.github.io/openelis-global2-fhir-ig/
- Version: OpenELIS GLOBAL2 FHIR IG v0.1.0

**Integration Methods:**

**Method 1: FHIR-Based (Modern, Recommended)**
```
OpenMRS → FHIR Workflow Module → OpenELIS
    ↓                               ↓
Order Tests                    Process Tests
    ↑                               ↑
Receive Results ← FHIR Resources ← Return Results
```

**FHIR Resources Used:**
- **Task** - Workflow coordination
- **Patient** - Demographics
- **ServiceRequest** - Test order
- **DiagnosticReport** - Results container
- **Observation** - Individual test results
- **Specimen** - Sample information
- **Practitioner** - Provider info
- **Encounter** - Clinical context

**Method 2: HL7 V2.5.1 (Legacy, Still Supported)**
- Uses HL7 messaging format
- Proven in production deployments
- More mature, stable

**Real-World Deployments:**
- ✅ **Haiti** - iSantePlus EMR + OpenELIS (pilot)
- ✅ **Multiple countries** - Bahmni + OpenELIS

**Documentation:**
- OpenELIS Docs: https://docs.openelisci.org/en/latest/deployomrs/
- OpenMRS Wiki: https://wiki.openmrs.org/display/projects/Lab+Integration+Workflow

---

### 1.4 SENAITE Integration (Alternative)

**Bahmni can also integrate with SENAITE LIMS** (instead of OpenELIS):

**Integration Approach:**
- HL7-based via Mirth Connect
- Similar to PACS integration pattern
- FHIR-based approach also available

**When to Choose SENAITE:**
- Need 60+ instruments (vs OpenELIS 12+)
- Need spectroscopy/chromatography support
- Research lab requirements

**Caution:** GPL-2.0 license (see licensing analysis doc)

**Resources:**
- OpenMRS Talk: https://talk.openmrs.org/t/introducing-bahmni-hl7-lis-integration-with-senaite-lims/34198

---

## 2. OpenEMR

### 2.1 OpenEMR Overview

**What is OpenEMR?**
- Most popular open-source EHR/EMR
- **100+ million patient records** worldwide
- **70+ countries**
- ONC certified (USA)
- Strong HIPAA compliance

**Key Features:**
- Electronic Health Records (EHR)
- Practice Management
- Scheduling
- e-Prescribing (Surescripts certified)
- Billing (CMS-1500, UB-04)
- **Lab integration** via HL7 and FHIR
- Telehealth
- Patient portal

**License:** GPL-3.0 ⚠️ **GPL licensing considerations**

**Website:** https://www.open-emr.org

---

### 2.2 OpenEMR FHIR Support (2025)

**FHIR Maturity:**
- Full CRUD operations for core resources
- Supports: Patients, Practitioners, Encounters, Observations, Conditions, Medication Requests
- **Lab integration** via FHIR Observations
- Terminology servers: SNOMED CT, LOINC, ICD-10

**Recent Updates (2025):**
- Enhanced interoperability standards
- Improved FHIR API performance
- Better lab result handling

**Lab Integration Features:**
- Facility-specific lab code profiles
- External lab interfaces
- Results import via HL7/FHIR
- Integration with HIEs (Health Information Exchanges)

**Documentation:**
- FHIR Guide: https://www.capminds.com/blog/fhir-openemr-enabling-modern-interoperability-in-2025/
- API Docs: https://www.open-emr.org/wiki/index.php/OpenEMR_API

---

### 2.3 OpenEMR Lab Integration

**Supported Integration Methods:**
- **HL7 V2.x** - Traditional lab messaging
- **FHIR Observations** - Modern approach
- **Direct file import** - CSV/custom formats
- **API integration** - REST endpoints

**Workflow:**
```
OpenEMR → Order Lab Test → External LIMS
    ↓                           ↓
Patient Record            Process Sample
    ↑                           ↑
Display Results ← HL7/FHIR ← Send Results
```

**Integration Partners:**
- Laboratories
- Health Information Exchanges (HIEs)
- Other EHRs
- Billing systems

---

## 3. Other Open Source Options

### 3.1 GNU Health

**Overview:**
- Comprehensive Hospital Information System (HIS)
- Includes EMR, LIMS, imaging, pharmacy, genetics
- Strong on public health
- **Built-in laboratory module**

**License:** GPL-3.0 ⚠️

**Pros:**
- All-in-one solution
- Strong international focus
- Laboratory module included
- Genetics/genomics support

**Cons:**
- More complex to deploy
- Steeper learning curve
- Smaller community vs OpenMRS/OpenEMR
- GPL licensing

**Website:** https://www.gnuhealth.org

**Use Case:** Comprehensive hospital system with research focus

---

### 3.2 Emerging FHIR-Native Options

#### **Ottehr**
- First FHIR-native, open-source EHR
- Production-ready
- Modular: telehealth, charting, e-prescriptions, scheduling
- **Modern architecture**
- Website: https://www.ottehr.com

#### **Beda EMR**
- FHIR-Native, open source
- Built on Aidbox FHIR APIs
- Pre-configured auth, user management, access control
- Website: https://beda.software/emr

#### **Metriport**
- Data aggregation API
- Access to largest health information networks
- Lab results in FHIR R4, C-CDA, PDF
- Website: https://www.metriport.com

**Note:** These are newer, less proven in production

---

## 4. Integration Standards

### 4.1 HL7 V2.x (Legacy Standard)

**What is HL7 V2.x?**
- Health Level Seven messaging standard
- **87% adoption** in healthcare providers
- Text-based protocol
- Bi-directional communication

**Common Message Types:**
- **ORM** - Order messages (lab test orders)
- **ORU** - Observation result unsolicited (lab results)
- **ADT** - Admit/Discharge/Transfer (patient demographics)
- **ACK** - Acknowledgment

**Lab Workflow:**
```
EMR sends ORM → LIMS receives order
LIMS processes → LIMS sends ORU
EMR receives results → EMR sends ACK
```

**Pros:**
- Mature, proven
- Wide vendor support
- Real-time messaging
- Bi-directional

**Cons:**
- Complex to implement
- Text parsing required
- Limited flexibility
- Vendor variations

---

### 4.2 FHIR (Modern Standard)

**What is FHIR?**
- Fast Healthcare Interoperability Resources
- RESTful API approach
- JSON/XML data format
- **Modern replacement for HL7 V2**

**Benefits:**
- Web-based (HTTP/REST)
- JSON format (easy parsing)
- Modular resources
- Better documentation
- Mobile-friendly

**Lab Integration Resources:**
- **ServiceRequest** - Test order
- **DiagnosticReport** - Results container
- **Observation** - Individual results
- **Specimen** - Sample details
- **Task** - Workflow management

**Lab Workflow:**
```
POST /ServiceRequest → Create lab order
GET /Task → Monitor status
GET /DiagnosticReport → Retrieve results
GET /Observation → Individual test values
```

**Pros:**
- Modern, web-native
- Easy to implement
- Good documentation
- Growing adoption

**Cons:**
- Newer (less mature than HL7 V2)
- Not all vendors support yet
- Multiple FHIR versions (R4, R5)

---

### 4.3 Standards Terminology

**Required for Lab Integration:**

**LOINC (Logical Observation Identifiers Names and Codes)**
- Standard for lab tests and observations
- **Required for HL7/FHIR lab messages**
- Example: 718-7 = Hemoglobin [Mass/volume] in Blood

**SNOMED CT (Clinical Terms)**
- Clinical terminology
- Diagnoses, procedures, findings
- Used in EMR-LIMS communication

**ICD-10/11 (International Classification of Diseases)**
- Diagnosis codes
- Required for billing
- Clinical context for tests

**Website Resources:**
- LOINC: https://loinc.org (free)
- SNOMED CT: https://www.snomed.org (license required for some uses)
- ICD: https://www.who.int/standards/classifications/classification-of-diseases

---

## 5. Existing OpenELIS Integrations

### 5.1 Built-in EMR Connectors

**OpenELIS Has Production-Ready Integrations With:**

| EMR System | Integration Method | Status | Documentation |
|------------|-------------------|--------|---------------|
| **OpenMRS** | FHIR + HL7 V2.5.1 | ✅ Production | https://docs.openelisci.org/en/latest/deployomrs/ |
| **Bahmni** | Built-in (OpenMRS) | ✅ Production | https://bahmni.atlassian.net/wiki/spaces/BAH/ |
| **iSantePlus** (Haiti) | FHIR | ✅ Pilot | Part of OpenMRS ecosystem |
| **Generic FHIR** | FHIR R4 | ✅ Available | https://digi-uw.github.io/openelis-global2-fhir-ig/ |
| **Generic HL7 V2** | HL7 V2.5.1 | ✅ Available | Via OpenHIE architecture |

---

### 5.2 Integration Architecture

**OpenELIS FHIR Server:**
- Built-in FHIR endpoint
- Powered by HAPI FHIR JPA Server
- Supports FHIR R4
- RESTful API

**Endpoints:**
```
POST   /fhir/Task                 # Submit lab order
GET    /fhir/Task/{id}            # Check status
GET    /fhir/DiagnosticReport     # Get results
GET    /fhir/Observation          # Get individual tests
POST   /fhir/ServiceRequest       # Order tests
GET    /fhir/Patient/{id}         # Patient info
```

**Configuration:**
- Located in: `/var/lib/openelis-global/properties/hapi_application.yaml`
- FHIR server runs alongside OpenELIS
- Database: Shared PostgreSQL

---

## 6. Implementation Architecture

### 6.1 Recommended Architecture for bioMate

```
┌─────────────────────────────────────────────────────────┐
│                   bioMate Platform                       │
│                 (Orchestration & Analytics)              │
└────────────┬──────────────────────┬─────────────────────┘
             │                      │
             ↓                      ↓
┌────────────────────┐   ┌────────────────────────────┐
│  OpenELIS          │   │  OpenMRS/Bahmni            │
│  (LIMS)            │←→│  (EMR/EHR)                 │
│                    │   │                            │
│  - Clinical labs   │   │  - Patient demographics    │
│  - Instruments     │   │  - Medical records         │
│  - Results         │   │  - Orders/prescriptions    │
└────────────────────┘   │  - Clinical notes          │
         ↑               └────────────────────────────┘
         │                           ↑
         │                           │
         ↓                           ↓
┌─────────────────────────────────────────────────────────┐
│              FHIR Integration Layer                      │
│  - ServiceRequest (orders)                              │
│  - DiagnosticReport (results)                           │
│  - Observation (test values)                            │
│  - Task (workflow)                                      │
└─────────────────────────────────────────────────────────┘
```

---

### 6.2 Data Flow

**Order Flow (EMR → LIMS):**
```
1. Clinician orders lab test in OpenMRS
2. OpenMRS creates FHIR ServiceRequest
3. OpenMRS creates FHIR Task (status: requested)
4. OpenELIS receives Task via FHIR API
5. OpenELIS creates internal lab order
6. OpenELIS updates Task (status: in-progress)
7. bioMate triggers workflow based on test type
```

**Result Flow (LIMS → EMR):**
```
1. Instrument generates results → OpenELIS
2. Technician validates results in OpenELIS
3. OpenELIS creates FHIR DiagnosticReport
4. OpenELIS creates FHIR Observations
5. OpenELIS updates Task (status: completed)
6. OpenMRS receives DiagnosticReport via FHIR
7. OpenMRS displays results in patient record
8. bioMate ingests results for advanced analytics
```

---

### 6.3 Integration Points for bioMate

**bioMate Can Hook Into:**

**1. Pre-Analytical:**
- Sample collection (EMR)
- Order management (EMR → LIMS)
- Workflow optimization

**2. Analytical:**
- Instrument connectivity (OpenELIS)
- Multi-omics pipelines (Galaxy)
- Quality control

**3. Post-Analytical:**
- Result validation (OpenELIS)
- Advanced analytics (bioMate)
- Clinical decision support
- Report generation

**4. Data Aggregation:**
- Patient demographics (EMR)
- Clinical context (EMR)
- Lab results (LIMS)
- Multi-omics data (bioMate)
- Longitudinal analysis

---

## 7. Quick Start Guide

### 7.1 Option 1: Bahmni (Easiest)

**Step 1: Deploy Bahmni**
```bash
# Docker deployment
git clone https://github.com/Bahmni/bahmni-docker
cd bahmni-docker
docker-compose up -d
```

**Step 2: Access Systems**
- Bahmni EMR: http://localhost:8080
- OpenELIS: http://localhost:8052 (bundled!)
- Default credentials: superman / Admin123

**Step 3: Configure Integration**
- Already configured out-of-the-box
- Orders sync automatically
- Results flow back to EMR

**Step 4: Connect bioMate**
```bash
# Access OpenELIS via REST API
curl http://localhost:8052/api/analyzer/results

# Access OpenMRS via FHIR
curl http://localhost:8080/openmrs/ws/fhir2/R4/DiagnosticReport
```

---

### 7.2 Option 2: OpenMRS + OpenELIS (More Control)

**Step 1: Deploy OpenMRS**
```bash
# Docker deployment
docker run -d --name openmrs \
  -p 8080:8080 \
  openmrs/openmrs-core:latest
```

**Step 2: Deploy OpenELIS**
```bash
# Use your existing OpenELIS deployment
# (from bioMate roadmap)
```

**Step 3: Install OpenMRS FHIR Module**
- Navigate to: Administration → Manage Modules
- Install: FHIR2 Module
- Configure FHIR endpoints

**Step 4: Configure Integration**
- Follow guide: https://docs.openelisci.org/en/latest/deployomrs/
- Set up FHIR workflow module
- Map lab tests (LOINC codes)
- Configure result routing

---

### 7.3 Option 3: OpenEMR (Alternative)

**Step 1: Deploy OpenEMR**
```bash
# Docker deployment
git clone https://github.com/openemr/openemr-devops
cd openemr-devops/docker/production
docker-compose up -d
```

**Step 2: Access System**
- URL: http://localhost
- Complete setup wizard
- Create admin account

**Step 3: Configure Lab Integration**
- Navigate to: Administration → Globals → Lab
- Enable HL7 Lab Interface
- Configure lab result import
- Set up FHIR endpoints

**Step 4: Connect to OpenELIS**
- Use HL7 V2.5.1 messaging
- Configure OpenELIS to send ORU messages
- Map lab codes (LOINC)

---

## 8. Comparison Matrix

| Feature | OpenMRS/Bahmni | OpenEMR | GNU Health |
|---------|---------------|---------|------------|
| **License** | MPL 2.0 ✅ | GPL-3.0 ⚠️ | GPL-3.0 ⚠️ |
| **OpenELIS Integration** | ✅ Built-in | ⚠️ Via HL7 | ⚠️ Custom |
| **FHIR Support** | ✅ Native | ✅ Full | ⚠️ Limited |
| **HL7 V2 Support** | ✅ Yes | ✅ Yes | ⚠️ Limited |
| **Deployment Complexity** | ⭐⭐⭐ Easy | ⭐⭐ Medium | ⭐ Complex |
| **Global Deployments** | ✅ 40+ countries | ✅ 70+ countries | ⚠️ Limited |
| **Community Size** | ⭐⭐⭐ Large | ⭐⭐⭐ Large | ⭐ Small |
| **Documentation** | ⭐⭐⭐ Excellent | ⭐⭐ Good | ⭐ Limited |
| **Lab Focus** | ✅ Strong | ⭐⭐ Moderate | ⭐⭐ Moderate |
| **Production Ready** | ✅ Yes | ✅ Yes | ⚠️ Less mature |
| **bioMate Integration** | ✅ Easy | ⭐⭐ Medium | ⚠️ Complex |

---

## 9. Recommendations for bioMate

### Recommended: OpenMRS/Bahmni

**Why:**
1. ✅ **OpenELIS integration already built-in** - No development needed
2. ✅ **MPL 2.0 license** - Commercial-friendly (matches OpenELIS)
3. ✅ **FHIR-native** - Modern, well-documented
4. ✅ **Production-proven** - 2.5B patient records globally
5. ✅ **Active community** - Large developer base
6. ✅ **Good documentation** - Comprehensive guides
7. ✅ **International focus** - Matches your multi-country strategy

**Implementation Timeline:**
- **Week 1:** Deploy Bahmni (1 day with Docker)
- **Week 2:** Configure test catalog, map LOINC codes
- **Week 3:** Test order → result workflow
- **Week 4:** Connect bioMate analytics layer

---

### Alternative: OpenEMR

**When to Choose:**
- USA-focused deployment (ONC certified)
- Need strong e-prescribing (Surescripts)
- Want larger US community
- Prefer more mature billing features

**Trade-offs:**
- GPL-3.0 license (more restrictive)
- No built-in OpenELIS integration
- More configuration required

---

### Not Recommended: Build Custom

**Why not build your own EMR integration?**
- ❌ Takes 12-18 months development
- ❌ Requires deep HL7/FHIR expertise
- ❌ Regulatory complexity (HIPAA, GDPR)
- ❌ Diverts resources from core bioMate value
- ❌ OpenMRS/Bahmni already solves this

**Better:** Use existing integrations, focus on your differentiation (multi-omics analytics)

---

## 10. Next Steps

### Immediate Actions (Week 1)

**Day 1-2: Deploy Bahmni Test Instance**
```bash
# Clone Bahmni Docker
git clone https://github.com/Bahmni/bahmni-docker
cd bahmni-docker

# Deploy locally
docker-compose up -d

# Access Bahmni EMR
open http://localhost:8080

# Access bundled OpenELIS
open http://localhost:8052
```

**Day 3-4: Test OpenELIS Integration**
1. Create test patient in Bahmni
2. Order lab test (CBC, Chemistry panel)
3. Verify order appears in OpenELIS
4. Enter results in OpenELIS
5. Verify results appear in Bahmni patient record

**Day 5: Connect bioMate**
1. Query OpenMRS FHIR API for patients
2. Query OpenELIS for lab results
3. Verify data flow
4. Design bioMate integration layer

---

### Month 1: Production Pilot

**Week 1:** Deploy to test environment
**Week 2:** Configure lab test catalog
**Week 3:** Train users (EMR + LIMS)
**Week 4:** Run parallel (old system + new system)

---

### Month 2-3: Scale

**Month 2:**
- Production deployment
- Add instruments via OpenELIS
- Configure bioMate analytics pipelines
- Integrate Galaxy workflows

**Month 3:**
- Multi-omics data integration
- Advanced analytics dashboards
- Clinical decision support

---

## Resources

### Documentation
- **OpenMRS FHIR**: https://openmrs.atlassian.net/wiki/spaces/docs/pages/26935684/FHIR
- **OpenELIS-OpenMRS**: https://docs.openelisci.org/en/latest/deployomrs/
- **Bahmni**: https://bahmni.atlassian.net/wiki/spaces/BAH/
- **OpenEMR FHIR**: https://www.capminds.com/blog/fhir-openemr-enabling-modern-interoperability-in-2025/

### Community
- **OpenMRS Talk**: https://talk.openmrs.org
- **Bahmni Community**: https://talk.openmrs.org/c/software/bahmni
- **OpenELIS Talk**: https://talk.openelis-global.org
- **OpenEMR Community**: https://community.open-emr.org

### Code Repositories
- **OpenMRS**: https://github.com/openmrs
- **Bahmni**: https://github.com/Bahmni
- **OpenELIS**: https://github.com/I-TECH-UW/OpenELIS-Global-2
- **OpenEMR**: https://github.com/openemr/openemr

---

**Document Version:** 1.0
**Last Updated:** 2025-10-28
**Maintained By:** bioMate Platform Team
**Next Review:** After Bahmni pilot deployment
