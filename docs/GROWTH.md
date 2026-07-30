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

`brew install --cask itspaint` is how Mac developers install Mac software. A
cask is a single small PR to `homebrew/homebrew-cask`, it gives permanent
discoverability, it carries trust we cannot manufacture ourselves, and it makes
updates automatic.

**Requirements:** a stable versioned download URL (the GitHub release already
provides this), a published SHA-256 (`checksums.txt` already exists), and
notarisation — all three now hold, so **this is unblocked and is the next thing
to do.**

With notarisation done, the cask is the last mechanical step between the project
and every channel below.

---

## Where to post, ranked

### Tier 1 — worth real preparation

| Channel | Why | What it needs |
|---|---|---|
| **Show HN** | Highest ceiling for a native, no-network, open-source Mac tool. This audience specifically rewards "no accounts, no telemetry, no dependencies". | A working notarised DMG, a GIF above the fold in the README, and a first comment that says *why* rather than *what* |
| **r/macapps** | ~high-intent Mac software audience, and new native apps do well there | The GIF, and answering every comment for 48h |
| **Homebrew Cask** | Permanent, compounding, zero ongoing effort | See above |
| **awesome-mac** ([jaywcjlove](https://github.com/jaywcjlove/awesome-mac)) and **open-source-mac-os-apps** ([serhii-londar](https://github.com/serhii-londar/open-source-mac-os-apps)) | Two of the highest-traffic Mac software lists on GitHub. A PR each. | One line each |

### Tier 2 — cheap, do them all in an afternoon

- **AlternativeTo** — list as an alternative to Microsoft Paint, Paintbrush,
  Skitch and Markup. Long-tail search traffic, permanently.
- **r/opensource, r/swift, r/MacOS** — different framings of the same post.
- **Lobste.rs** — smaller than HN, higher signal, likes native and dependency-free.
- **Mastodon / Bluesky** with `#macos #swift #opensource`. The Swift and Mac dev
  communities are genuinely active on both.
- **Product Hunt** — save it for 1.0. Good sustained traffic, less credibility
  with developers than HN, and it burns once.
- **GitHub topics** — `macos`, `swift`, `swiftui`, `image-editor`,
  `screenshot`, `mspaint`, `paint`. Free discovery inside GitHub search.

### Tier 3 — once there is a 1.0 worth writing about

One short, specific email each to MacStories, 9to5Mac, MacRumors and Six
Colors. Not a press release — a two-paragraph note with the GIF and the
"Paintbrush has been dead for a decade and nothing replaced it" angle, which is
a genuine story rather than a launch announcement.

---

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
> So: twelve tools, both colours and the palette on screen at once, ~5k lines
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
