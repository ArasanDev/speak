---
name: pe3c3-more-affordance
description: PE-3c-3 ⌄more affordance design — panel height analysis, expansion flag pattern, rareCategories derivation
metadata:
  type: project
---

PE-3c-3 landed in commit `70a0dc2` (branch `pe/pe-3c-3`). The `Code` category is surfaced behind a `⌄more` button in the `agentCategoryPage` header.

Key design decisions:

**Panel height**: Fixed at 112 pt (`TranscriptOverlayPanel.panelHeight`). The expanded 3-row card (header + primary + rare) is estimated ~87 pt (63 pt VStack + 24 pt vertical padding), fitting with ~12 pt spare. No height change needed — do NOT bump panelHeight for this feature.

**Expansion flag on OverlayViewModel**: `isCategoryMoreExpanded: Bool = false`. Reset only on the open path (`profileButton` when `.agent` is picked, i.e. `model.isCategoryMoreExpanded = false` before `model.isShowingAgentCategories = true`). No OverlayController change needed.

**rareCategories derived dynamically**: `AgentCategory.allCases.filter { !primaryCategories.contains($0) }` — any future AgentCategory addition is automatically covered, making `primaryCategories` the single source of truth.

**No animation on reveal** [decision PE-3c-3]: consistent with the card's instant transitions; reduce-motion is moot since the baseline is also unanimated.

**Spacer(minLength: 0) in the rare row** prevents a single Code button from stretching full-width (all category buttons use `.frame(maxWidth: .infinity)` inside).

Gates: build ✅ / test 548,5-skip,0-fail ✅ / lint 0 serious ✅ / moat 7/7 ✅.

**Why:** Panel height was the main blind spot — gates never catch a clipped row. Always estimate content height vs. panel height before adding rows to the category page.

**How to apply:** When adding further rows to the overlay card, re-estimate height against `panelHeight = 112 pt`. If the expanded content exceeds 100 pt (with 12 pt spare), a height bump in `TranscriptOverlayPanel.swift` is needed.
