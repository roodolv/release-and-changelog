# Release and Changelog

Automated Versioning for [GitHub flow](https://docs.github.com/en/get-started/using-github/github-flow)

## Features
- Automatically generates <u>releases</u> and updates <u>CHANGELOG.md</u>.
- Automatically calculates and creates <u>a new version tag</u> following [Semantic Versioning](https://semver.org).
  - Abbreviated, prerelease, and other special kind of tags (e.g. `v1`, `v0.2`, `v3.4.5pre`, `v1.2.3-alpha`, `v0.1.2-beta.1`, and `release-0.1.0` etc) are **all ignored**.
- Automatically detects <u>a version type</u> of SemVer (e.g. `major`, `minor`, `patch`, and `none`) with the user-specified JSON fields.
- Generates the release notes with [automatically generated release notes](https://docs.github.com/en/repositories/releasing-projects-on-github/automatically-generated-release-notes) and **detected commits**.
  - Detects commit messages with the user-specified `prefix` and includes them in sections of `title` in the release notes and CHANGELOG.md.
  - The `prefix` and `title` can be customized using a JSON field.
- Retrieves **scopes** from PRs and commits.
    - Supports the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) format.

> **NOTE**: This action uses the previous tag and the SHA of HEAD when checking the PRs and commit logs. If there is no previous version tag, it uses the SHA of the first commit instead.

## Usage
> **NOTE**: This action should be used with [automatically generated release notes](https://docs.github.com/en/repositories/releasing-projects-on-github/automatically-generated-release-notes). It needs `.github/release.yml` on your repository.

Please add `if:` condition as below if you want to call the action only when a merged PR contains a `release` label.

If your repository is **public**:
```yaml
name: "Generate release and changelog"

on:
  pull_request:
    types: [closed]
    branches:
      - main

jobs:
  release-and-changelog:
    # Triggered only when a PR is merged and labeled with `release`
    if: |
      github.event.pull_request.merged == true &&
      (contains(github.event.pull_request.labels.*.name, 'release'))
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: roodolv/release-and-changelog@v1
        env:
          TZ: "Asia/Tokyo"
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

If your repository is **private**, please add `pr_token`:
```yaml
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          pr_token: ${{ secrets.PR_TOKEN }}
```

> **HINT**: You can create the necessary labels using `setup_labels.sh`.

## Inputs
- `github_token`: Token used to access the GitHub API.
- `pr_token`: Set a **Read-only** token for pull requests here if you are using this action on a private repository.
- `tag_prefix`: Set the prefix of the version tag. If empty (`''`), the tag like `1.2.3` will be detected and created.
- `semver_config`: Set the **JSON field** to include <u>semantic versioning types</u> and <u>labels for PRs</u>.
- `category_config`: Set the **JSON field** to include <u>prefixes</u> for commit messages and <u>titles of headings</u> in release notes.

> **NOTE**: `tag_prefix` can only be set to either `"v"` or `""`(empty string).

| name | required | default |
| :-- | :-- | :-- |
|  `github_token`   | true  | - |
|  `pr_token`       | false | - |
|  `tag_prefix`     | false | `"v"` |
|  `semver_config`    | false | `'{"semver_types":[{"type":"major","label":["breaking-change"]},{"type":"minor","label":["feature","enhancement"]},{"type":"patch","label":["improvement","bug","hotfix"]}]}'` |
|  `category_config`    | false | `'{"categories":[{"prefix":["revert"],"title":"Reverts"},{"prefix":["refactor"],"title":"Refactoring"},{"prefix":["perf"],"title":"Performance"}]}'` |

### About JSON configs

Here is the example of JSON settings. You can freely customize them.

When you setup YAML like this,
```yaml
      - uses: roodolv/release-and-changelog@v1
        env:
          TZ: "Asia/Tokyo"
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          category_config: |
            {
              "categories": [
                {
                  "prefix": ["refactor"],
                  "title": "Refactoring"
                },
                {
                  "prefix": ["docs", "document"],
                  "title": "Docs"
                }
              ]
            }
```

and if your Git log is like this,
```bash
$ git log --pretty=oneline --abbrev-commit

abcdef0 document(readme): bar bar bar
0123456 refactor(src): foo foo foo (#3)
ccccccc (tag: v0.1.0) chore(release): v0.1.0
bbbbbbb feat(other): fugafuga (#2)
aaaaaaa fix(src): hogehoge (#1)
0000000 (tag: v0.0.1) chore(release): v0.0.1
```

this action outputs the following release notes:
```md
## [v0.1.1](https://github.com/USER/REPO/compare/v0.1.0...v0.1.1) (2024-12-22)

### Refactoring
- **src**: foo foo foo ([#3](https://github.com/USER/REPO/pull/3)) ([0123456](https://github.com/USER/REPO/commit/012345678900000000000000000000000000000))

### Docs
- **readme**: bar bar bar ([abcdef0](https://github.com/USER/REPO/commit/abcdef000000000000000000000000000000000))
```

## Examples

<details>
  <summary>Case1: Only merged PRs</summary>

Git log:
```bash
$ git log --pretty=oneline --abbrev-commit

cba7d60 (tag: v0.2.0) chore(release): v0.2.0
1ba902b change on config.lua (#2)
2203652 fix(src): added config.lua (#1)
209d402 (tag: v0.1.0) chore(src): added a.lua
```

PR details:
```bash
$ gh pr view 2

change on config.lua roodolv/git-test#2
Merged • roodolv wants to merge 2 commits into main from feat/config01 • about 10 hours ago
+40 -36 • ✓ Checks passing
Labels: feature, semver-minor

  • feat(src): added aiueo to config.lua
  • revert(src): reverted config.lua
```

Release notes body:
```md
## [v0.2.0](https://github.com/roodolv/git-test/compare/v0.1.0...v0.2.0) (2024-11-27)

### Features
- **src**: change on config.lua ([#2](https://github.com/roodolv/git-test/pull/2))

### Hot Fixes
- **src**: added config.lua ([#1](https://github.com/roodolv/git-test/pull/1))
```
</details>

<details>
  <summary>Case2: Only specified commits</summary>

Git log:
```bash
$ git log --pretty=oneline --abbrev-commit

49e89f8 (tag: v0.3.2) chore(release): v0.3.2
32383af revert(src): playback on init.lua (#7)
1b1810d (tag: v0.3.1) chore(release): v0.3.1
```

PR details:

> **NOTE**: This PR didn't have labels like `bug` or `enhancement`, so the PR itself wouldn't be included in automatically generated release notes. However, the PR included the commit that has a user-specified prefix (`revert`), so the commit would be included in releases notes.

```bash
$ gh pr view 7

init.lua came back roodolv/git-test#7
Merged • roodolv wants to merge 1 commit into main from chore/testtstststs • about 9 hours ago
+0 -2 • ✓ Checks passing
Labels: semver-patch

  No description provided
```

Release notes body:
```md
## [v0.3.2](https://github.com/roodolv/git-test/compare/v0.3.1...v0.3.2) (2024-11-27)

### Reverts
- **src**: playback on init.lua ([#7](https://github.com/roodolv/git-test/pull/7)) ([32383af](https://github.com/roodolv/git-test/commit/32383af4b1c52f19b86a62f5cded57585aef4ddd))
```
</details>

<details>
  <summary>Case3: Merged PRs and specified commits 1</summary>

Git log:
```bash
$ git log --pretty=oneline --abbrev-commit

cccab17 (tag: v0.3.0) chore(release): v0.3.0
de269cf feat(src): added init.lua (#4)
fcc08fd chore on config.lua (#3)
75d5c33 docs(other): tweaked CHANGELOG
cba7d60 (tag: v0.2.0) chore(release): v0.2.0
```

PR details:

> **NOTE**: These internal commits of `#3` were squashed and merged. These were all **skipped** because the PR title didn't have a scope, the PR wasn't labeled, and the PR branch didn't have a specific name (such as `feat/` or `fix/`).

> **NOTE**: If you want to include them in the release, either include the scope in the PR title before the merge, label the PR before the merge, or do merge without squashing.
```bash
$ gh pr view 3

chore on config.lua roodolv/git-test#3
Merged • roodolv wants to merge 2 commits into main from chore/testtest • about 10 hours ago
+36 -40 • ✓ Checks passing

  • style(src): added commeent okay
  • revert(src): reverted comment on config.lua
```

```bash
$ gh pr view 4

added init.lua roodolv/git-test#4
Merged • roodolv wants to merge 1 commit into main from feat/init-lua • about 10 hours ago
+487 -0 • ✓ Checks passing
Labels: feature, semver-minor

  No description provided
```

Release notes body:
```md
## [v0.3.0](https://github.com/roodolv/git-test/compare/v0.2.0...v0.3.0) (2024-11-27)

### Features
- **src**: added init.lua ([#4](https://github.com/roodolv/git-test/pull/4))

### Docs
- **other**: tweaked CHANGELOG ([75d5c33](https://github.com/roodolv/git-test/commit/75d5c3304b2538775e3670cdb884650e097b799e))
```
</details>

<details>
  <summary>Case4: Merged PRs and specified commits 2</summary>

> **NOTE**: This is suitable when you don't want to include the PR itself in the release, but want to include only the commit.

Git log:
```bash
$ git log --graph --pretty=oneline --abbrev-commit

* 1b1810d (tag: v0.3.1) chore(release): v0.3.1
*   d4c2908 Merge pull request #6 from roodolv/chore/aaaa
|\
| * 37498bf revert(src): reverted init.lua
|/
* 3aaab8a refactor(src): added comment oh-no (#5)
* cccab17 (tag: v0.3.0) chore(release): v0.3.0
```

PR details:
```bash
$ gh pr view 5

added oh-no comment roodolv/git-test#5
Merged • roodolv wants to merge 1 commit into main from fix/testsssss • about 9 hours ago
+414 -292 • ✓ Checks passing
Labels: bug

  No description provided
```

> **NOTE**: This `#6` has branch name `chore/` and is not labeled with other than `semver-XX`, but the prefix of the commit (`revert`) is detected **because it is not squashed at PR merge**.
```bash
$ gh pr view 6

fixed init.lua roodolv/git-test#6
Merged • roodolv wants to merge 1 commit into main from chore/aaaa • about 9 hours ago
+292 -412 • ✓ Checks passing
Labels: semver-patch

  No description provided
```

Release notes body:
```md
## [v0.3.1](https://github.com/roodolv/git-test/compare/v0.3.0...v0.3.1) (2024-11-27)

### Bug Fixes
- **src**: added oh-no comment ([#5](https://github.com/roodolv/git-test/pull/5))

### Reverts
- **src**: reverted init.lua ([37498bf](https://github.com/roodolv/git-test/commit/37498bf62120a1d3eb710ac92c3cfd2112187085))

### Refactor
- **src**: added comment oh-no ([#5](https://github.com/roodolv/git-test/pull/5)) ([3aaab8a](https://github.com/roodolv/git-test/commit/3aaab8a1d6450c6ad18c3d15fff493cf6db15f1f))
```
</details>

