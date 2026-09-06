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
is set. To test unreleased Swift changes end-to-end, run
`OMACCY_HYPERKEY_BUILD_LOCAL=1 bash scripts/install.sh`, which builds from the
current checkout, ad-hoc signs it, and resets Accessibility state only when the
built binary's hash changes — retain that distinction when modifying app
deployment. Tagging and pushing `v*` triggers `.github/workflows/release.yml`,
which builds, signs, notarizes, staples, and publishes the app as a GitHub
release asset alongside a `.sha256` checksum file; both the zip filename
pattern (`omaccy-hyperkey-*.zip[.sha256]`) and the checksum format (a bare
hex digest) are load-bearing for `scripts/lib/hyperkey.sh`'s parsing.
