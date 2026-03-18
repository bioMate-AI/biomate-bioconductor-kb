# Galaxy-Nextflow Converter Completion Plan

**Date**: 2025-12-03 21:33
**Status**: Planning
**Goal**: Complete bidirectional workflow conversion with full feature support

---

## Executive Summary

Current converters are ~60% complete. This plan addresses the remaining gaps:

| Gap | Current Status | Solution |
|-----|----------------|----------|
| Subworkflow structure | Partial (not recursive) | Recursive parsing + Galaxy embedding |
| Channel operators | Skipped entirely | Rule-based conversion + annotations |
| Conditionals (NF→Galaxy) | Not handled | Expression mapping |
| Workflow hierarchy | Not handled | Tree builder with traversal |

---

## Current State Analysis

### What Works

| Feature | Galaxy → Nextflow | Nextflow → Galaxy |
|---------|-------------------|-------------------|
| Basic process/step mapping | ✅ | ✅ |
| Input/output connections | ✅ | ✅ |
| Tool identification | ✅ | ✅ |
| Conditional detection | ✅ (from annotations) | ❌ |
| `include` parsing | N/A | ✅ (parsed, not converted) |
| Subworkflow embedding | N/A | ❌ |

### What's Missing

1. **Subworkflow Structure**
   - Galaxy `type: subworkflow` with embedded workflow JSON
   - Nextflow `include { PROCESS } from './module'`
   - Recursive parsing of nested workflows

2. **Channel Operators**
   - `.map { }` - data transformation
   - `.filter { }` - conditional filtering
   - `.branch { }` - splitting data flow
   - `.join()` - merging channels
   - `.collect()` - aggregation

3. **Conditionals (Nextflow → Galaxy)**
   - `when:` directive → Galaxy `when` expression
   - `if/else` in script → multiple steps or annotation

4. **Workflow Hierarchy**
   - Multi-file Nextflow projects
   - Proper include resolution
   - Hierarchy preservation

---

## Implementation Plan

### Phase 1: Subworkflow Structure (HIGH Priority)

**Effort**: 2-3 days

#### 1.1 Nextflow Include Resolution

```python
class IncludeResolver:
    """Resolve Nextflow include statements to actual workflow content."""

    def resolve(self, include: NextflowInclude, base_path: Path) -> ResolvedInclude:
        """
        Load and parse included file.

        Args:
            include: Parsed include statement
            base_path: Directory of the including file

        Returns:
            ResolvedInclude with parsed workflow/process content
        """
        source_path = self._resolve_path(include.source, base_path)
        content = source_path.read_text()

        # Parse the included file
        parser = NextflowParser()
        parsed = parser.parse(content)

        # Filter to only included items
        return ResolvedInclude(
            items={name: parsed.get_item(name) for name in include.items},
            source_path=source_path
        )
```

#### 1.2 Galaxy Subworkflow Generation

```python
def generate_galaxy_subworkflow_step(
    resolved: ResolvedInclude,
    step_id: int,
    input_connections: Dict
) -> Dict:
    """Generate Galaxy subworkflow step with embedded workflow."""

    # Recursively convert included workflow to Galaxy format
    converter = NextflowToGalaxyConverter()
    embedded_workflow = converter.convert(resolved.workflow)

    return {
        "id": step_id,
        "type": "subworkflow",
        "name": resolved.name,
        "input_connections": {
            f"0:{input_name}": {
                "id": source_id,
                "input_subworkflow_step_id": 0,
                "output_name": output_name
            }
            for input_name, (source_id, output_name) in input_connections.items()
        },
        "subworkflow": embedded_workflow
    }
```

#### 1.3 Tests
- Convert nf-core workflow with subworkflows → Galaxy
- Convert Galaxy workflow with subworkflows → Nextflow
- Verify structure preservation

---

### Phase 2: Conditionals NF→Galaxy (HIGH Priority)

**Effort**: 1-2 days

#### 2.1 When Directive Conversion

```python
def convert_when_directive(nf_when: str) -> str:
    """
    Convert Nextflow when clause to Galaxy when expression.

    Examples:
        params.aligner == 'bwa'  →  ${aligner} == 'bwa'
        params.skip_qc           →  ${skip_qc}
        !params.skip_qc          →  ${skip_qc} == false
    """
    expr = nf_when

    # params.X → ${X}
    expr = re.sub(r'params\.(\w+)', r'${\1}', expr)

    # Handle negation
    expr = re.sub(r'!\$\{(\w+)\}', r'${\1} == false', expr)

    return expr
```

