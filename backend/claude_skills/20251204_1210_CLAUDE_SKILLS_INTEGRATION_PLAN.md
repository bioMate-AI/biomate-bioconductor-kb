# Claude Skills Integration Plan

**Date**: 2024-12-04
**Target**: galaxy_ai_tools.db

---

## Resource Type Classification

### Type 1: Databases (Query Tools)
**Pattern**: `biomni/database/query_{name}` → Category: `Data Source`

| Database | Tool ID | Description | Auth Required |
|----------|---------|-------------|---------------|
| COSMIC | `biomni/database/query_cosmic` | Cancer somatic mutations | Yes (academic free) |
| ClinPGx | `biomni/database/query_clinpgx` | Pharmacogenomics annotations | No |
| USPTO | `biomni/database/query_uspto` | Patent search | No |
| ZINC | `biomni/database/query_zinc` | Commercial compounds | No |

**Schema fields to populate**:
- `tool_id`: `biomni/database/query_{name}`
- `name`: `Query {Name}`
- `category`: `Data Source`
- `description`: From SKILL.md
- `inputs`: JSON with query parameters
- `outputs`: JSON with return types
- `requirements`: `[{"name": "requests", "type": "pip"}, {"name": "pandas", "type": "pip"}]`
- `help_text`: From SKILL.md quick start
- `scientific_context`: Use cases from SKILL.md

---

### Type 2: Python Packages (Tool Dependencies)
**Pattern**: `biomni/package/{name}` → Category: `Computational chemistry` / `Machine Learning` / etc.

| Package | Tool ID | Category | Use Case |
|---------|---------|----------|----------|
| DeepChem | `biomni/package/deepchem` | Machine Learning | Molecular property prediction |
| TorchDrug | `biomni/package/torchdrug` | Machine Learning | Graph neural networks |
| torch_geometric | `biomni/package/torch_geometric` | Machine Learning | GNN foundation |
| MedChem | `biomni/package/medchem` | Computational chemistry | Medicinal chemistry filters |
| Molfeat | `biomni/package/molfeat` | Computational chemistry | Molecular featurization |
| Datamol | `biomni/package/datamol` | Computational chemistry | Molecule manipulation |
| PyTDC | `biomni/package/pytdc` | Data Source | Therapeutics Data Commons |
| gget | `biomni/package/gget` | Data Source | Gene/protein retrieval |
| CellxGene Census | `biomni/package/cellxgene_census` | Single Cell | Large-scale scRNA data |
| COBRApy | `biomni/package/cobrapy` | Systems Biology | Metabolic modeling |
| Arboreto | `biomni/package/arboreto` | Single Cell | Gene regulatory networks |
| PyMC | `biomni/package/pymc` | Statistics | Bayesian modeling |
| PyMatGen | `biomni/package/pymatgen` | Materials science | Materials toolkit |

**Schema fields to populate**:
- `tool_id`: `biomni/package/{name}`
- `name`: Package name
- `category`: Appropriate domain
- `description`: From SKILL.md
- `requirements`: `[{"name": "{package}", "type": "pip", "version": "..."}]`
- `inputs`: Common function signatures
- `outputs`: Return types
- `examples`: From SKILL.md workflows
- `usage_guide`: Installation + basic usage

---

### Type 3: External Integrations (API Connectors)
**Pattern**: `biomni/integration/{name}` → Category: `Web Services`

| Integration | Tool ID | Type | Description |
|-------------|---------|------|-------------|
| Benchling | `biomni/integration/benchling` | LIMS/ELN | Biotech R&D platform |
| Opentrons | `biomni/integration/opentrons` | Lab Automation | Robot protocol execution |
| DNAnexus | `biomni/integration/dnanexus` | Cloud Platform | Genomics cloud |
| LatchBio | `biomni/integration/latchbio` | Cloud Platform | Bioinformatics cloud |
| OMERO | `biomni/integration/omero` | Data Management | Imaging data management |
| LabArchive | `biomni/integration/labarchive` | ELN | Electronic lab notebook |

**Schema fields to populate**:
- `tool_id`: `biomni/integration/{name}`
- `name`: `{Name} Integration`
- `category`: `Web Services`
- `description`: Integration capabilities
- `requirements`: API client packages
- `inputs`: API endpoints/methods
- `outputs`: Response formats
- `help_text`: Authentication setup

---

## Implementation Steps

### Phase 1: Test Database Setup
```bash
# Create test database
sqlite3 galaxy_ai_tools_test.db < schema.sql
```

### Phase 2: Add Type 1 - Database Query Tools (4 items)
```sql
INSERT INTO tools (tool_id, name, category, description, ...)
VALUES ('biomni/database/query_cosmic', 'Query Cosmic', 'Data Source', ...);
```

### Phase 3: Add Type 2 - Package Tools (13 items)
```sql
INSERT INTO tools (tool_id, name, category, description, requirements, ...)
VALUES ('biomni/package/deepchem', 'DeepChem', 'Machine Learning', ...);
```

### Phase 4: Add Type 3 - Integration Tools (6 items)
```sql
INSERT INTO tools (tool_id, name, category, description, ...)
VALUES ('biomni/integration/benchling', 'Benchling Integration', 'Web Services', ...);
```

### Phase 5: Validation
```sql
-- Verify counts
SELECT category, COUNT(*) FROM tools WHERE tool_id LIKE 'biomni/%' GROUP BY category;

-- Test queries
SELECT * FROM tools WHERE name LIKE 'Query Cosmic';
SELECT * FROM tools WHERE requirements LIKE '%deepchem%';
```

### Phase 6: Merge to Production
```sql
-- Attach test db and copy
ATTACH 'galaxy_ai_tools_test.db' AS test;
INSERT INTO main.tools SELECT * FROM test.tools WHERE tool_id LIKE 'biomni/%';
```

---

## Data Sources for Each Entry

| Resource | Source File | Key Sections |
|----------|-------------|--------------|
| COSMIC | `scientific-databases/cosmic-database/SKILL.md` | Overview, Quick Start, Data Types |
| DeepChem | `scientific-packages/deepchem/SKILL.md` | Overview, Workflows, API Reference |
| Benchling | `scientific-integrations/benchling-integration/SKILL.md` | Overview, Authentication, Endpoints |

---

## Priority Order

1. **HIGH** (implement first):
   - Query Cosmic (cancer research critical)
   - DeepChem (AI drug discovery)
   - TorchDrug (graph ML)
   - MedChem (lead optimization)
   - Benchling (enterprise integration)

2. **MEDIUM** (implement second):
   - Molfeat, Datamol, PyTDC
   - gget, CellxGene Census
   - COBRApy, Arboreto
   - Opentrons

3. **LOW** (implement last):
   - ClinPGx, USPTO, ZINC
   - PyMC, PyMatGen
   - DNAnexus, LatchBio, LabArchive, OMERO

---

## Total Items to Add: 23

| Type | Count | Category |
|------|-------|----------|
| Databases | 4 | Data Source |
| Packages | 13 | Various |
| Integrations | 6 | Web Services |
