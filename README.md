# Release and Changelog

GitHub Actions for Automated Versioning

## Features
- Automatically generates release notes and updates `CHANGELOG.md` if a merged PR has a `semver-XX` label.
- Generates the body of the release notes based on merged PRs and commits between the current SHA (e.g., `${{ github.sha }}`) and the previous tag's SHA.
- Calculates and creates a new version tag following [Semantic Versioning](https://semver.org).
- Detects commit messages with the specified `prefix` and includes them in sections defined by `title` in the release notes and CHANGELOG.md.
  - The `prefix` and `title` can be customized using a JSON field.
- Retrieves scopes from PRs and commits.
    - Supports the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) format.

## Usage
> **NOTE**: This action should be used with [automatically generated release notes](https://docs.github.com/en/repositories/releasing-projects-on-github/automatically-generated-release-notes). It needs `.github/release.yml` on your repository.


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
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: roodolv/release-and-changelog@v1.1
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

Add this to execute the action only when a merged PR contains `semver-XX` labels:
```yaml
  release-and-changelog:
    # Triggered only when PRs are merged and labeled with `semver-XX`
    if: |
      github.event.pull_request.merged == true &&
      (contains(github.event.pull_request.labels.*.name, 'semver-major') ||
       contains(github.event.pull_request.labels.*.name, 'semver-minor') ||
       contains(github.event.pull_request.labels.*.name, 'semver-patch'))
    runs-on: ubuntu-latest
    ...
```

## Inputs
- `github_token`: Token used to access the GitHub API.
- `pr_token`: Set a **Read-only** token for pull requests here if you are using this action with a private repository.
- `default_branch`: Set the default branch name here if it's not `main`.
- `json_config`: Set the **JSON field** to include prefixes for commit messages and headings for release notes. (available in `v1.1.0`+)

| name | required | default |
| :-- | :-- | :-- |
|  `github_token`   | true  | - |
|  `pr_token`       | false | - |
|  `default_branch` | false | `"main"` |
|  `json_config`    | false | `'{"categories":[{"prefix":["revert"],"title":"Reverts"},{"prefix":["refactor"],"title":"Refactoring"},{"prefix":["perf"],"title":"Performance"}]}'` |

### About `json_config`
> **NOTE**: This feature is available from version `v1.1.0` onward.

You can specify `prefix` for commit messages and `title` for release notes freely, with `json_config` variable.

For example:
```yaml
      - uses: roodolv/release-and-changelog@v1.1
        env:
          TZ: "Asia/Tokyo"
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          json_config: |
            {
              "categories": [
                {
                  "prefix": ["refactor"],
                  "title": "Refactoring"
                },
                {
                  "prefix": ["perform"],
                  "title": "Performance"
                },
                {
                  "prefix": ["docs", "documentation"],
                  "title": "Docs"
                }
              ]
            }
```

## Todo
- [x] Allow commit message prefixes and release note headings to be customized in JSON fields