#### 2.2 Script Conditional Handling

```python
def handle_script_conditionals(script: str) -> ConditionalResult:
    """
    Handle if/else blocks in Nextflow scripts.

    Strategy:
    - Simple if/else → Split into multiple Galaxy steps with when
    - Complex logic → Single step with annotation
    """
    conditions = extract_conditions(script)

    if is_simple_branch(conditions):
        # Generate multiple Galaxy steps
        return ConditionalResult(
            strategy='split',
            steps=[
                {'tool_id': tool, 'when': convert_when_directive(cond)}
                for cond, tool in conditions.items()
            ]
        )
    else:
        # Too complex - annotate and keep single step
        return ConditionalResult(
            strategy='annotate',
            annotation=f"Conditional logic: {summarize_conditions(conditions)}"
        )
```

#### 2.3 Tests
- Convert Nextflow process with `when:` → Galaxy step with `when`
- Round-trip test: Galaxy → NF → Galaxy preserves conditionals

---

### Phase 3: Channel Operators (MEDIUM Priority)

**Effort**: 2-3 days

#### 3.1 Operator Classification

| Operator | Galaxy Equivalent | Strategy |
|----------|-------------------|----------|
| `.filter { }` | Filter tool / when expression | Convert |
| `.branch { }` | Multiple connections + when | Convert |
| `.collect()` | Collection creation | Convert |
| `.map { }` | No equivalent | Annotate |
| `.flatMap { }` | No equivalent | Annotate |
| `.join()` | Implicit via connections | Best-effort |

#### 3.2 Branch Operator Conversion

```python
def convert_branch_operator(branch_expr: str) -> List[Dict]:
    """
    Convert Nextflow .branch { } to Galaxy branched outputs.

    Input:
        .branch {
            bwa: it.aligner == 'bwa'
            bowtie: it.aligner == 'bowtie2'
        }

    Output:
        Multiple Galaxy output connections with when expressions
    """
    cases = parse_branch_cases(branch_expr)

    return [
        {
            'name': case_name,
            'when': convert_condition_to_galaxy(condition),
            'connections': []  # Filled in during workflow assembly
        }
        for case_name, condition in cases.items()
    ]
```

#### 3.3 Filter Operator Conversion

```python
def convert_filter_operator(filter_expr: str) -> Dict:
    """
    Convert Nextflow .filter { } to Galaxy filter step.

    Simple filters can use Galaxy's collection filter.
    Complex filters become annotations.
    """
    condition = parse_filter_condition(filter_expr)

    if is_simple_condition(condition):
        return {
            'type': 'tool',
            'tool_id': '__FILTER_COLLECTION__',
            'tool_state': {'how': 'filter', 'filter': condition}
        }
    else:
        return {
            'annotation': f"Filter: {filter_expr}",
            'warning': 'Complex filter - manual review needed'
        }
```

#### 3.4 Tests
- Convert workflow with `.branch` → verify multiple Galaxy paths
- Convert workflow with `.filter` → verify filter step created
- Document what cannot be converted

---

### Phase 4: Workflow Hierarchy (MEDIUM Priority)

**Effort**: 2-3 days

#### 4.1 Hierarchy Tree Builder

