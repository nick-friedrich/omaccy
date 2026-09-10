# Working on Omaccy

Omaccy combines a native Hyperkey app with AeroSpace, SketchyBar, and Ghostty.
Read [.ai/architecture.md](.ai/architecture.md) for the repository map and
[.ai/development.md](.ai/development.md) for setup lifecycle rules and checks.
[.ai/releasing.md](.ai/releasing.md) covers the signed release pipeline.
[CHANGELOG.md](CHANGELOG.md) is the user-facing record of what shipped.
`plan.md` contains historical decisions and future ideas; it is not a guarantee
that a feature or distribution method is implemented.

## Change conventions

- Keep `scripts/install.sh`, `update.sh`, and `uninstall.sh` as readable entry
  points. Put reusable setup behavior in `scripts/lib/`, grouped by responsibility.
- Library files should define functions or paths without changing the system
  when sourced. Keep user confirmation before any setup mutations.
- Pair changes to installed configs, dependencies, and macOS preferences with
  the corresponding uninstall behavior. Preserve original values across updates.
- Preserve customized configs and distinguish pre-existing dependencies from
  dependencies installed by Omaccy.
- Target the macOS system Bash (3.2); avoid features requiring newer Bash.
- Run the relevant checks in `.ai/development.md`. For script refactors, use
  isolated checks rather than running a real install or uninstall as a test.
- Update `.ai` documentation when module boundaries or lifecycle behavior change.
- Add a `CHANGELOG.md` entry in the same change that makes the behavior
  change, under the top unreleased version heading and the Keep a Changelog
  section it belongs to (Added, Changed, Fixed, Removed). Write it for
  someone running Omaccy, not for a reviewer: name what they will notice and
  what they have to do about it, and say when state on disk is discarded or
  its format changes. Reconstructing the entry at release time loses the
  reason a change was made, so do not defer it. Internal refactors with no
  observable effect need no entry.
