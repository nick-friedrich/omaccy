#!/usr/bin/env bash

# Fast-forwarding the checkout that setup runs from. This is a best-effort step
# in front of the installation sequence, never a gate on it: an unreachable
# remote, a modified checkout, or local commits are reported and skipped, and
# setup still runs from the revision already present. Only a fast-forward is
# performed, so local work is never rewritten or merged away.

checkout_git() {
  git -C "$REPO_ROOT" "$@"
}

# Empty when the checkout can be fast-forwarded, otherwise the reason it cannot.
# Read-only: it inspects local state and never contacts the remote.
checkout_pull_blocker() {
  if ! command -v git >/dev/null 2>&1; then
    echo "git is not installed"
  elif ! checkout_git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "$REPO_ROOT is not a Git checkout"
  elif ! checkout_git symbolic-ref -q HEAD >/dev/null 2>&1; then
    echo "the checkout has a detached HEAD"
  elif ! checkout_git rev-parse -q --verify '@{upstream}' >/dev/null 2>&1; then
    echo "the current branch tracks no remote branch"
  elif ! checkout_git diff --quiet HEAD >/dev/null 2>&1; then
    echo "the checkout has uncommitted changes"
  fi
}

# Reports why the code update was skipped and that setup proceeds regardless,
# so a skipped pull never reads as a failed update.
skip_checkout_pull() {
  echo "Skipping the code update: $1."
  echo "Setup continues from the revision already in $REPO_ROOT."
}

update_checkout() {
  local blocker before after
  blocker="$(checkout_pull_blocker)"
  if [[ -n "$blocker" ]]; then
    skip_checkout_pull "$blocker"
    return 0
  fi

  echo "Fetching newer Omaccy code..."
  if ! checkout_git fetch --quiet; then
    skip_checkout_pull "the remote could not be reached"
    return 0
  fi

  before="$(checkout_git rev-parse HEAD)"
  if ! checkout_git merge --ff-only --quiet '@{upstream}' >/dev/null 2>&1; then
    skip_checkout_pull "this branch has commits the remote does not, so it cannot be fast-forwarded"
    echo "Reconcile it with git yourself, then run the update again."
    return 0
  fi
  after="$(checkout_git rev-parse HEAD)"

  if [[ "$before" == "$after" ]]; then
    echo "Already on the latest Omaccy code."
  else
    echo "Updated the checkout to $(checkout_git rev-parse --short "$after") ($(checkout_git rev-list --count "$before..$after") new commits)."
  fi
}
