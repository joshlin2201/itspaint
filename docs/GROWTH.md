# Getting this in front of people

Distribution, positioning and money. Ordered by return on effort, with the
things that are currently blocking conversion named first.

Researched 2026-07-29. Sources at the bottom.

---

## The two things blocking everything else

Both are conversion killers and neither is a marketing problem.

### 1. ~~The app is not notarised~~ — done

**Shipped in 0.11.0.** Releases are signed with a Developer ID and notarised,
and the ticket is stapled to both the disk image and the app inside it, so a
first launch works with no network. Gatekeeper opens them with no Control-click
and nothing to clear from a terminal.

This was the item every other line on this page multiplied against, and the
diagnosis in the original version of this section was wrong in an instructive
way: the membership was already paid, and the blocker was a certificate. Worse,
the *first* submissions each sat over an hour in Apple's queue and CI threw away
three green builds treating a ran-out wait as a rejection. Once one submission
was through, the rest came back in under two minutes. Nothing needed buying and
nothing needed a longer wait — it needed a first submission to clear.

Kept here rather than deleted, because "the funnel-breaking item was a
certificate and a wrong assumption about a timeout" is the sort of thing worth
not rediscovering.

### 2. There is no `brew install`

`brew install --cask itspaint` is how Mac developers install Mac software. It
gives permanent discoverability, carries trust we cannot manufacture, and makes
updates automatic.

**The official repo will reject it today, and not for a technical reason.**
Homebrew's [Package Acceptance Policy](https://docs.brew.sh/Package-Acceptance-Policy)
gates on notability, and the numbers matter in a way that is easy to get wrong —
they are joined by **or**, not *and*, and they **triple for a self-submission**:

| | forks | watchers | stars |
|---|---|---|---|
| Someone else submits it | 30 | 30 | **75** |
| **You submit your own project** | 90 | 90 | **225** |

Any *one* of the three is enough. And separately: *"A code repository less than 30
days old is normally not eligible"*, plus it must be *"software with a public
presence independent of Homebrew and a homepage that explains the project"*.

This repository was created 2026-07-29 at 0 forks / 0 watchers / 0 stars, so it
fails on age **and** on every metric. Earliest eligibility is around
**2026-08-28**, and because Josh owns the repo the bar is the 225-star column
unless a third party submits it.

**The cheaper door is the left-hand column.** Any *one* of 30 forks, 30
watchers or 75 stars is enough when someone other than the author submits it,
and 30 watchers is a tenth of the work of 225 stars. The people who file real
issues are the ones to ask, once they have used it for a while — not on the day
they report a bug.

That inverts the order this document was written in. The cask is not what
unblocks distribution; **distribution is what unblocks the cask**, and 225 stars
is the concrete number the posting work below is aiming at.

**A personal tap has no notability gate, and it is live now:**

```bash
brew install --cask joshlin2201/itspaint/itspaint
```

