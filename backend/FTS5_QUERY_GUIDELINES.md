# FTS5 Query Guidelines for Galaxy Tool Search

## Database Structure

The tool search index uses SQLite FTS5 (Full-Text Search) with these indexed fields:
- `name` - Tool name
- `description` - Tool description
- `keywords` - Extracted keywords (lcms, peak, metabolite, etc.)

## FTS5 Query Syntax Rules

### ✅ VALID Syntax:
1. **Simple keywords**: `metabolomics`, `peak`, `detection`
2. **OR operator**: `peak OR detection`
3. **AND operator**: `peak AND detection` or `peak detection`
4. **Phrase search**: `"peak detection"` (exact phrase)
5. **Prefix search**: `metab*` (matches metabol, metabolite, metabolomics)
6. **Column search**: `name:xcms` (search only in name field)

### ❌ INVALID Syntax (causes errors):
1. **Hyphens in keywords**: `LC-MS` → Use `lcms` or `"lc ms"` instead
2. **Special characters**: `MS/MS` → Use `msms` or `"ms ms"` instead
3. **Complex phrases without quotes**: `identify metabolites from` → Use keywords: `identify metabolites`
4. **Parentheses in query**: `(version 1.0)` → Remove or use `version`

## Query Transformation Strategy

### User Intent → FTS5 Query Conversion

**Step 1: Extract domain keywords**
- User: "Identify metabolites from human serum LC-MS data"
- Keywords: metabolite, serum, lcms, identification

**Step 2: Remove special characters**
- `LC-MS` → `lcms` or `"lc ms"`
- `MS/MS` → `msms`
- `m/z` → `mz`

**Step 3: Build FTS5 query**
- Simple: `metabolite lcms` (AND is implicit)
- OR: `metabolite OR compound`
- Phrase: `"peak detection"`

**Step 4: Add category filter (optional)**
- Category: `Metabolomics`

## Recommended Query Patterns by Task

### 1. Metabolomics Workflows
```
Query: metabolite OR metabolomics OR xcms OR msnbase
Category: Metabolomics
```

### 2. Peak Detection
```
Query: peak AND (detection OR finding OR picker)
Category: Metabolomics
```

### 3. Compound Identification
```
Query: compound OR metabolite AND (identification OR annotation OR matching)
Category: Metabolomics
```

### 4. LC-MS Data Processing
```
Query: lcms OR "lc ms" OR chromatogram OR mzml
Category: Metabolomics
```

### 5. Proteomics
```
Query: protein OR peptide OR mascot OR proteomics
Category: Proteomics
```

## Example Transformations

| User Intent | FTS5 Query |
|-------------|------------|
| "Find metabolites in LC-MS data" | `metabolite lcms` |
| "Detect peaks in chromatogram" | `peak detection chromatogram` |
| "Identify compounds using MS/MS" | `compound identification msms` |
| "XCMS peak picking" | `xcms peak` |
| "Align retention times" | `retention time alignment` OR `retention alignment` |
| "Statistical analysis of metabolomics data" | `metabolomics statistical analysis` |

## Python Implementation

```python
def transform_user_intent_to_fts_query(user_intent: str) -> str:
    """Transform user intent to valid FTS5 query."""

    # Extract keywords using LLM
    keywords = extract_keywords_llm(user_intent)

    # Clean special characters
    cleaned = []
    for kw in keywords:
        # Replace hyphens and slashes with space or remove
        kw = kw.replace('-', ' ').replace('/', ' ')
        # Remove parentheses
        kw = kw.replace('(', '').replace(')', '')
        cleaned.append(kw.strip())

    # Join with OR for broader matching
    query = ' OR '.join(cleaned)

    return query
```

## Testing Queries

```bash
# Test in SQLite
sqlite3 tool_search_index.db "
  SELECT name, category
  FROM tools
  WHERE id IN (
    SELECT rowid FROM tools_fts
    WHERE tools_fts MATCH 'metabolite OR xcms'
  )
  LIMIT 10;
"
```

## Common Errors and Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `no such column: MS` | Hyphen treated as operator | Use `ms` or quote `"m s"` |
| `fts5: syntax error` | Special chars in query | Clean query string |
| No results | Too specific query | Use OR to broaden |
| Too many results | Too generic query | Add AND conditions or category filter |

## Best Practices

1. **Start broad, then narrow**: Use OR for initial search, then filter
2. **Use category filter**: Limit to relevant category (Metabolomics, Proteomics)
3. **Test queries**: Always validate FTS5 syntax before executing
4. **Fallback to LIKE**: If FTS5 fails, fallback to SQL LIKE operator
5. **Cache common queries**: Reuse successful query patterns
