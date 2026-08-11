# Every check that failed here verified something next to the claim

This is a list of checks that passed while the thing they were checking was broken.

They come from [ItsPaint](https://github.com/joshlin2201/itspaint), a free open-source
paint and markup app for the Mac, and from the tooling around it — three are in the
app and its tests, four are in the release and publishing machinery. That split is
worth stating rather than blurring, because the machinery is where the sloppier checks
live: nobody reviews a health check.

All were found between 2026-08-08 and 2026-08-11, most of them in one day, which is
what made them worth writing down. They are not seven different mistakes. They are one
mistake with seven costumes.

The shape is always the same. There is a claim. Checking the claim directly is
awkward, slow, or requires a thing you do not have. So you check something adjacent
that correlates with it — and correlation is exactly the property that holds right up
until the moment you needed the check.

## 1. The guard whose test was the only input that satisfied it

`Image ▸ Remove Background` refused to run if the page covered more than 92% of the
canvas, so it could not hand back a blank image. Its test passed. Its fixture was a
40×20 canvas with a 20×8 subject — 80% background, comfortably under the line.

A logo on a white sweep is 97%+ background. The command refused the images it existed
for, more certainly the better they fitted, for three releases.

The full write-up is
[a guard tuned to its test](A_GUARD_TUNED_TO_ITS_TEST.md). The one line worth
carrying: **a constant can be satisfied by its test and by nothing a person would ever
open.** Fixtures get sized for legibility. Thresholds get written against whatever
fixture is already there.

## 2. The probe that checked the exit code, not the pixels

Fixed version of the above. To show `PaintKit` working as a dependency, I wrote four
lines that decode a PNG, call `removeBackground()`, and write the result out. It built
against the published tag and ran over four real images.

Four exit-zeros. Four files written. **Two of those files were byte-identical to their
inputs**, with `true` returned.

They were images whose page was already transparent. The flood selected it, the
subject survived so the remainder guard was satisfied, and clearing already-clear
pixels succeeded at doing nothing. Success was reported, an undo step was pushed, the
document was marked dirty, and nothing changed.

The check was "did it exit zero and write a file". The claim was "it removes the
background". Those come apart on exactly the input where it matters, and the only
thing that surfaced it was counting transparent pixels before and after.

## 3. The shell that ran the previous binary

While fixing that, I rewrote the probe and ran:

```sh
swift build 2>&1 | tail -3 && ./probe a.png b.png c.png
```

The build failed on a compile error. **`tail` exited 0**, because a pipeline's exit
status is its last command's. So `&&` ran the *previous* binary — which took an output
path as its second argument, and overwrote a file in the repository with a
background-removed render of something else. It printed a plausible success line while
doing it.

The commit that fixed it is in the history, and so is the commit that put it there.

## 4. The health check with a selector that did not exist

I wrote a script that verifies every tool this project's release process depends on.
One check asked whether the browser was signed in, by looking for `#user_profile_name`
on a GitHub settings page.

That element does not exist. The check reported a browser signed in as `joshlin2201`
as **anonymous**.

**A false negative in a health check is worse than no health check**, because it
teaches you to scroll past a FAIL. It now reads `meta[name=user-login]`, which is the
identity the page itself declares, and it prints the name it found.

## 5. The health check that verified a different service

Same script, worse version. The check above says "chrome signed in ✓". The thing that
actually depends on a browser session is an outbound mail path, which drives Gmail's
compose window.

GitHub and Google are separate sessions. The browser was signed into GitHub and signed
out of every Google account, so the check was green and the path was dead.

**Verifying a dependency you have is not the same as verifying the dependency you
need.** There are now two checks, and the failing one names the fix.

## 6. The gate with no judges behind it

Before anything gets published here, its wording is scored by three model CLIs, and a
majority of at least two must be happy. For several days, one refused to start because
it wanted a flag, printing the reason as prose on stdout so it recorded as "no
answer" — and another was out of quota.

One judge answered. The quorum is two. **The gate could not block anything and it
printed "preflight passed" every time.** It never printed how many judges had spoken.

Now it does, and a panel sitting exactly *on* quorum renders as DEGRADED rather than
as the same green as everything else, because a count that cannot absorb one more
outage is not healthy.

## 7. Four documents, four different test counts

`docs/TESTING.md` said 293 tests, 211 engine, 82 app. `docs/ARCHITECTURE.md` said 211
engine. `CONTRIBUTING.md` said 275 tests in 40 suites. The suites report 290 engine,
118 app.

Every one of those numbers was true once. None of them was checked again, because
prose does not get re-run. That is the same failure as §1 wearing different clothes,
and it was living in the file called *Testing protocol*, which is where somebody
checking whether this project counts carefully would look first.

There is now a script that runs the suites, reads the counts back out of the
documents, and exits non-zero when they disagree. **It caught this twice in ten
minutes** — once at 288, and again at 290, because two tests had been added between
the two runs. Then it caught its own fix: a stated commit count went stale the moment
the fix was pushed. A number that changes on every push does not belong in prose.

## What actually generalises

- **Name the claim in one sentence, then ask what would be true if the claim were
  false.** If the check would still pass, it is checking something else. "It exited
  zero" is true of a program that did nothing.
- **Fixtures drift from reality in one direction: smaller and tidier.** Look at their
  dimensions. A threshold written against a small fixture has never met real input.
- **Watch a check fail before you trust it to pass.** Stash the fix, run the check, see
  red, restore. A check that has only ever been green is a check you are guessing
  about.
- **A false negative is worse than a missing check.** It trains the reader to skip the
  failure column.
- **A quorum gate must print its count.** Otherwise "everyone agreed" and "nobody
  answered" render identically.
- **A pipeline's exit status is the last command's.** `build | tail && run` runs a
  stale binary on every failed build.
- **Prose is a check that never re-runs.** If a number in a document matters, have
  something measure it and fail.

None of this is clever. It is all the same discipline applied seven times, and the
reason it needed applying seven times is that each disguise looked like a different
problem.

---

The engine is [`Packages/PaintKit`](../Packages/PaintKit), a UI-free Swift package
with no third-party dependencies, so `swift test` in a fresh clone runs its whole
suite with no Xcode and no GUI session — including the regression from §1, which fails
against the old constant.

More in this series: [a guard tuned to its
test](A_GUARD_TUNED_TO_ITS_TEST.md) · [background removal without a
model](BACKGROUND_REMOVAL.md) · [proving an app has no network
access](PROVING_NO_NETWORK.md).
