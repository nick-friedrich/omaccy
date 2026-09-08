# Development and validation

## Shell lifecycle changes

Run from the repository root:

```sh
for script in scripts/*.sh scripts/lib/*.sh tests/*.sh; do
  bash -n "$script" || exit
done
bash tests/scripts-smoke.sh
git diff --check
```

Assert with `[[ ... ]] || fail "what broke"`, never a bare `[[ ... ]]`: the
macOS system bash (3.2) does not apply `set -e` to a failing conditional, and
its ERR trap does not fire for one either, so a bare check silently passes no
matter what the code does. When adding a check, confirm it actually fails by
breaking the behavior it covers and rerunning.

The smoke checks use temporary directories for config state and only exercise
cancellation in the real entry points. They do not install dependencies, restart
services, or modify macOS preferences. AeroSpace stop/start recovery is checked
with a mocked CLI, including a disabled server and restricted IPC.
Full install/uninstall testing changes the
desktop and should be a deliberate manual integration check.

Keep these invariants when editing setup logic:

1. No directories, packages, settings, or services change before confirmation.
2. Update asks once and uses the same installation sequence.
3. Original setting backups are saved once, not overwritten by repeated installs.
4. Customized canonical configs survive an update; pristine defaults can refresh.
5. Uninstall only restores targets still managed by Omaccy and asks separately
   about removing dependencies that Omaccy installed.
6. Source paths work independently of the caller's working directory.
7. Keep mutations in ordinary function calls after confirmation. Do not put an
   entire installation function in an `if` condition, which alters Bash errexit
   behavior inside the function.

For structural refactors, preserve operation ordering and avoid mixing unrelated
behavior changes into moved functions. Keep application and restoration logic in
the same responsibility module so reviewers can inspect them together.

## Hyperkey app changes

```sh
swift test --package-path apps/hyperkey
swift build -c release --package-path apps/hyperkey
```

See `apps/hyperkey/README.md` for the palette preview and keyboard details.
Script-only changes do not require rebuilding the Swift app.

`install.sh` fetches the latest Developer ID-signed, notarized release by
default; it never rebuilds the Swift app unless `OMACCY_HYPERKEY_BUILD_LOCAL=1`
is set. To build and install the current checkout instead:

```sh
OMACCY_HYPERKEY_BUILD_LOCAL=1 bash scripts/install.sh
```

That build is signed with a Developer ID Application identity when the keychain
holds one, and ad-hoc signed otherwise. Signing locally with Developer ID is
worth the setup because the designated requirement is the bundle identifier plus
the team rather than the binary's hash, so a single Accessibility grant covers
every rebuild and the released app as well; ad-hoc builds take a new code
identity whenever the executable changes and have to be granted again.
Installation records which mode was used in `~/.omaccy/hyperkey-signing-mode`
and resets Accessibility state only when that mode changes, or when an ad-hoc
binary changes. Retain that distinction when modifying app deployment.

The first local Developer ID signature on a machine raises a keychain
authorization dialog asking whether `codesign` may use the private key, and
setup blocks until it is answered — choosing "Always Allow" adds `codesign` to
the key's ACL so later builds are silent, whereas "Allow" authorizes only that
one signature. It can also be granted ahead of time:

```sh
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "$(read -rs -p 'login password: ' p; echo "$p")" ~/Library/Keychains/login.keychain-db
```

`OMACCY_SIGNING_IDENTITY` overrides the choice: a certificate hash or name pins
one, and `-` forces ad-hoc signing. Detection reads
`security find-identity -v -p codesigning` and selects by hash, because a
keychain can hold several certificates sharing one Developer ID name, which
`codesign` rejects as ambiguous rather than resolving. Local signing passes
`--timestamp=none` so rebuilds stay fast and work offline; a trusted timestamp
matters for distribution, which the release workflow handles.

Tagging and pushing `v*` triggers `.github/workflows/release.yml`. The asset
filename pattern (`omaccy-hyperkey-*.zip[.sha256]`) and the checksum format (a
bare hex digest) are load-bearing for `scripts/lib/hyperkey.sh`'s parsing. See
[releasing.md](releasing.md) for the pipeline, its repository secrets,
certificate rotation, and troubleshooting.
