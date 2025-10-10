#!/usr/bin/env python3
"""
Create comprehensive markdown reference document for Galaxy data tools and datasets
"""
import json
from datetime import datetime
from collections import defaultdict

def format_parameters(params):
    """Format tool parameters for markdown"""
    if not params:
        return "None"

    lines = []
    for param in params[:5]:  # Limit to first 5 params for brevity
        if isinstance(param, dict):
            name = param.get('name', 'unknown')
            param_type = param.get('type', 'unknown')
            desc = param.get('label', param.get('description', ''))
            lines.append(f"  - `{name}` ({param_type}): {desc[:80]}")

    if len(params) > 5:
        lines.append(f"  - ... and {len(params) - 5} more parameters")

    return "\n".join(lines) if lines else "None"

def main():
    # Load reference data
    with open('/Users/jingqiwang/biomate/backend/reference_data_complete.json', 'r') as f:
        data = json.load(f)

    tools = data['tools']
    datasets = data['datasets']
    metaboanalyst_dbs = data['metaboanalyst_databases']

    # Create markdown content
    timestamp = datetime.now().strftime('%Y-%m-%d')
    md = []

    md.append(f"# Galaxy Data Tools and Datasets Reference")
    md.append(f"**Generated:** {timestamp}\n")
    md.append("## Table of Contents\n")
    md.append("1. [Overview](#overview)")
    md.append("2. [Galaxy Data Source Tools](#galaxy-data-source-tools)")
    md.append("3. [Local Datasets](#local-datasets)")
    md.append("4. [MetaboAnalyst SQLite Databases](#metaboanalyst-sqlite-databases)")
    md.append("5. [API Query Patterns](#api-query-patterns)")
    md.append("6. [Usage Guidelines](#usage-guidelines)\n")

    # Overview
    md.append("## Overview\n")
    md.append(f"This document provides comprehensive reference information for integrating chemical and biological databases into Galaxy workflows.\n")
    md.append("### Summary Statistics\n")
    md.append(f"- **Galaxy Data Tools:** {len(tools)}")
    md.append(f"- **Local Datasets:** {len(datasets)}")
    md.append(f"- **MetaboAnalyst Databases:** {len(metaboanalyst_dbs)}")
    md.append(f"- **Total Data Resources:** {len(tools) + len(datasets) + len(metaboanalyst_dbs)}\n")

    # Tools by database
    md.append("### Tools by Database Type\n")
    db_types = defaultdict(list)
    for tool_id, tool in tools.items():
        name = tool.get('name', '')
        if 'PubChem' in name or 'PubChem' in tool.get('description', ''):
            db_types['PubChem'].append(tool)
        elif 'ChEMBL' in name or 'ChEMBL' in tool.get('description', ''):
            db_types['ChEMBL'].append(tool)
        elif 'KEGG' in name or 'KEGG' in tool.get('description', ''):
            db_types['KEGG'].append(tool)
        elif 'UniProt' in name or 'UniProt' in tool.get('description', ''):
            db_types['UniProt'].append(tool)
        elif 'Reactome' in name or 'Reactome' in tool.get('description', ''):
            db_types['Reactome'].append(tool)
        elif 'HMDB' in name or 'HMDB' in tool.get('description', ''):
            db_types['HMDB'].append(tool)

    for db_name in sorted(db_types.keys()):
        md.append(f"- **{db_name}:** {len(db_types[db_name])} tools")
    md.append("")

    # Galaxy Data Source Tools
    md.append("## Galaxy Data Source Tools\n")
    md.append("Detailed information about existing Galaxy tools that query chemical and biological databases.\n")

    for db_name in ['PubChem', 'ChEMBL', 'KEGG', 'UniProt', 'Reactome', 'HMDB']:
        if db_name not in db_types:
            continue

        md.append(f"### {db_name} Tools ({len(db_types[db_name])} tools)\n")

        for tool in db_types[db_name][:10]:  # Limit to 10 tools per database
            md.append(f"#### {tool.get('name', 'Unknown')}\n")
            md.append(f"**Tool ID:** `{tool.get('id', 'Unknown')}`  ")
            md.append(f"**Category:** {tool.get('category', 'Unknown')}  ")
            md.append(f"**Version:** {tool.get('version', 'Unknown')}  ")
            md.append(f"**Repository:** {tool.get('repo_owner', 'Unknown')}/{tool.get('repo_name', 'Unknown')}\n")

            desc = tool.get('description', 'No description available')
            md.append(f"**Description:** {desc[:200]}{'...' if len(desc) > 200 else ''}\n")

            # Parameters
            params = tool.get('parameters', [])
            if params:
                md.append("**Key Parameters:**")
                md.append(format_parameters(params))
                md.append("")

            # Inputs/Outputs
            inputs = tool.get('inputs', [])
            outputs = tool.get('outputs', [])
            if inputs:
                md.append(f"**Inputs:** {len(inputs)} input(s)")
            if outputs:
                md.append(f"**Outputs:** {len(outputs)} output(s)")
            md.append("")

    # Local Datasets
    md.append("## Local Datasets\n")
    md.append(f"Information about {len(datasets)} local datasets available for Galaxy workflows.\n")

    # Group by format
    by_format = defaultdict(list)
    for ds_name, ds in datasets.items():
        fmt = ds.get('format', 'unknown')
        by_format[fmt].append((ds_name, ds))

    md.append("### Datasets by Format\n")
    for fmt in sorted(by_format.keys(), key=lambda x: -len(by_format[x])):
        count = len(by_format[fmt])
        md.append(f"- **{fmt.upper()}:** {count} datasets")
    md.append("")

    # List key datasets
    md.append("### Key Datasets\n")
    for fmt in ['csv', 'tsv', 'parquet', 'txt']:
        if fmt not in by_format:
            continue

        md.append(f"#### {fmt.upper()} Datasets ({len(by_format[fmt])} files)\n")

        for ds_name, ds in sorted(by_format[fmt])[:15]:  # First 15 per format
            name = ds.get('name', ds_name)
            size = ds.get('size', 'Unknown')
            path = ds.get('path', 'Unknown')

            md.append(f"- **{name}**")
            md.append(f"  - Size: {size}")
            md.append(f"  - Path: `{path}`")

            schema = ds.get('schema', {})
            if schema:
                md.append(f"  - Type: {schema.get('type', 'unknown')}")
                if 'has_header' in schema:
                    md.append(f"  - Header: {schema['has_header']}")

            index_cols = ds.get('index_columns', [])
            if index_cols:
                md.append(f"  - Index columns: {', '.join(index_cols[:5])}")
            md.append("")

        if len(by_format[fmt]) > 15:
            md.append(f"*... and {len(by_format[fmt]) - 15} more {fmt} datasets*\n")

    # MetaboAnalyst SQLite Databases
    md.append("## MetaboAnalyst SQLite Databases\n")
    md.append("Detailed schema information for MetaboAnalyst MS/MS spectral databases.\n")

    md.append("### Database Overview\n")
    md.append("| Database | Size | Tables | Purpose |")
    md.append("|----------|------|--------|---------|")

    db_purposes = {
        'MS2ID_Pathway': 'Pathway-focused metabolites',
        'MS2ID_PathwayNL': 'Pathway metabolites (no lipids)',
        'MS2ID_Bio': 'Biological metabolites',
        'MS2ID_BioNL': 'Biological metabolites (no lipids)',
        'MS2ID_Exposomics': 'Exposomics compounds',
        'MS2ID_ExposomicsNL': 'Exposomics (no lipids)',
        'MS2ID_Lipids': 'Lipid compounds',
        'MS2ID_LipidsNL': 'Lipid compounds (no lipids subset)',
        'FragsAnnotateDB': 'Fragment annotation database',
        'FragsAnnotateDBNL': 'Fragment annotation (no lipids)'
    }

    for db_name, db_info in sorted(metaboanalyst_dbs.items()):
        size_gb = db_info['size_gb']
        table_count = len(db_info['schema'])
        base_name = db_name.replace('.sqlite', '').split('_v')[0]
        purpose = db_purposes.get(base_name, 'MS/MS spectral database')
        md.append(f"| {db_name} | {size_gb:.1f} GB | {table_count} | {purpose} |")
    md.append("")

    # Detailed schemas for first 2 databases
    md.append("### Database Schemas\n")
    for db_name, db_info in list(metaboanalyst_dbs.items())[:2]:
        md.append(f"#### {db_name}\n")
        md.append(f"**Size:** {db_info['size_gb']:.2f} GB  ")
        md.append(f"**Tables:** {len(db_info['schema'])}\n")

        md.append("**Table Schemas:**\n")
        for table_name, table_info in list(db_info['schema'].items())[:5]:  # First 5 tables
            md.append(f"##### {table_name}")
            md.append(f"*Columns: {table_info['column_count']}*\n")
            md.append("| Column | Type |")
            md.append("|--------|------|")
            for col in table_info['columns'][:10]:  # First 10 columns
                md.append(f"| {col['name']} | {col['type']} |")
            if len(table_info['columns']) > 10:
                md.append(f"| ... | *{len(table_info['columns']) - 10} more columns* |")
            md.append("")

        if len(db_info['schema']) > 5:
            md.append(f"*... and {len(db_info['schema']) - 5} more tables*\n")

    md.append("*Note: Other databases follow similar schema patterns.*\n")

    # API Query Patterns
    md.append("## API Query Patterns\n")
    md.append("Reference patterns for querying chemical/biological databases programmatically.\n")

    md.append("### Common Query Pattern\n")
    md.append("```python")
    md.append("def query_database(prompt: str, database: str, max_results: int = 5):")
    md.append("    \"\"\"Generic database query using LLM for API generation\"\"\"")
    md.append("    # 1. Query LLM to generate API endpoint from natural language")
    md.append("    endpoint = _query_llm_for_api(prompt, database)")
    md.append("    ")
    md.append("    # 2. Execute REST API call")
    md.append("    response = _query_rest_api(endpoint)")
    md.append("    ")
    md.append("    # 3. Parse and return results")
    md.append("    return parse_response(response, max_results)")
    md.append("```\n")

    md.append("### Database-Specific APIs\n")
    md.append("#### PubChem PUG REST API")
    md.append("- **Base URL:** `https://pubchem.ncbi.nlm.nih.gov/rest/pug/`")
    md.append("- **Documentation:** https://pubchem.ncbi.nlm.nih.gov/docs/pug-rest")
    md.append("- **Example:** `compound/name/aspirin/property/MolecularFormula,MolecularWeight/JSON`\n")

    md.append("#### ChEMBL API")
    md.append("- **Base URL:** `https://www.ebi.ac.uk/chembl/api/data/`")
    md.append("- **Documentation:** https://www.ebi.ac.uk/chembl/api/data/docs")
    md.append("- **Example:** `molecule/CHEMBL25?format=json`\n")

    md.append("#### KEGG REST API")
    md.append("- **Base URL:** `https://rest.kegg.jp/`")
    md.append("- **Documentation:** https://www.kegg.jp/kegg/rest/keggapi.html")
    md.append("- **Example:** `get/hsa:10458` (get entry), `find/compound/glucose` (search)\n")

    md.append("#### HMDB API")
    md.append("- **Base URL:** `https://hmdb.ca/`")
    md.append("- **Access:** Requires academic credentials")
    md.append("- **Documentation:** https://hmdb.ca/simple/api\n")

    # Usage Guidelines
    md.append("## Usage Guidelines\n")
    md.append("### For LLM-Based Workflow Generation\n")
    md.append("1. **Dataset Selection:**")
    md.append("   - Use tool parameters for large local datasets (>100MB)")
    md.append("   - Use workflow inputs for small datasets (<100MB)")
    md.append("   - Use Data Source tools for API queries\n")

    md.append("2. **Format Conversion:**")
    md.append("   - Parquet/PKL files: Convert on-demand using conversion functions")
    md.append("   - SQLite databases: Use with compatible metabolomics tools (ipaPy2, CFM-ID, BEAMSpy)")
    md.append("   - CSV/TSV files: Galaxy-ready, use directly\n")

    md.append("3. **Tool Selection:**")
    md.append("   - Match database type to tool (e.g., PubChem tools for PubChem data)")
    md.append("   - Check tool parameters for database/reference file support")
    md.append("   - Verify input/output format compatibility\n")

    md.append("4. **API Integration:**")
    md.append("   - Use existing Galaxy Data Source tools when available")
    md.append("   - Follow biomni query patterns for LLM-assisted API generation")
    md.append("   - Cache API results when possible to reduce redundant queries\n")

    md.append("### Compatible Galaxy Tools\n")
    md.append("- **SQLite Databases:** ipaPy2, CFM-ID, BEAMSpy, MS2Compound")
    md.append("- **Chemical Data:** ChemicalToolBox, OpenBabel, RDKit tools")
    md.append("- **Metabolomics:** MetaboAnalyst, XCMS, mzML processing tools")
    md.append("- **Proteomics:** SearchGUI, PeptideShaker, MaxQuant")
    md.append("- **Pathway Analysis:** Reactome, KEGG mapper, PathwayEnrichment\n")

    md.append("---")
    md.append(f"*Document generated on {timestamp} for biomate backend integration*")

    # Write markdown file
    output_file = f'/Users/jingqiwang/biomate/backend/GALAXY_DATA_TOOLS_AND_DATASETS_REFERENCE_{timestamp}.md'
    with open(output_file, 'w') as f:
        f.write('\n'.join(md))

    print(f"✓ Reference document created: {output_file}")
    print(f"  Total lines: {len(md)}")

    return output_file

if __name__ == '__main__':
    main()
