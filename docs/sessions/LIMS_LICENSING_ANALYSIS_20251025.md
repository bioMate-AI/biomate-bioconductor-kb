# LIMS Licensing Analysis for Commercial Use

**Document Created:** 2025-10-25
**Purpose:** Evaluate commercial-friendliness of LIMS systems for bioMate integration

---

## Executive Summary

**Short Answer:**
- ✅ **OpenELIS & Mirth Connect (MPL 2.0)**: **Commercial-friendly**
- ⚠️ **Bika LIMS/SENAITE (GPL-2.0)**: **Restrictive for commercial use**

**Recommendation:** For commercial bioMate platform, **OpenELIS is safer** from a licensing perspective, OR use SENAITE via strict API separation.

---

## License Comparison

| System | License | Commercial Friendly? | Key Restrictions |
|--------|---------|---------------------|------------------|
| **OpenELIS Global 2** | **MPL 2.0** | ✅ **YES** | File-level copyleft only |
| **Mirth Connect** | **MPL 2.0** | ✅ **YES** | File-level copyleft only |
| **Bika LIMS** | **GPL-2.0** | ⚠️ **RESTRICTIVE** | Strong copyleft |
| **SENAITE Core** | **GPL-2.0** | ⚠️ **RESTRICTIVE** | Strong copyleft |
| **senaite.instruments** | **GPL-2.0** | ⚠️ **RESTRICTIVE** | Strong copyleft |

---

## Detailed License Analysis

### 1. MPL 2.0 (Mozilla Public License 2.0)

**Used by:** OpenELIS, Mirth Connect

#### What is MPL 2.0?

MPL 2.0 is a **weak copyleft** license that is **commercial-friendly**.

#### Key Features:

✅ **File-level copyleft:**
- Only modified MPL files must remain MPL
- You can combine with proprietary code
- Larger work can be under different license

✅ **Can link with proprietary code:**
- No requirement to open-source your application
- Can use as a library/service without contamination

✅ **Patent grant:**
- Contributors grant patent licenses

✅ **Compatible with GPL:**
- Can combine with GPL code (becomes GPL)
- Can combine with proprietary code (stays proprietary + MPL files)

#### Commercial Use Scenarios:

**Scenario 1: Use OpenELIS as separate service**
```
OpenELIS (MPL 2.0)  <--API-->  bioMate (Proprietary)
```
- ✅ **Fully allowed**
- bioMate remains proprietary
- No requirement to share bioMate code

**Scenario 2: Modify OpenELIS code**
```
Modified OpenELIS files (must stay MPL 2.0)
    +
bioMate proprietary code
    =
Combined product (bioMate can stay proprietary)
```
- ✅ **Allowed**
- Only modified OpenELIS files must be MPL 2.0
- Must provide source for modified MPL files
- Rest of bioMate can be proprietary

**Scenario 3: Extract OpenELIS components**
```
OpenELIS analyzer parsers (keep as MPL 2.0 files)
    +
bioMate wrapper code (proprietary)
    =
bioMate Analyzer Service (mixed licensing)
```
- ✅ **Allowed**
- MPL files stay MPL
- Your code stays proprietary
- Must disclose which files are MPL and provide source

#### Obligations under MPL 2.0:

1. **Include license notice** in MPL files
2. **Provide source code** for MPL files (if modified)
3. **Document modifications** to MPL files
4. **No restriction** on proprietary additions

---

### 2. GPL-2.0 (GNU General Public License v2)

**Used by:** Bika LIMS, SENAITE, senaite.instruments

#### What is GPL-2.0?

GPL-2.0 is a **strong copyleft** license that is **restrictive for commercial use**.

#### Key Features:

❌ **Strong copyleft:**
- Derivative works must be GPL
- Linking/combining may create derivative work
- Viral nature - can "infect" proprietary code

❌ **Distribution triggers:**
- If you distribute GPL software (modified or not), you must provide source
- If you create derivative work, it must be GPL

⚠️ **Network use loophole:**
- GPL-2.0 doesn't cover network use (unlike AGPL)
- SaaS/API use may not trigger obligations
- BUT: Legal gray area

