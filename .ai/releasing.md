# Releasing and CI

`.github/workflows/release.yml` is the only place Omaccy Hyperkey is built for
distribution. It produces a universal, Developer ID-signed, notarized, stapled
app bundle and publishes it as a GitHub release asset that
`scripts/lib/hyperkey.sh` downloads during setup.

## Triggering

Pushing a `v*` tag builds and publishes:

```sh
git tag v0.3.0 && git push origin v0.3.0
```

Running the workflow manually (Actions → Release Hyperkey → Run workflow, or
`gh workflow run "Release Hyperkey" --ref main`) performs the identical build,
signing, and notarization chain but skips the publish job, which is gated on
`github.ref_type == 'tag'`. Use it to verify credentials without cutting a
release; it still submits to Apple's notary service.

## What the workflow does, and why

The build stamps the version from the tag into `Constants.swift` before
compiling — that value is compiled in, so stamping only `Info.plist` would ship
an app that misreports its own version — and into the bundle's `Info.plist`
when the bundle is assembled. Neither edit is committed.

It builds with `--arch arm64 --arch x86_64`. The runner is arm64 and a plain
`swift build -c release` would yield an arm64-only binary, while `Info.plist`
advertises `LSMinimumSystemVersion 13.0`, a range that includes Intel Macs.
SwiftPM writes universal output to `.build/apple/Products/Release/`, not
`.build/release/`.

The certificate is imported into a temporary keychain whose password is
generated per run, with `-T /usr/bin/codesign` so only codesign may use the key.
The decoded `.p12` is deleted immediately after import, and the keychain is
removed in an `always()` step. The signing identity is selected by certificate
hash rather than name: a keychain can hold several certificates sharing one
Developer ID name, and `codesign` refuses that as ambiguous instead of choosing.

Signing uses `--options runtime --timestamp`; notarization requires both the
hardened runtime and a trusted timestamp. Notarization checks `notarytool`'s
status explicitly rather than relying on its exit code, and dumps
`notarytool log` on anything other than `Accepted`, so a rejection arrives with
Apple's reasons attached. The bundle is then stapled, `stapler validate`d, and
assessed with `spctl`, so an undistributable build fails in CI rather than on a
user's Mac.

Two assets are published: `omaccy-hyperkey-<version>.zip` and a
`.zip.sha256` sidecar containing a bare hex digest. Both the filename pattern
and that format are load-bearing for `install_hyperkey_app_from_release`.

## Secrets

| Secret | Contents |
| --- | --- |
| `APPLE_CERTIFICATE_P12` | base64 of a `.p12` holding the Developer ID Application certificate and its private key |
| `APPLE_CERTIFICATE_PASSWORD` | the `.p12` export password |
| `APPLE_APP_SPECIFIC_PASSWORD` | an app-specific password from appleid.apple.com, not an account password |
| `APPLE_ID` | the Apple ID that generated the app-specific password |
| `APPLE_TEAM_ID` | `Y8R7PRA8UZ` |

A preflight step fails with the names of any that are empty, so a missing secret
is reported before anything is built.

To rotate the certificate, export it from Keychain Access (select both the
certificate and the private key underneath it, right-click → Export), then:

```sh
base64 -i <exported>.p12 | gh secret set APPLE_CERTIFICATE_P12
gh secret set APPLE_CERTIFICATE_PASSWORD
```

`gh secret set` without `--body` prompts, keeping the value out of shell
history. GitHub secrets cannot be read back, so GitHub is not a backup of the
private key: Apple does not retain it either, and losing it means issuing a new
certificate.

Losing the key is recoverable. The designated requirement of a signed bundle
binds to the bundle identifier and the team, not to a particular certificate:

```
identifier "com.omaccy.hyperkey" and anchor apple generic and ... certificate leaf[subject.OU] = Y8R7PRA8UZ
```

so a replacement certificate from the same team produces signatures that satisfy
it, and Accessibility grants survive the change. Let an old certificate expire
rather than revoking it: notarized apps keep launching after their signing
certificate expires, because the trusted timestamp and notary ticket establish
that the signature was made while it was valid, whereas revocation can
invalidate builds already installed.

## Verifying a release by hand

```sh
ditto -x -k omaccy-hyperkey-<version>.zip extracted
spctl --assess --type exec --verbose=4 "extracted/Omaccy Hyperkey.app"
xcrun stapler validate "extracted/Omaccy Hyperkey.app"
lipo -info "extracted/Omaccy Hyperkey.app/Contents/MacOS/omaccy-hyperkey"
codesign -dv --verbose=4 "extracted/Omaccy Hyperkey.app"
```

`spctl` reporting `source=Notarized Developer ID` confirms the stapled ticket is
readable without contacting Apple, which is what an offline first launch needs.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `Missing repository secrets: …` | The named secret is unset or empty. |
| `ambiguous (matches … and …)` | Signing by name with more than one certificate of that name in the keychain. Sign by hash. |
| `notarytool` authentication failure | `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, or `APPLE_TEAM_ID` disagree; the app-specific password belongs to whichever Apple ID created it. |
| Notarization `Invalid` | The dumped `notarytool log` names the offending binary and reason; a missing hardened runtime or timestamp is the usual cause. |
| `No usable Omaccy Hyperkey release found` during setup | No published release yet. Use `OMACCY_HYPERKEY_BUILD_LOCAL=1`. |
| Release runs but `install.sh` cannot parse it | The asset filename or the `.sha256` format changed; both are parsed by `install_hyperkey_app_from_release`. |
