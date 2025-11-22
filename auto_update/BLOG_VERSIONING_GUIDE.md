# Blog Versioning System - Audit Trail Guide

**Created**: 2025-11-11
**Purpose**: Track all blog post iterations for quality auditing

---

## Folder Structure

```
blog_posts/
├── auto_toolname_blog.md                    ← Current published version
├── auto_toolname_blog_reviewed.md           ← AI-reviewed final version
├── auto_toolname_blog.json                  ← JSON metadata
├── review/
│   ├── evaluation_results_TIMESTAMP.json    ← Tool worthiness evaluation
│   └── workflow_summary_TIMESTAMP.json      ← Processing summary
└── versions/
    └── auto_toolname/
        ├── auto_toolname_v0_initial_TIMESTAMP.md              ← Initial generated blog
        ├── auto_toolname_v1_iteration_1_TIMESTAMP.md         ← After 1st improvement
        ├── auto_toolname_v1_iteration_1_review_TIMESTAMP.json ← Review feedback iter 1
        ├── auto_toolname_v2_iteration_2_TIMESTAMP.md         ← After 2nd improvement
        ├── auto_toolname_v2_iteration_2_review_TIMESTAMP.json ← Review feedback iter 2
        └── auto_toolname_v2_final_approved_TIMESTAMP.md      ← Agent-approved final
```

---

## File Naming Convention

### Version Numbers
- **v0** = Initial generated blog (before any review)
- **v1** = After 1st review iteration
- **v2** = After 2nd review iteration
- **vN** = After Nth review iteration

### Phase Labels
- **initial** = First generation from template
- **iteration_N** = After Nth improvement cycle
- **final_approved** = AI agent determined ready for manual review

### Timestamps
- Format: `YYYYMMDD_HHMMSS`
- Example: `20251111_145100` = Nov 11, 2025, 14:51:00

---

## Complete Example

### foldseek Blog Evolution

```
versions/auto_foldseek/
├── auto_foldseek_v0_initial_20251111_145100.md
│   Quality: 0.45
│   Issues: 5 (2 critical)
│   Status: Needs improvement
│
├── auto_foldseek_v1_iteration_1_20251111_145125.md
│   Quality: 0.75
│   Issues: 3 (0 critical)
│   Status: Improved but not ready
│
├── auto_foldseek_v1_iteration_1_review_20251111_145125.json
│   Contains: Detailed review feedback for iteration 1
│
├── auto_foldseek_v2_iteration_2_20251111_145135.md
│   Quality: 0.92
│   Issues: 2 (0 critical, minor only)
│   Status: Ready for manual review
│
├── auto_foldseek_v2_iteration_2_review_20251111_145135.json
│   Contains: Final review confirming quality
│
└── auto_foldseek_v2_final_approved_20251111_145135.md
    Quality: 0.92
    Decision: READY FOR MANUAL REVIEW
    Same as v2_iteration_2 but marked as approved
```

---

## Auditing Workflow

### 1. Check What Blogs Were Generated

```bash
ls -lh blog_posts/*.md
```

### 2. Review Improvement History for a Tool

```bash
# List all versions chronologically
ls -lhtr blog_posts/versions/auto_foldseek/

# Count iterations
ls blog_posts/versions/auto_foldseek/*iteration*.md | wc -l
```

### 3. Compare Initial vs Final

```bash
# View initial blog (quality 0.45)
cat blog_posts/versions/auto_foldseek/auto_foldseek_v0_initial_*.md

# View final approved blog (quality 0.92)
cat blog_posts/versions/auto_foldseek/auto_foldseek_v*_final_approved_*.md

# Side-by-side comparison
diff -u blog_posts/versions/auto_foldseek/auto_foldseek_v0_initial_*.md \
        blog_posts/versions/auto_foldseek/auto_foldseek_v*_final_approved_*.md
```

### 4. Review AI Feedback

```bash
# Check review feedback for each iteration
cat blog_posts/versions/auto_foldseek/*review*.json | python3 -m json.tool
```

### 5. Audit Quality Progression

```bash
# Extract quality scores from all review files
grep -h "quality_score" blog_posts/versions/auto_foldseek/*review*.json
```

---

## Review JSON Structure

Each `*_review_TIMESTAMP.json` file contains:

```json
{
  "ready_for_review": false,
  "quality_score": 0.75,
  "issues": [
    {
      "section": "Introduction",
      "severity": "major",
      "issue": "Description of problem",
      "suggestion": "How to fix it"
    }
  ],
  "strengths": [
    "What the blog does well"
  ],
  "decision_reason": "Why ready or not ready",
  "iteration_needed": true
}
```

**Severity Levels**:
- **critical**: Must be fixed (blocks approval)
- **major**: Should be fixed (affects quality score significantly)
- **minor**: Nice to fix (small improvements)

---

## Quality Scores

