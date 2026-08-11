# Making "no network, no telemetry" checkable

Every app says it. It is the cheapest sentence in software, it costs nothing to write
whether or not it is true, and a reader has no way to tell the honest ones from the rest.

ItsPaint says it too. This document is how you check, in three commands, against the
build on your disk — and, since the technique is not specific to a paint app, how to make
the same claim checkable in yours.

The order matters. The first command is the strongest and needs no trust at all; the third
is the weakest and needs the most.

---

## 1. The entitlements — the one that does not require trusting anybody

```bash
codesign -d --entitlements - --xml /Applications/ItsPaint.app | plutil -p -
```

```
{
  "com.apple.security.app-sandbox" => true
  "com.apple.security.files.bookmarks.app-scope" => true
  "com.apple.security.files.user-selected.read-write" => true
}
```

Three entries. The sandbox itself, read-write access to the files you pick in an open or
save panel, and app-scoped bookmarks so recent documents reopen without asking again.

**What is absent is the point.** Neither `com.apple.security.network.client` nor
`com.apple.security.network.server` is there. Inside the App Sandbox those are not
documentation — the kernel enforces them. Without `network.client` a `connect(2)` fails
with `EPERM`. It does not matter what the code contains, what a dependency does at
runtime, what a `dlopen`ed bundle tries, or whether the developer is lying: the process
cannot open an outbound socket, because the operating system will not let it.

You can watch that happen rather than take it on faith. `sandbox-exec` uses the same
enforcement, so a short profile reproduces it on any Mac. Check the errno rather than a
tool's error message — `curl` under this profile may fail at DNS instead of at `connect`,
and the two look different while proving the same thing:

```bash
printf '(version 1)\n(allow default)\n(deny network*)\n' > /tmp/nonet.sb
sandbox-exec -f /tmp/nonet.sb python3 -c '
import socket, errno
s = socket.socket()
try:
    s.connect(("93.184.216.34", 80))
except OSError as e:
    print(errno.errorcode.get(e.errno), e.errno)'
# EPERM 1
```

**`socket()` succeeds and `connect()` fails with `EPERM`** — errno 1, "Operation not
permitted". The file descriptor is handed out; the *connection* is what the kernel
refuses. That distinction is why this page says "refuses an outbound connection" rather
than "refuses a socket".

Run the same thing outside the sandbox against a closed local port and it returns
`ECONNREFUSED` (errno 61). So `EPERM` is the sandbox denying it, not what a failed
connection looks like in general.

This is why it is first. The other two commands tell you what the developer *wrote*. This
one tells you what the app is *permitted to do*, and it is checked by something that has
no stake in the answer.

It also survives an update you did not read. Entitlements are inside the code signature,
so changing them changes the signature — a future version that starts talking to a server
has to declare it, and this command shows it.

## 2. The linked libraries

```bash
otool -L /Applications/ItsPaint.app/Contents/MacOS/ItsPaint
```

Every line is under `/System/Library/Frameworks` or `/usr/lib`, on both architectures
(`lipo -archs` reports `x86_64 arm64`). No `CFNetwork`, no `Network.framework`, no bundled
`.dylib`, no vendored SDK, no analytics framework.

**Be precise about what this does and does not prove.** `otool -L` lists the *linked*
libraries of *one* Mach-O. It says nothing about which of them makes network calls, and
three things evade it entirely: code linked statically into the executable leaves no
`-L` line at all, a bundle loaded later with `dlopen` is not a load command, and an
embedded helper or XPC service is a separate binary you would have to check separately.

For this app that last gap is closable by looking:

```bash
find /Applications/ItsPaint.app -type f -perm -u+x -exec file {} \; | grep Mach-O
```

One file — `Contents/MacOS/ItsPaint`. It prints as three lines, because `file` reports a
universal binary and then each of its two slices; count paths, not lines. There is no
`Frameworks/`, no `XPCServices/` and no `PlugIns/` directory in the bundle, so "the main
executable" and "everything that ships" are the same set, and one `otool -L` covers it.

The static-linking and `dlopen` gaps are not closed by this command in any app, and that
is the honest reason command 1 comes first: the sandbox refuses the connection whether the
code arrived linked, statically bound, or loaded at runtime.

## 3. The source

```bash
grep -rniE 'URLSession|NWConnection|import Network|CFSocket|getaddrinfo' App Packages
```

Zero matches. And `Package.swift` declares no external dependency, so there is no
third-party source behind that grep to audit separately.

This is the weakest of the three and it is worth being honest about why: it only proves
something about the tree you are looking at. It cannot see a build-time transformation,
and it is checking a list of API names somebody chose. It is here because it is easy to
run and it is consistent with the other two, not because it would catch a determined
liar. Commands 1 and 2 are the ones that do that.

---

## Doing this in your own app

The claim is only worth making if it is falsifiable, and making it falsifiable is mostly
about *not asking for things*.

**Request the narrowest entitlements that make the app work, and write down the ones you
deliberately skipped.** ItsPaint's entitlements file spends more lines on absence than on
presence:

```xml
<!--
  Deliberately NOT requested:
    com.apple.security.network.client / .server  — ItsPaint never phones home.
    com.apple.security.assets.pictures.read-write — the open panel covers it.
    com.apple.security.device.camera / .microphone / location
  Every entitlement is a promise to App Review and a line in the privacy
  nutrition label. Asking for one we don't use is a rejection risk and a
  trust cost for nothing.
-->
```

A comment is not enforcement — the enforcement is the missing key. But the comment is what
stops a future contributor from adding `network.client` for a quick fix without noticing
they are spending something.

**Prefer the user's choice to a broad file entitlement.** `files.user-selected.read-write`
grants nothing by itself — access arrives as a security-scoped bookmark for each item the
user actually picks, in an open or save panel or by dragging it in. It replaces blanket
read of the disk, and it is why `assets.pictures.read-write` is not needed here. Note that
`files.bookmarks.app-scope`, which this app also requests, is what lets that access outlive
the panel, so recent documents reopen without re-prompting. Worth being clear-eyed about:
the pair means access persists, one user-chosen item at a time, rather than expiring.

**Check what actually shipped, not what you configured.** These are different, and the gap
is where the surprises live:

- Xcode injects `get-task-allow` into debug builds so the debugger can attach. In a
  distribution build that entitlement should be gone —
  `CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO` is what removes it here. Run command 1 against
  a release build, not a debug one.
- A framework you link can pull in `CFNetwork` transitively. Command 2 is how you find
  out, and it is the reason "we have no analytics" and "we link nothing that has
  analytics" are separate claims.
- SwiftPM dependencies can appear without anyone deciding to add one. An empty
  `dependencies:` array is a much easier thing to verify than a policy.

**Publish the commands, not the conclusion.** "We respect your privacy" asks for trust.
Three commands and their expected output ask for thirty seconds. The second one is
checkable by someone who has never met you and does not believe you, which is the only
kind of trust worth having.

---

The full context — what ItsPaint is and why it has no network code in the first place — is
in the [README](../README.md#no-network-and-how-to-check). The entitlements file is
[`App/Resources/ItsPaint.entitlements`](../App/Resources/ItsPaint.entitlements); it is
short, and the comments are the interesting part.

None of this is a promise about future versions. It is three commands that run against the
build you have.