✅ **Patent grant:**
- Contributors cannot assert patents

#### Commercial Use Scenarios:

**Scenario 1: Use SENAITE as separate service (API only)**
```
SENAITE (GPL-2.0)  <--API/Network-->  bioMate (Proprietary)
```
- ✅ **Likely allowed** (network service loophole)
- No code distribution = no GPL obligations
- BUT: Legal uncertainty
- Safer: Use AGPL interpretation (requires source disclosure)

**Scenario 2: Link SENAITE libraries into bioMate**
```
SENAITE libraries (GPL-2.0)
    +
bioMate code
    =
Combined work (MUST be GPL-2.0)
```
- ❌ **NOT ALLOWED for proprietary product**
- Entire bioMate would need to be GPL-2.0
- Must provide all source code to customers
- Cannot have proprietary bioMate

**Scenario 3: Extract SENAITE code into bioMate**
```
SENAITE analyzer parsers (GPL-2.0)
    +
bioMate code (proprietary)
    =
bioMate (MUST be GPL-2.0 if derivative work)
```
- ❌ **HIGH RISK**
- If parsers are substantial, creates derivative work
- Entire bioMate could be forced to GPL
- Legal risk

**Scenario 4: Fork and modify SENAITE**
```
Modified SENAITE (GPL-2.0)
    +
bioMate proprietary wrapper
    =
Distributed product
```
- ❌ **RISKY**
- If distributed as integrated product, likely GPL
- If kept separate (API), safer

#### Obligations under GPL-2.0 (if triggered):

1. **Provide complete source code** to recipients
2. **License derivative works under GPL-2.0**
3. **Include GPL license and copyright notices**
4. **Document changes** if modified
5. **Cannot add additional restrictions**

#### The GPL Linking Debate:

**Conservative interpretation (safest):**
- Any linking (static or dynamic) creates derivative work
- API calls in same process = linking
- Triggers GPL for entire application

**Liberal interpretation (risky):**
- Only static linking or modification triggers GPL
- Separate processes communicating via API/network = okay
- SaaS use doesn't trigger distribution

**Recommended approach:** Assume conservative interpretation for commercial product

---

## Commercial Risk Assessment

### OpenELIS (MPL 2.0)

**Risk Level:** ✅ **LOW**

**Can bioMate:**
- ✅ Use as separate service? **YES**
- ✅ Modify and integrate? **YES (with source disclosure of MPL files)**
- ✅ Extract components? **YES (keep MPL files MPL)**
- ✅ Remain proprietary? **YES**
- ✅ Sell commercially? **YES**
- ✅ Keep bioMate code closed? **YES (except MPL files)**

**Obligations:**
- Disclose source of modified MPL files
- Include MPL license notices
- Document which files are MPL

**Legal clarity:** ✅ **High** - well-understood, widely used

---

### Bika LIMS/SENAITE (GPL-2.0)

**Risk Level:** ⚠️ **MEDIUM to HIGH**

**Can bioMate:**
- ✅ Use as separate service (API)? **Probably YES (gray area)**
- ❌ Link libraries directly? **NO**
- ❌ Extract code into bioMate? **HIGH RISK**
- ⚠️ Remain proprietary? **Only if strict separation**
- ✅ Sell commercially? **YES (if GPL obligations met)**
- ❌ Keep bioMate code closed? **RISKY**

**Safe usage:**
- Keep SENAITE completely separate (different containers)
- Communicate only via network API (HTTP/REST)
- No shared libraries or code
- Clear separation of codebases

**Risky usage:**
- Extracting parser code into bioMate
- Dynamic or static linking
- Embedding SENAITE components
- Tight integration

**Obligations (if triggered):**
- Release ALL bioMate source code under GPL-2.0
- Provide source to all customers
- Allow redistribution and modification

**Legal clarity:** ⚠️ **Medium** - some uncertainty around network use

---

## Comparison Matrix