### Score Ranges
- **0.00-0.49**: Poor - Lacks technical depth, vague descriptions
- **0.50-0.69**: Fair - Some technical content but needs improvement
- **0.70-0.84**: Good - Solid technical content, minor issues remain
- **0.85-1.00**: Excellent - Ready for manual review

### Approval Criteria

Blog is marked `ready_for_review: true` when:
1. Quality score >= 0.85 **AND**
2. No critical issues remaining

---

## Manual Review Checklist

Before publishing a blog to production:

### 1. Check Version History
```bash
ls -lh blog_posts/versions/auto_toolname/
```

**Questions to ask**:
- How many iterations did it take? (1-2 is normal, 5 indicates problems)
- What was the initial quality score?
- What were the main issues fixed?

### 2. Review Final Quality
```bash
# Check final review JSON
cat blog_posts/versions/auto_toolname/*final*review*.json | \
  python3 -c "import json, sys; \
    data = json.load(sys.stdin); \
    print(f'Quality: {data[\"quality_score\"]}'); \
    print(f'Issues: {len(data[\"issues\"])}'); \
    print(f'Critical: {sum(1 for i in data[\"issues\"] if i[\"severity\"]==\" critical\")}')"
```

**Accept if**:
- Quality score >= 0.85
- No critical issues
- Issues are minor and acceptable

### 3. Read Final Blog
```bash
cat blog_posts/versions/auto_toolname/*final_approved*.md
```

**Check for**:
- Clear, specific introduction
- Technical depth appropriate for researchers
- Accurate workflow examples
- Proper input/output specifications

### 4. Compare to Initial
```bash
diff blog_posts/versions/auto_toolname/*v0_initial*.md \
     blog_posts/versions/auto_toolname/*final*.md | head -50
```

**Look for improvements in**:
- Specificity (concrete examples vs vague descriptions)
- Technical accuracy (correct terminology, realistic workflows)
- Completeness (all sections substantive)

### 5. Approve or Request Changes

**If approved**:
```bash
# Copy final version to production
cp blog_posts/auto_toolname_blog_reviewed.md \
   /path/to/website/blog/toolname.md
```

**If changes needed**:
1. Note specific issues in `blog_posts/review/manual_feedback_toolname.txt`
2. Regenerate with manual corrections
3. Re-run through review agent

---

## Maintenance

### Archive Old Versions

After publishing, archive versions for audit trail:

```bash
# Create archive directory
mkdir -p blog_posts/archive/$(date +%Y%m)

# Move versions to archive
mv blog_posts/versions/auto_toolname \
   blog_posts/archive/$(date +%Y%m)/
```

### Clean Up Test Runs

```bash
# Remove test blog directories
rm -rf blog_posts_test blog_posts_with_review_test blog_posts_versioned_test
```

### Monitor Storage

```bash
# Check versions directory size
du -sh blog_posts/versions/

# Count total versions
find blog_posts/versions -name "*.md" | wc -l
```

---

## Troubleshooting

### Too Many Iterations (5+)

**Problem**: Blog not improving or stuck in loop

**Solutions**:
1. Check tool metadata in database (incomplete data causes poor blogs)
2. Review initial generated blog template
3. Manually write blog and use as template

### Low Initial Quality (<0.30)

**Problem**: Initial template generating poor content

**Solutions**:
1. Improve blog_post_generator.py templates
2. Add more tool metadata to database
3. Check if tool is actually blog-worthy

### High Quality but Still Iterating

**Problem**: Agent being too strict

**Solutions**:
1. Check review criteria in blog_review_agent.py
2. Lower quality threshold if consistently good blogs rejected
3. Review "iteration_needed" logic

---

## Statistics

### Per-Tool Stats

```bash
# Count iterations for each tool
for tool in blog_posts/versions/*/; do
  count=$(ls $tool/*iteration*.md 2>/dev/null | wc -l)
  echo "$(basename $tool): $count iterations"
done
```

### Quality Distribution

```bash
# Extract final quality scores
find blog_posts/versions -name "*final*review*.json" -exec \
  python3 -c "import json, sys; \
    data = json.load(open('{}'))); \
    print(data.get('quality_score', 0))" \; | \
  sort -n
```

### Approval Rate

```bash
# Count ready vs not ready
grep -h "ready_for_review" blog_posts/versions/*/*final*review*.json | \
  sort | uniq -c
```

---

## Best Practices

1. **Never delete versions/** - It's your audit trail
2. **Review final_approved blogs** before publishing
3. **Archive old versions** monthly to save space
4. **Monitor quality trends** to improve templates
5. **Check 5+ iteration tools** - May indicate systemic issues

---

## Integration with Workflow

The versioning system is integrated into the main workflow:

```bash
# Full workflow with versioning
python3 scripts/generate_blogs_with_review.py \
  --all-new \
  --output ./blog_posts

# Versions automatically saved to:
#   blog_posts/versions/tool_id/
```

Versions directory structure is created automatically. No manual intervention needed.

---

**Last Updated**: 2025-11-11
**System**: Fully automated with manual review checkpoints
