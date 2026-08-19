# Documentation

Six documents about the app, in the order they are worth reading.

| | |
|---|---|
| **[PHILOSOPHY.md](PHILOSOPHY.md)** | Why the app is shaped this way: the five rules, what each costs, and the list of things it deliberately is not. **Start here** — every other document assumes it. |
| **[ARCHITECTURE.md](ARCHITECTURE.md)** | The anatomy: module map, the one dependency rule, how a gesture becomes pixels, the state machine, undo, the document format, and recipes for adding a tool, a shape or an export format. |
| **[DESIGN.md](DESIGN.md)** | The design language: chrome anatomy, the real token values, surfaces, colour, iconography, motion, zoom, accessibility — and the weaknesses stated plainly. |
| **[FEATURES.md](FEATURES.md)** | What every tool and command actually does, including the behaviour that is easy to miss. The reference to check a bug report against. |
| **[TESTING.md](TESTING.md)** | The testing protocol: what each suite is for, how to write a test that stays useful, the guard tests, and the three app-host failure modes that each cost a day. |
| **[ROADMAP.md](ROADMAP.md)** | Path forward — now / next / later, what is explicitly not planned, and exactly how a release is cut. |

Four about where it goes and who else is in the space:

| | |
|---|---|
| **[COMPETITIVE.md](COMPETITIVE.md)** | The capability map against Windows 11 Paint and macOS Markup, the rest of the field, and the two empty slots the positioning comes from. |
| **[CAPTURE.md](CAPTURE.md)** | Replacing the screenshot workflow: everything macOS's own capture tools do, four routes in ranked by what they cost the user in permissions, and the integration surfaces that cost nothing. |
| **[GROWTH.md](GROWTH.md)** | Distribution, where to post and what to say, the utility worth building to attract contributors, and which money models survive the constraints in PHILOSOPHY. |
| **[APP_STORE.md](APP_STORE.md)** | The Mac App Store submission kit: every App Store Connect field pre-written, the archive/export script, the screenshot pipeline, and the steps only the account holder can do. |

## Write-ups

Standalone pieces about one mechanism each, written to be read by someone who does
not use this app.

- **[A_GUARD_TUNED_TO_ITS_TEST.md](A_GUARD_TUNED_TO_ITS_TEST.md)** — a safety check
  that rejected an image more certainly the better it fitted the feature, for three
  releases. A threshold satisfied by its own test fixture and crossed by ordinary
  input, kept invisible by a paragraph arguing the failure was deliberate.
- **[CHECKS_THAT_MISS.md](CHECKS_THAT_MISS.md)** — a running list of checks that
  passed while the thing they were checking was broken, some in the app and more in
  the release tooling. A guard satisfied only by its own fixture, a probe that read
  the exit code instead of the pixels, a health check verifying a different service
  than the one it gated, and a quorum gate with one judge left alive.
- **[BACKGROUND_REMOVAL.md](BACKGROUND_REMOVAL.md)** — taking a product shot off its
  page with no model, no weights and no network: four corner-seeded flood fills
  unioned, in about thirty lines on top of the paint bucket.
- **[PROVING_NO_NETWORK.md](PROVING_NO_NETWORK.md)** — making "it never contacts
  anything" falsifiable rather than asserted, and why the entitlements check goes
  first: it reports what the kernel will permit, not what the developer wrote.

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

The engine is a separate, UI-free package: `Packages/PaintKit` imports no AppKit and
no third-party code, declares macOS 12, and `swift test` runs it in a fresh clone with
no Xcode. It ships often while it is in beta. **Watch ▸ Custom ▸ Releases** is the
quietest way to hear about a new build — it does not mail you issues or comments.
