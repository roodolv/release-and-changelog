# Release and Changelog

GitHub Actions for Automated Versioning

## Features
- Automatically generates release notes and updates `CHANGELOG.md` if a merged PR has a `semver-XX` label.
- Creates version tags following [Semantic Versioning](https://semver.org).
- Detects commit messages with specified prefixes and includes them in the release notes and `CHANGELOG.md`.
- Retrieves scopes from PRs and commits.
    - Supports the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) format.

## Inputs
- `github_token` (**Required**): Token used to access the GitHub API.
- `pr_token` (**Optional**): Set a **Read-only** token for pull requests here if you are using this action with a private repository.
- `default_branch` (**Optional**): Set the default branch name here if it's not `main`.
    - default value: `"main"`

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

      - uses: roodolv/release-and-changelog@main
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

## Todo
- [ ] Allow commit message prefixes and release note headings to be customized in JSON fields