```python
@dataclass
class WorkflowNode:
    """Node in workflow hierarchy."""
    name: str
    node_type: str  # 'main', 'subworkflow', 'process'
    source_file: Path
    children: List['WorkflowNode'] = field(default_factory=list)
    includes: List[NextflowInclude] = field(default_factory=list)
    content: Any = None  # Parsed workflow/process

class WorkflowHierarchyBuilder:
    """Build complete workflow tree from entry point."""

    def __init__(self, parser: NextflowParser):
        self.parser = parser
        self.resolved_files: Dict[Path, WorkflowNode] = {}

    def build(self, entry_file: Path) -> WorkflowNode:
        """Build hierarchy starting from main workflow file."""
        return self._build_node(entry_file, node_type='main')

    def _build_node(self, file_path: Path, node_type: str) -> WorkflowNode:
        """Recursively build node and children."""
        # Avoid circular includes
        if file_path in self.resolved_files:
            return self.resolved_files[file_path]

        content = file_path.read_text()
        parsed = self.parser.parse(content)

        node = WorkflowNode(
            name=file_path.stem,
            node_type=node_type,
            source_file=file_path,
            includes=parsed.includes,
            content=parsed
        )

        self.resolved_files[file_path] = node

        # Resolve children
        for include in parsed.includes:
            child_path = self._resolve_include_path(include, file_path.parent)
            child_node = self._build_node(child_path, node_type='subworkflow')
            node.children.append(child_node)

        return node

    def flatten(self, root: WorkflowNode) -> Dict:
        """Flatten hierarchy for Galaxy (embedded subworkflows)."""
        pass

    def to_file_structure(self, root: WorkflowNode) -> Dict[Path, str]:
        """Generate Nextflow file structure (separate files with includes)."""
        pass
```

#### 4.2 Tests
- Parse nf-core/rnaseq (complex hierarchy) → verify tree structure
- Convert to Galaxy → verify embedded subworkflows
- Convert back to Nextflow → verify include structure preserved

---

### Phase 5: Complex Channel Operators (LOW Priority)

**Effort**: 1-2 days

#### 5.1 Map/FlatMap Handling

These cannot be directly converted - strategy is documentation:

```python
def handle_map_operator(map_expr: str) -> Dict:
    """
    Document map operation - cannot convert to Galaxy.

    Returns annotation explaining the transformation.
    """
    transformation = analyze_map_transformation(map_expr)

    return {
        'annotation': f"""
Data Transformation (Nextflow .map):
{map_expr}

Effect: {transformation.description}
Input structure: {transformation.input_type}
Output structure: {transformation.output_type}

Note: Galaxy workflows cannot represent arbitrary data transformations.
Manual adjustment may be needed.
""",
        'convertible': False,
        'impact': transformation.impact  # 'critical', 'moderate', 'low'
    }
```

#### 5.2 Join Operator (Best Effort)

```python
def convert_join_operator(join_expr: str, channels: List[str]) -> Dict:
    """
    Attempt to convert .join() to Galaxy multi-input step.

    Galaxy handles joins implicitly through multiple input connections
    to the same step. This works for simple cases.
    """
    if len(channels) == 2 and is_simple_join(join_expr):
        return {
            'strategy': 'multi_input',
            'input_connections': {
                f'input_{i}': ch for i, ch in enumerate(channels)
            }
        }
    else:
        return {
            'strategy': 'annotate',
            'annotation': f'Complex join: {join_expr}',
            'warning': 'Manual review needed'
        }
```

---

## Bidirectional Testing Strategy

### Why Bidirectional Testing is Critical

**YES, bidirectional (round-trip) testing is extremely valuable:**

1. **Validates Completeness**
   - If A → B → A loses information, the converter is incomplete
   - Round-trip tests reveal hidden gaps

2. **Ensures Consistency**
   - Both converters should agree on semantics
   - Inconsistencies indicate bugs

3. **Catches Edge Cases**
   - Real workflows expose patterns not anticipated
   - nf-core and IWC workflows provide diverse test cases

### Round-Trip Test Framework

```python
class RoundTripTester:
    """Test bidirectional conversion fidelity."""

    def __init__(self):
        self.nf_to_galaxy = NextflowToGalaxyConverter()
        self.galaxy_to_nf = GalaxyToNextflowConverter()

    def test_nextflow_roundtrip(self, nf_file: Path) -> RoundTripResult:
        """Nextflow → Galaxy → Nextflow"""
        original = parse_nextflow(nf_file)

        # Forward
        galaxy = self.nf_to_galaxy.convert(original)

        # Backward
        reconstructed = self.galaxy_to_nf.convert(galaxy)

        # Compare
        return self._compare_workflows(original, reconstructed, 'nextflow')

    def test_galaxy_roundtrip(self, ga_file: Path) -> RoundTripResult:
        """Galaxy → Nextflow → Galaxy"""
        original = parse_galaxy(ga_file)

        # Forward
        nextflow = self.galaxy_to_nf.convert(original)

        # Backward
        reconstructed = self.nf_to_galaxy.convert(nextflow)

        # Compare
        return self._compare_workflows(original, reconstructed, 'galaxy')

    def _compare_workflows(
        self,
        original: Any,
        reconstructed: Any,
        format: str
    ) -> RoundTripResult:
        """Compare workflows and identify differences."""

        differences = []

        # Compare structure
        if format == 'nextflow':
            differences.extend(self._compare_nf_structure(original, reconstructed))
        else:
            differences.extend(self._compare_galaxy_structure(original, reconstructed))

        # Categorize differences
        critical = [d for d in differences if d.severity == 'critical']
        warnings = [d for d in differences if d.severity == 'warning']
        info = [d for d in differences if d.severity == 'info']

        return RoundTripResult(
            success=len(critical) == 0,
            critical_differences=critical,
            warnings=warnings,
            info=info,
            fidelity_score=self._calculate_fidelity(differences)
        )
```

