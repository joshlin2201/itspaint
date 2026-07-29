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
listed with a SHA-256 in `checksums.txt`. Builds are **ad-hoc signed, not
notarised**: a Developer ID certificate cannot live in a public repository. If
you would rather not trust a binary, building from source takes one command.
