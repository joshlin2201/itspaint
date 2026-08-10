# Security

ItsPaint is a local image editor. It has no network code, no analytics and no
accounts — it opens files you point it at and writes files you ask it to write.
It is sandboxed, with read/write access only to files you choose.

## Reporting a vulnerability

Please open a
[private security advisory](https://github.com/joshlin2201/itspaint/security/advisories/new)
rather than a public issue. I will confirm within a week and credit you in the
release notes unless you would rather I did not.

Things worth reporting: anything that reads or writes outside the sandbox,
anything that executes data from an opened file, or a crash reachable from a
malformed image (decoding goes through ImageIO, but the `.itspaint` package
parser is ours).

## Releases

Release builds are produced by GitHub Actions from a tag, and every download is
listed with a SHA-256 in `checksums.txt`.

**Published builds are signed with a Developer ID and notarised by Apple**, with
the ticket stapled to both the disk image and the app inside it, so the check
needs no network. Verify a download before opening it:

```bash
shasum -a 256 -c checksums.txt
xcrun stapler validate ItsPaint-*.dmg
spctl -a -vvv -t exec /Volumes/ItsPaint*/ItsPaint.app   # expect: accepted
```

The signing certificate and the notarisation credentials are Actions secrets and
are not in the repository. Builds you make yourself are ad-hoc signed, because a
Developer ID certificate cannot live in a public checkout — that is a statement
about *your* build, not about the ones on the releases page.

> This section previously said releases were "ad-hoc signed, not notarised". That
> was true when it was written and stopped being true at 0.10.0, and it sat here
> wrong for six releases. A security document that describes a process the
> project no longer follows is worse than one that says nothing, because it is
> the document a reader trusts to be current.

If you would rather not trust a binary at all, building from source takes one
command.