### Test Categories

| Category | Test | Pass Criteria |
|----------|------|---------------|
| **Structure** | Step count preserved | ±10% (subworkflow expansion allowed) |
| **Connections** | Data flow preserved | 100% match |
| **Conditionals** | When expressions preserved | Semantic equivalence |
| **Subworkflows** | Hierarchy preserved | Structure match |
| **Tool IDs** | Tools identifiable | Same tool resolved |
| **Parameters** | Config preserved | Values match |

### Expected Losses (Documented)

Some information CANNOT survive round-trip - document explicitly:

| Nextflow Feature | Loss in Galaxy | Acceptable? |
|------------------|----------------|-------------|
| `.map { }` transformations | Yes - annotated only | Yes |
| Groovy expressions | Yes - simplified | Yes |
| Resource directives | Yes - in tool XML | Yes |
| Profile configs | Yes - no equivalent | Yes |
| Channel operator chains | Partial | Document |

| Galaxy Feature | Loss in Nextflow | Acceptable? |
|----------------|------------------|-------------|
| GUI positions | Yes - not meaningful | Yes |
| Report templates | Yes - no equivalent | Yes |
| Post-job actions | Partial | Document |

---

## Test Workflow Selection

### Nextflow Test Cases (nf-core)

| Workflow | Complexity | Key Features |
|----------|------------|--------------|
| `fetchngs` | Simple | Basic process chain |
| `rnaseq` | Complex | Subworkflows, conditionals, branches |
| `sarek` | Very Complex | Multiple paths, extensive conditionals |
| `chipseq` | Medium | Peak calling pipeline |

### Galaxy Test Cases (IWC)

| Workflow | Complexity | Key Features |
|----------|------------|--------------|
| `fastq_to_bam` | Simple | Linear pipeline |
| `fastq_align_dna` | Medium | Multiple aligners (conditionals) |
| `chipseq_pe` | Medium | Paired-end ChIP-seq |
| `rnaseq_pe` | Complex | Full RNA-seq with QC |

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Round-trip fidelity | >90% | Structure + connections preserved |
| Subworkflow support | 100% | All subworkflows converted |
| Conditional preservation | >80% | When expressions survive |
| Channel operator coverage | >60% | Converted or documented |
| Test coverage | >85% | Unit + integration tests |

---

## Timeline Summary

| Phase | Work | Duration | Dependencies |
|-------|------|----------|--------------|
| 1 | Subworkflow structure | 2-3 days | None |
| 2 | Conditionals NF→Galaxy | 1-2 days | None |
| 3 | Channel operators | 2-3 days | Phase 1 |
| 4 | Workflow hierarchy | 2-3 days | Phase 1 |
| 5 | Complex operators | 1-2 days | Phase 3 |
| **Testing** | Round-trip framework | 2-3 days | All phases |

**Total**: ~12-16 days for complete implementation

---

## Recommendations

1. **Start with Phase 1 + 2** - Highest impact, enables meaningful round-trip tests
2. **Build round-trip tests early** - Use them to validate each phase
3. **Document losses explicitly** - Better to acknowledge than hide
4. **Use real workflows** - nf-core and IWC provide best test coverage
5. **Docker approach complements** - Merge with LLM converters for tool execution

---

## Next Steps

1. [ ] Review and approve this plan
2. [ ] Set up round-trip test framework
3. [ ] Begin Phase 1: Subworkflow implementation
4. [ ] Select specific test workflows from nf-core/IWC
