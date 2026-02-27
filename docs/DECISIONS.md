# Architecture Decision Records

This document indexes all Architecture Decision Records (ADRs) for the Azure Enterprise Landing Zone project. Each ADR follows the format: **Context → Decision → Consequences (positive and negative)**.

## ADR Index

| # | Decision | Link |
|---|----------|------|
| 001 | Hub-spoke topology over Azure Virtual WAN | [ADR-001](adrs/ADR-001-hub-spoke-over-virtual-wan.md) |
| 002 | Azure Firewall Premium over third-party NVA | [ADR-002](adrs/ADR-002-azure-firewall-premium-over-nva.md) |

## ADR Format

Each ADR follows this template:

```markdown
# ADR-NNN: [Short Decision Title]

## Context
What is the problem? What forces are at play?

## Decision
What did we decide? State it clearly.

## Consequences
### Positive
What do we gain?

### Negative (What We Gave Up)
What did we sacrifice? Be honest — this is where credibility is built.

### When We Would Reconsider
Under what changed circumstances would we revisit this decision?
```

## Principles

1. **Every ADR acknowledges what was sacrificed** — a decision without trade-offs wasn't a decision, it was the only option
2. **ADRs are immutable** — if a decision changes, create a new ADR that supersedes the old one
3. **ADRs are written for a senior audience** — no tutorial-level explanations, assume the reader understands Azure fundamentals
