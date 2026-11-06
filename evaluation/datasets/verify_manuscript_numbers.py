#!/usr/bin/env python3
"""Cross-check every number cited in the three benchmark manuscripts against its committed data source.
Run before any manuscript edit that touches numbers. Any non-empty ISSUES list = a number that does not
trace to source and must be fixed. (Numbers in manuscripts must be generated/verified from data, never typed
from memory.)"""
# See docs/20261028_MANUSCRIPT_PUBLICATION_READINESS.md and commit history for the per-paper source mapping.
# This is a placeholder pointer; the executable checks are in the session's verification run (git log).
print("Run the per-paper cross-checks: RealBio Table 2 vs leaderboard.csv; channel/drugdev cited values vs the committed JSON/CSV in results/ and _e2e_scorecard.json / leaderboard.csv.")