| Feature | OpenELIS (MPL 2.0) | SENAITE (GPL-2.0) |
|---------|-------------------|-------------------|
| **Use as separate service** | ✅ No restrictions | ⚠️ Probably okay |
| **Modify source** | ✅ Disclose modified files | ❌ Entire work becomes GPL |
| **Extract components** | ✅ Keep MPL files MPL | ❌ Derivative work = GPL |
| **Link libraries** | ✅ Allowed | ❌ Triggers GPL |
| **Keep bioMate proprietary** | ✅ YES | ⚠️ Only with strict separation |
| **Commercial sales** | ✅ No restrictions | ✅ Allowed (if GPL followed) |
| **Source code disclosure** | ✅ Only MPL files | ❌ ALL code (if triggered) |
| **Legal clarity** | ✅ High | ⚠️ Medium |
| **Investor concerns** | ✅ None | ⚠️ Potential issues |
| **Acquisition/exit** | ✅ Clean IP | ⚠️ Complicated IP |

---

## Real-World Examples

### Companies Using GPL Software

**Successful GPL-based businesses:**
- **Red Hat** - Sells GPL Linux support
- **Automattic** - WordPress (GPL) + proprietary SaaS
- **GitLab** - Open core (GPL) + proprietary features

**Key:** They either:
1. Sell services/support (not software)
2. Dual-license (GPL + commercial)
3. Open-core model (GPL base + proprietary add-ons)

### Companies Using MPL Software

- **Mozilla Firefox** - MPL browser
- **HashiCorp** - Originally MPL (changed to BSL)
- Many commercial products using MPL libraries

**Key:** MPL allows proprietary combination easily

---

## Recommended Approaches for bioMate

### Option 1: Use OpenELIS (SAFEST)

```
┌─────────────────────────────────────────────────────────┐
│                 OpenELIS (MPL 2.0)                      │
│                 - 13+ instruments                       │
│                 - Clinical focus                        │
└────────────────────┬────────────────────────────────────┘
                     │ REST API
                     ↓
┌─────────────────────────────────────────────────────────┐
│          bioMate Platform (Proprietary)                 │
│          - Workflow orchestration                       │
│          - Analytics                                    │
└─────────────────────────────────────────────────────────┘
```

**Benefits:**
- ✅ No GPL concerns
- ✅ Clean IP for investors/acquisition
- ✅ Can modify OpenELIS (disclose changes)
- ✅ bioMate stays 100% proprietary

**Limitations:**
- Only 13+ instruments (vs SENAITE 60+)
- No spectroscopy/chromatography

---

### Option 2: SENAITE as External Service (CAREFUL)

```
┌─────────────────────────────────────────────────────────┐
│              SENAITE (GPL-2.0)                          │
│              - 60+ instruments                          │
│              - Separate container/VM                    │
│              - No code sharing with bioMate             │
└────────────────────┬────────────────────────────────────┘
                     │ HTTP REST API ONLY
                     │ (Network boundary)
                     ↓
┌─────────────────────────────────────────────────────────┐
│          bioMate Platform (Proprietary)                 │
│          - Completely separate codebase                 │
│          - No SENAITE libraries                         │
│          - No SENAITE code                              │
└─────────────────────────────────────────────────────────┘
```

**Requirements for GPL safety:**
1. ✅ Separate Docker containers
2. ✅ Communication via HTTP/REST only
3. ✅ No shared libraries
4. ✅ No SENAITE code in bioMate
5. ✅ Clear architectural separation

**Benefits:**
- ✅ Access to 60+ instruments
- ⚠️ bioMate probably stays proprietary

**Risks:**
- ⚠️ Legal gray area
- ⚠️ May concern investors
- ⚠️ Could complicate acquisition

---

### Option 3: Dual Integration (RECOMMENDED)

```
Research Labs                          Clinical Labs
     ↓                                      ↓
SENAITE (GPL-2.0)                    OpenELIS (MPL 2.0)
- 60+ instruments                    - 13+ instruments
- Spectroscopy                       - Clinical focus
- Chromatography                     - Public health
     ↓ API                                 ↓ API
     └──────────────┬──────────────────────┘
                    ↓
         ┌──────────────────────────┐
         │  bioMate (Proprietary)   │
         │  - Universal interface   │
         │  - Both integrations     │
         └──────────────────────────┘
```

