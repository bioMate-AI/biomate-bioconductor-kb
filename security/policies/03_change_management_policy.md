# Change Management Policy

| | |
|---|---|
| **Version** | 0.1 DRAFT |
| **Owner** | `[CONFIRM: Engineering lead]` |
| **Effective date** | `[CONFIRM]` |
| **Review cadence** | Annual |

## 1. Purpose
Ensure changes to the production environment are authorized, tested, reviewed, and traceable. Supports CC8.1.

## 2. Scope
All changes to application code, infrastructure, and configuration affecting the BioMate AI Assistant Services System.

## 3. Policy statements
1. **Source control.** All code changes are made through Git and merged only via pull request to protected branches (`main`, `integration/next-phase`).
2. **Peer review.** Each production change requires review and approval by a person other than the author before merge. `[CONFIRM: for a small team, document how developer/QA/approver separation is achieved, or the compensating control.]`
3. **Automated testing.** A required CI test suite runs on pull requests (full backend suite) and on protected-branch pushes (smoke tests); merges are blocked on failure.
4. **Deployment.** Deployments run through GitHub Actions → AWS SSM with pre-/post-deploy health gates and automatic rollback to the prior image on health-gate failure.
5. **Traceability.** Each change is traceable to a pull request capturing author, reviewer/approver, and merge activity, retained as the change population for audit.
6. **Emergency changes.** `[CONFIRM: define the expedited path for urgent fixes — who authorizes, and the requirement to open a retroactive PR/record.]`
7. **Segregation.** No developer deploys unreviewed code directly to production; direct out-of-band changes to the production host are prohibited (per the deploy-process discipline).

## 4. Roles & responsibilities
- **Engineering lead** — owns the pipeline, branch protection, and CI gates.
- **Developers** — open PRs, obtain review, do not bypass gates.

## 5. Enforcement & 6. Review
Per the Information Security Policy. Reviewed annually.
