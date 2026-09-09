# China Partner — Original Requirement (English)

**Prepared for:** external review (Andrew)
**Date:** 2026-09-08
**What this is:** a faithful English statement of the requirement/inquiry received from our China-based partner, presented on its own — i.e. *what the partner is asking for*, separated from BioMate's internal capability assessment, positioning, or commercial counter-strategy (those live in a separate internal document).

> **Provenance note.** This is a faithful English *reconstruction* of the partner's inquiry as recorded in our working notes, not a verbatim translation of a single source message. The partner communicated in Chinese; specific Chinese terms they used are preserved in parentheses. If a verbatim translation of the original Chinese text is needed, we can produce one once the original message is provided.

---

## 1. Who the partner is, and the relationship they propose

- The partner is a **China-based agent/partner**: a CEO plus a (non-technical) business lead, with **deep, long-standing hospital relationships in China**.
- They propose to **co-develop a China-localized edition of BioMate** and **carry it into the China market themselves**.
- Their side brings **hospital access, market reach, on-site deployment/maintenance, and regulatory/procurement navigation**; our side brings **the platform and the underlying methods**.
- They envision **two lines of business together**: (1) licensing/deploying the localized platform to hospitals and pharma, and (2) **joint, hospital-based drug-R&D collaboration** using the platform plus hospital data.

## 2. The commercial model they proposed

- **Co-develop a localized, "cut-down"/subset edition** (阉割版) tailored to China — a joint build.
- **The partner owns the China market** — sales, hospital relationships, deployment, and **on-site maintenance performed by their own engineers** (trained and certified by us).
- **Revenue sharing by percentage**, applied to **both** (a) platform license revenue and (b) the upside from joint drug-development programs.
- **Two revenue streams:**
  1. **Platform licensing/subscription** — per hospital / per department / per capability package.
  2. **Joint drug-R&D programs** (target → lead → IND), **sharing asset/milestone upside with the hospitals.**
- **Maintenance & support:** their technical staff handle on-site install/update/support; we provide remote L2/L3 support (where permitted), training, certification, and a maintenance SLA.

## 3. Their explicit product & technical requirements for the China edition

The partner set out the following as necessary for the China market:

1. **Full Chinese localization** — the interface, reports, and AI-generated narrative output all in Chinese; Chinese medical/genomic terminology; China-population reference data where relevant.
2. **Domestic LLM support, running on-premise** — because patient/genetic data cannot leave the hospital, the system must run **domestic, self-hostable AI models** (e.g. DeepSeek / Qwen / GLM-class) on the **hospital's own GPUs, fully offline** — not a hosted foreign model.
3. **On-premise / air-gapped / domestic-stack (国产化 / 信创) deployment** — a fully offline install that runs on **domestic operating systems, CPUs/GPUs, and databases** (e.g. 麒麟/统信 OS, 鲲鹏/昇腾 chips, 达梦-class DB).
4. **Data residency & regulatory compliance** — conformance with China's **Human Genetic Resources Regulation, PIPL, Data Security Law, and Cybersecurity Law**; hospital ethics/IRB workflows; audit logging for regulators. All patient/genetic data stays on hospital hardware.
5. **Integration with the hospital's internal resources — for both input and output** — connect to hospital **sequencers, LIS/HIS, and electronic lab notebooks** so data flows in without manual re-upload, and results flow back into the hospital's own report systems.
6. **Modular / departmental subsetting** *(the partner explicitly raised this)* — a given department (e.g. oncology molecular pathology) needs only a **small subset** of the platform's capabilities, not everything; they want **per-department capability packages** — smaller, focused, and separately licensed.
7. **Convenient, code-free tuning of functions, interactions, and resources** *(the partner raised this)* — on-site administrators should be able to **configure the system without programming**: enable/disable modules, set thresholds, allocate resources, choose the local AI model, and adjust the interaction flow.
8. **IP protection** — because the software (and the cut-down edition) sits on-premise inside customer/hospital sites, the core technology must be **protected from inspection/extraction**, and the arrangement needs a clear **IP-ownership split** between the co-developed China-localization work and our retained core platform/method.

## 4. The specific question they asked about drug-development scope

The partner asked **which stage of drug R&D BioMate addresses**, using three Chinese terms:
- **Lead compounds** (先导化合物),
- **Candidate drugs** (候选药), or
- **Drug-efficacy validation** (药物疗效验证)?

*(They want a clear answer on where the platform's strength sits along that progression — this shapes what the joint drug-development programs would pursue.)*

## 5. What the partner would provide

- A **lighthouse pilot hospital**, plus a **specific department, disease, and concrete use-case** with available data.
- **Access to the relevant gene/reference databases** and China-population resources, clarified as to what is licensable/usable on-premise.
- **Regulatory & procurement navigation** — HGR/PIPL/信创 requirements, ethics/IRB, hospital IT/security review.
- **Real hospital data (under a data-use agreement)** for the pilot — governed, on-premise, never leaving the site.
- **A co-development disease/target** to jointly pursue lead compounds (先导化合物).
- **Localization review** — Chinese medical terminology and the report formats hospitals expect.
- **The real on-premise environment details** (hardware/OS/network / 信创 level) at the target hospitals.

---

*Everything above reflects the partner's own ask and proposed structure. BioMate's internal assessment of feasibility, maturity, positioning, commercial terms, legal/IP/regulatory risk, and the recommended response is maintained separately and is not included here.*
