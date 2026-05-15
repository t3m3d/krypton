#!/usr/bin/env bash
set -euo pipefail

# Creates a fork of github/linguist, applies the prepared patch, pushes a branch,
# and opens a PR. Requires the `gh` CLI and git configured for your account.

GH_USER="t3m3d"
UPSTREAM_REPO="github/linguist"
FORK_REPO="$GH_USER/linguist"
BRANCH="add-krypton-language"
PATCH_SRC="/Users/t3m3d/Documents/GitHub/krypton/contrib/linguist/pr/linguist_add_krypton.patch"
PR_BODY_FILE="/Users/t3m3d/Documents/GitHub/krypton/contrib/linguist/pr/PR_BODY.md"

command -v gh >/dev/null 2>&1 || { echo "gh CLI is required. Install from https://cli.github.com/"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git is required."; exit 1; }

echo "This script will fork ${UPSTREAM_REPO} into ${FORK_REPO}, apply the patch, and open a PR. Continue? [y/N]"
read -r CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborted by user."
  exit 1
fi

# Fork (if not already forked) and clone
if gh repo view "$FORK_REPO" >/dev/null 2>&1; then
  echo "Fork already exists on GitHub." 
else
  echo "Creating fork..."
  gh repo fork "$UPSTREAM_REPO" --remote=false --org "$GH_USER" || true
fi

CLONE_DIR="${HOME}/work/linguist-${GH_USER}"
rm -rf "$CLONE_DIR"
echo "Cloning fork to $CLONE_DIR"
gh repo clone "$FORK_REPO" "$CLONE_DIR"
cd "$CLONE_DIR"

git remote add upstream "https://github.com/${UPSTREAM_REPO}.git" || true
git fetch upstream
git checkout -b "$BRANCH" || git checkout --track -b "$BRANCH" origin/HEAD

echo "Copying patch into clone and applying..."
cp "$PATCH_SRC" ./linguist_add_krypton.patch
if ! git apply linguist_add_krypton.patch; then
  echo "git apply failed. Inspect linguist_add_krypton.patch and resolve conflicts manually." >&2
  exit 1
fi

git add lib/linguist/languages.yml grammars.yml || true
git commit -m "Add Krypton language and TextMate grammar mapping" || echo "No changes to commit"

echo "Pushing branch to origin..."
git push -u origin "$BRANCH"

echo "Creating PR on GitHub..."
gh pr create --base main --head "${GH_USER}:${BRANCH}" --title "Add Krypton language" --body-file "$PR_BODY_FILE"

echo "Done. Visit: https://github.com/${UPSTREAM_REPO}/pulls to see the PR." 
