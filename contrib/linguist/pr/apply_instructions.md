How to create the Linguist PR (commands you can run locally)

1) Fork `github/linguist` on GitHub and clone your fork locally:

```bash
git clone git@github.com:<your-username>/linguist.git
cd linguist
git remote add upstream https://github.com/github/linguist.git
git fetch upstream
git checkout -b add-krypton-language
```

2) Append the `Krypton` entry to `lib/linguist/languages.yml`.
   You can copy the `-- languages.yml snippet --` block from `contrib/linguist/pr/patch_snippets.md` in this repo and paste it at the end of `lib/linguist/languages.yml`.

3) Add the grammar mapping to `grammars.yml`.
   Copy the `-- grammars.yml snippet --` block and append it to `grammars.yml`. Update `repo:` and `path:` if you will point to `owner/krypton` and a repo-relative path.

4) Commit and push your branch:

```bash
git add lib/linguist/languages.yml grammars.yml
git commit -m "Add Krypton language and TextMate grammar mapping"
git push origin add-krypton-language
```

5) Open a PR against `github/linguist:main`. Use the `PR_BODY.md` in this repo as the PR description.

If you prefer, I can create the patch/diff file here instead of manual copy/paste — tell me and I'll prepare a ready `git apply` patch.