[joshlin2201/homebrew-itspaint](https://github.com/joshlin2201/homebrew-itspaint).
The fully qualified name is deliberate — since Homebrew 6.0.0 third-party taps
require explicit trust, and installing by fully qualified name trusts *only that
cask* rather than the whole tap. `brew tap` followed by a bare name additionally
needs `brew trust --cask`, which is a worse first instruction to give someone.

The cask is the same one an eventual `homebrew-cask` submission will carry, so
none of the work is wasted; only the venue changes.

### Two things to fix before submitting upstream

**~~Stop marking releases as pre-releases~~ — done in 0.12.0.** This is the larger of the two, and it
is not about the version number — nothing in current policy requires 1.0. It is
that `homebrew-cask`'s autobump and both of its GitHub livecheck strategies
discard pre-releases outright (`github_releases.rb` does
`next if release["draft"] || release["prerelease"]`). So the cask here has to
read **git tags** instead, and submitting that upstream means asking maintainers
to merge a non-standard livecheck block whose only purpose is to defeat the
pre-release filter. Worse, the flag is a public statement that this is not the
channel you recommend for most users, while the unversioned cask is supposed to
track exactly that channel. Drop the flag and the cask simplifies to a bare
`strategy :github_latest` and the objection disappears.

The flag came off 0.12.0 and the tap's cask now carries exactly that bare
`strategy :github_latest`; `brew livecheck` resolves 0.12.0 against it. The
non-standard git-tag block, and the paragraph of comment explaining why it had
to exist, are gone.

**Disclose the AI assistance.** `homebrew-cask`'s CONTRIBUTING requires stating
in the PR that an LLM was used and which one, requires that you have reviewed it
yourself and can answer maintainer questions without one, forbids
`Co-developed-by`/`Assisted-by` trailers, and limits non-maintainers to one
AI-assisted PR open at a time.

---

## Where to post, ranked

**Read this first: three of these are one-shot.** Show HN explicitly excludes
version bumps — *"New features and upgrades ('Foo 1.3.1 is out') generally
aren't substantive enough to be Show HNs"* — so you get one, and it should be
spent at the version you would call 1.0, not at 0.11. r/macapps permits
*"not more than once per developer in 30 days"*. AlternativeTo makes new
accounts wait a week before they can submit an app. Sequence accordingly; the
order below is the order to do them in, not a ranking by value.

### Now — free, and they compound

| | Why | Effort |
|---|---|---|
| **Repo `homepage` field** | Was null. It is the link GitHub surfaces in search, on topic pages and in the sidebar. | Done |
| **A README GIF** | Every other channel resolves to the README, and the argument *is* the demo: auto-numbered step badges and token redaction, the two things Markup cannot do. | An hour |
| **[awesome-mac](https://github.com/jaywcjlove/awesome-mac)** — 108k stars | Merges in **under a day**, measured across its last 28 merged PRs. **Paintbrush is already listed in the same section**, which makes the positioning legible to the maintainer for free. | 20 minutes |
| **A personal Homebrew tap** | `brew tap joshlin2201/itspaint` — no notability gate, works today, same cask file the official PR will carry. | An hour |
| **[AlternativeTo](https://alternativeto.net/software/paintbrush/about/) account** | One-week wait before you can submit, so the clock starts when the account does. The Paintbrush page already lists 33 alternatives — this is the channel that matches the positioning exactly, and it keeps paying for years rather than for a day. | 5 minutes |

### At 1.0 — the one-shots

**Show HN**, and the data is not what the blogs say. Across 167 macOS Show HN
posts scoring ≥100 since January 2025: **41% were posted 06:00–09:59 PT**, 63%
between 03:00 and 11:00 PT. Day of week is essentially flat — Thursday 30,
Monday 25, Friday 25, Sunday 23 — so "never post on a Friday" does not survive
contact with the numbers. **Hour is what matters; the day barely does.**

The intro comment is not the differentiator either. HN does not allow text on a
URL submission, and only 22% of high-scoring Mac Show HNs had a top-level
comment from the author at all — but **98% commented somewhere, a median of 12
times**. The job is being awake and answering for the following six to eight
hours.

Title, ≤80 characters (the cap is real; measured max across 296 posts is exactly
80, median 66):

> `Show HN: ItsPaint – native Mac paint and screenshot markup, no network, MIT`

What kills these posts, from the same cohort: a pricing surprise mid-thread, and
**unverifiable claims**. "No network code at all" will be stress-tested, so make
it falsifiable in the README — no network entitlement in the sandbox
entitlements, no `URLSession` or `NWConnection` anywhere in the source, and the
`otool -L` output. A checkable claim is worth a hundred points; an unbacked one
reads as marketing.

**r/macapps** — 229k members, one post per developer per 30 days. Lead with
free, MIT, no account, no telemetry: that subreddit is saturated with paid
utilities and reacts well to the opposite.

### Then — evergreen, once the assets exist

- **AlternativeTo**, as an alternative on both the Paintbrush and Microsoft Paint
  pages. Approval takes days to a week.
- **[open-source-mac-os-apps](https://github.com/serhii-londar/open-source-mac-os-apps)**
  — 49k stars, but edit `applications.json`, not the generated README, and expect
  months: its most recent merge was 2026-03-25 with 150 PRs open. Submit and
  forget. Its `applications.json` on `master` is currently invalid JSON — a
  trailing comma — and fixing that in the same PR is a cheap way to get the
  maintainer to open the tab.
- **[awesome-native-macosx-apps](https://github.com/open-saas-directory/awesome-native-macosx-apps)**
  — small, but "no Electron, truly native" is its entire thesis.
- **[macapp.supply](https://macapp.supply/guidelines)**, and its siblings. Gated
  on *assets*, not code: a sharp icon and three or four quality screenshots
  unlock several directories at once.
- **Michael Tsai's link blog** and **Six Colors** — low traffic, very high signal
  among Mac developers, and links there propagate to MacStories and the podcasts.
- **iOS Dev Weekly** — frame it as the engineering story (pure AppKit, zero
  dependencies), not the product.

### Deprioritise

**Product Hunt.** Roughly 10% of daily launches get Featured, and Featured status
drives most of the outcome. For a free, open-source, developer-facing Mac app,
Show HN dominates — launch there as a same-week secondary at most.

**Lobsters** is invitation-only and restricts the `show` tag for new accounts.
The fastest legitimate way in is having authored something posted there, which a
good Show HN can produce for you.

## The pitch, per channel

The research is consistent that the README functions as the landing page and
the one-line value proposition does most of the work. Ours has to name the empty
slot rather than describe features.

**Show HN title.** State the thing, not the adjective:

> Show HN: ItsPaint – a native macOS paint and markup app with no account, network, or telemetry

**The first comment.** Lead with the observation, not the app:

> Paintbrush, the macOS MS Paint clone, has been abandoned for years and is
> Intel-only. Windows 11 Paint has meanwhile become a real editor — layers,
> transparency, AI fill — but it wants a Microsoft account and a Copilot+ NPU.
> On macOS the only thing in the gap is Markup, which cannot number the steps
> of a bug report or redact a token.
>
> So: eleven tools, both colours and the palette on screen at once, ~5k lines
> of UI-free Swift engine underneath, no third-party dependencies, no network
> code at all, MIT. The document format is a PNG with a JSON sidecar so it
> opens in anything.
>
> The thing I would most like feedback on is [specific open question].

That last line matters more than it looks. It converts a launch post into a
conversation and is the single most reliable way to get comments rather than
silent upvotes.

**r/macapps** wants the GIF first and the philosophy second. **AlternativeTo**
wants the comparison table from [COMPETITIVE.md](COMPETITIVE.md).

---

## Utility worth building to attract people

Ranked by how much traction each buys per hour spent.

1. **A 10-second GIF in the README.** Paste a screenshot, drop three step
   badges, pixelate a token, export. It is the highest-leverage asset on this
   list by a wide margin, and the research is unambiguous that video and
   visuals outperform prose for open-source discovery.
2. **`brew install --cask itspaint`.** Covered above.
3. **PaintKit published as a standalone SwiftPM package.** This is the
   collaborator magnet, not the app. A UI-free, dependency-free Swift raster
   engine with bounded undo, rect-scoped dirty tracking and eight codecs is
   genuinely reusable, and it attracts contributors who will never open the
   editor. It is already a separate package with 211 of its own tests — the
   work is a README, a tag, and a Swift Package Index entry.
4. **Five real `good first issue`s**, each naming the file and the test that
   must pass. CONTRIBUTING already explains the structure; what is missing is a
   list of concrete starting points. Arrowheads, grow/shrink selection, and
   freeform rotate are all well-scoped and self-contained.
5. **The capture layer** ([CAPTURE.md](CAPTURE.md)). This is the retention
   feature, not an acquisition one — but it is what turns a one-time download
   into a daily-use app, and daily use is what produces contributors.
6. **A GitHub Sponsors button.** Low yield, but it is a credibility signal and
   it costs one line in `.github/FUNDING.yml`.

---

## Money

**Constraints we are choosing to keep:** MIT licence, no network, no telemetry,
no accounts. Anything below that violates one of those is off the table
regardless of what it earns.

The blunt fact from the research: the median open-source project earns nothing,
and the projects that do earn combine several models rather than picking one.

### What fits

| Model | Fit | Realistic |
|---|---|---|
| **Free on GitHub, paid on the Mac App Store** | Strong | The standard indie Mac pattern, and legal under MIT. People pay for convenience, sandboxed auto-update, and not thinking about Gatekeeper. Needs the $99/yr account, which we need anyway. |
| **Paid capture product, free paint app** | Strongest | Screenshot tools demonstrably monetise — CleanShot X is ~$29 one-time plus a cloud subscription; Xnapper and Snagit are paid. A one-time price for the capture layer, with the editor staying free and MIT, is the cleanest possible split. Scrolling capture alone is worth it. |
| **GitHub Sponsors / Open Collective** | Weak revenue, strong signal | Do it because it is free, not because it will pay for anything |
| **Open core — paid "Pro" features in the editor** | Poor | Directly contradicts rule 1 in PHILOSOPHY. Features behind a paywall are features that are hidden. |
| **Hosted / cloud / SaaS** | Excluded | There is no network code and that is a feature |

### The recommendation

Sequence it:

1. Notarise. ($99/yr, unblocks everything.)
2. Launch free, MIT, `brew install`. Build the audience with the paint app.
3. Ship the no-permission capture layer (CAPTURE routes 1–2) — still free. This
   is what makes people open the app daily.
4. **Then** charge once, one time, for the capture features that need real work:
   scrolling capture, window picking, delayed capture, multi-display region
   select. Ship it as a separate paid build or an App Store purchase; keep the
   editor and PaintKit MIT and complete.

The reason this ordering works is that it never removes something people
already had, and the paid thing is genuinely expensive to build — which is the
only honest basis for charging for it.

**What not to do:** do not paywall an editor tool, do not add telemetry to
"understand usage", and do not add a cloud upload. Each of those trades the
entire positioning in [COMPETITIVE.md](COMPETITIVE.md) for a small amount of
money.

---

## What could not be verified

Recorded because a plan built on unverified numbers is worse than one with gaps
it knows about.

- **r/opensource and r/swift**: no rules, subscriber counts or karma/age
  requirements. Reddit 403s all unauthenticated access and the mirrors are
  proof-of-work gated. Check the sidebar before posting.
- **r/macapps**: the 229k members and the once-per-30-days rule are from a
  third-party index dated 2026-06-04, not from Reddit. Verify in the composer.
- **macapp.supply**: price and turnaround are not published.
- **`apps@sixcolors.com`**: appears in Six Colors' own round-up boilerplate but
  is not listed on their About page. Likely current, not confirmed.
- **Product Hunt's 10% Featured rate**: secondary sources, methodology not
  published.

## Sources

- [5 tips for promoting your open source project — GitHub Blog](https://github.blog/open-source/maintainers/5-tips-for-promoting-your-open-source-project/)
- [Finding Users for Your Project — Open Source Guides](https://opensource.guide/finding-users/)
- [Open Source Marketing: The Complete Guide 2026 — daily.dev](https://business.daily.dev/resources/open-source-marketing-complete-guide-growing-your-project-2026/)
- [How to promote my open source project — Zenika](https://github.com/zenika-open-source/promote-open-source-project)
- [Marketing Open Source Projects — TODO Group](https://todogroup.org/resources/guides/marketing-open-source-projects/)
- [Open Source Monetization: How Developers Are Actually Making Money in 2026 — DEV](https://dev.to/zny10289/open-source-software-monetization-how-developers-are-actually-making-money-in-2026-4ddh)
- [Open Source Monetization 2026: 5 Proven Models — EarnifyHub](https://earnifyhub.com/blog/open-source-monetization-making-money-from-free-software.php)
- [open-source-mac-os-apps: 689 tools — BrightCoding](https://www.blog.brightcoding.dev/2026/04/24/open-source-mac-os-apps-689-free-tools-for-macos-power-users)
- [5 Best CleanShot X Alternatives 2026 — screensnap.pro](https://www.screensnap.pro/blog/best-cleanshot-x-alternative-in-2026-plus-4-more-options-for-mac-users)