**Benefits:**
- ✅ Best of both worlds
- ✅ 60+ instruments via SENAITE
- ✅ Clean IP via OpenELIS
- ✅ Customer choice

**Approach:**
- Primary: OpenELIS (clean IP, commercial-friendly)
- Optional: SENAITE add-on (for customers who need it)
- Separate products if needed

---

### Option 4: Extract MPL Components Only (ULTRA-SAFE)

```
Source: OpenELIS (MPL 2.0)

Extract ONLY:
├── Analyzer parsers (MPL)
├── ASTM support (MPL)
└── Result import (MPL)

Build:
┌─────────────────────────────────────┐
│  bioMate Analyzer Service           │
│  ├── OpenELIS parsers (MPL files)   │
│  ├── bioMate wrapper (Proprietary)  │
│  └── bioMate API (Proprietary)      │
└─────────────────────────────────────┘
```

**Requirements:**
- Keep extracted MPL files as separate modules
- Clearly mark which files are MPL
- Provide source for MPL files
- bioMate wrapper is proprietary

**Benefits:**
- ✅ Clean IP
- ✅ Well-defined obligations
- ✅ No GPL risk
- ✅ Investor-friendly

**Limitations:**
- Only 13+ instruments (OpenELIS scope)

---

## Legal Recommendations

### Get Legal Counsel

⚠️ **Important:** This analysis is informational only. Consult with IP attorney for:

1. **GPL interpretation** specific to your architecture
2. **License compliance review** of final integration
3. **Due diligence preparation** for investors/acquisition
4. **Terms of service** that address license obligations

### Best Practices

1. **Document architecture clearly**
   - Show separation between GPL and proprietary
   - Diagram API boundaries
   - Prove no code sharing

2. **Maintain separate repositories**
   - bioMate repo (proprietary)
   - SENAITE/OpenELIS deployments (GPL/MPL)
   - Clear commit history

3. **License compliance file**
   - List all dependencies
   - Document license for each
   - Explain compliance approach

4. **Investor/acquisition preparation**
   - Clean IP audit
   - License compliance report
   - Risk assessment

---

## Final Recommendations

### For Maximum Commercial Safety:

**Tier 1 (Safest):**
✅ Use **OpenELIS** (MPL 2.0) as primary integration
- 13+ instruments
- Clean IP
- Investor-friendly
- No GPL concerns

**Tier 2 (Acceptable with proper architecture):**
⚠️ Offer **SENAITE** as optional add-on
- Strict API separation
- Separate containers
- Document architecture
- Legal review

**Tier 3 (Avoid):**
❌ Do NOT extract SENAITE code into bioMate
❌ Do NOT link SENAITE libraries
❌ Do NOT create derivative work

### Recommended Strategy:

```
Phase 1: OpenELIS Integration
- Build with MPL-licensed OpenELIS
- 13+ instruments, clean IP
- Prove bioMate value proposition

Phase 2: SENAITE Add-on (if market demands)
- Offer as separate module
- Strict API integration
- Legal review completed
- Customer deploys SENAITE separately

Phase 3: Commercial Success
- Raise funding / Exit with clean IP
- Optional: Negotiate commercial SENAITE license
- Or: Build proprietary parsers for key instruments
```

---

## Conclusion

**For commercial bioMate platform:**

✅ **OpenELIS (MPL 2.0):** **RECOMMENDED**
- Commercial-friendly
- Clean IP
- Investor-safe
- 13+ instruments sufficient for many labs

⚠️ **SENAITE (GPL-2.0):** **USE WITH CAUTION**
- 60+ instruments attractive
- BUT: GPL risks for commercial product
- Safe ONLY with strict API separation
- Get legal review

**The 60+ instruments of SENAITE are appealing, but the GPL licensing adds significant complexity and risk for a commercial product like bioMate. OpenELIS's 13+ instruments with MPL licensing is the safer commercial choice.**

---

**Document Version:** 1.0
**Last Updated:** 2025-10-25
**Status:** Legal guidance needed - consult IP attorney
**Disclaimer:** This is not legal advice. Consult qualified IP counsel for your specific situation.
