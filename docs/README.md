# Documentation

Six documents, in the order they are worth reading.

| | |
|---|---|
| **[PHILOSOPHY.md](PHILOSOPHY.md)** | Why the app is shaped this way: the five rules, what each costs, and the list of things it deliberately is not. **Start here** — every other document assumes it. |
| **[ARCHITECTURE.md](ARCHITECTURE.md)** | The anatomy: module map, the one dependency rule, how a gesture becomes pixels, the state machine, undo, the document format, and recipes for adding a tool, a shape or an export format. |
| **[DESIGN.md](DESIGN.md)** | The design language: chrome anatomy, the real token values, surfaces, colour, iconography, motion, zoom, accessibility — and the weaknesses stated plainly. |
| **[FEATURES.md](FEATURES.md)** | What every tool and command actually does, including the behaviour that is easy to miss. The reference to check a bug report against. |
| **[TESTING.md](TESTING.md)** | The testing protocol: what each suite is for, how to write a test that stays useful, the guard tests, and the three app-host failure modes that each cost a day. |
| **[ROADMAP.md](ROADMAP.md)** | Path forward — now / next / later, what is explicitly not planned, and exactly how a release is cut. |

Two more, kept for the reasoning rather than as current reference:

- **[PLAN.md](PLAN.md)** — the plan of record. A first design, an honest critique
  of it, and the revised plan that was actually built. Kept because a decision
  whose reasoning is lost gets re-litigated every six months.
- **[MAC_ESSENTIALS.md](MAC_ESSENTIALS.md)** — the platform checklist: keyboard,
  menus, documents, accessibility, distribution.

Contributor-facing material lives at the repository root:
[CONTRIBUTING.md](../CONTRIBUTING.md), [SECURITY.md](../SECURITY.md),
[CHANGELOG.md](../CHANGELOG.md).

---

**If you are here to change something**, the short path is:

1. [PHILOSOPHY](PHILOSOPHY.md) § *The five rules* — is the change in bounds?
2. [ARCHITECTURE](ARCHITECTURE.md) § *Adding a tool / shape / export format* —
   where the code goes.
3. [TESTING](TESTING.md) § *What a new tool needs* — the four tests to write.
4. [DESIGN](DESIGN.md) § *Tokens* — if it has a surface.
