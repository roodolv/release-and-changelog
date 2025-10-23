#!/bin/bash

# NOTE:
# Execute this script only on the local environment.
# Even if you execute this on remote repos, you can't fetch Git tags with `git pull` or `git pull --tags`.

##################################################
#                     Inputs
##################################################
DEFAULT_BRANCH="main"

##################################################
#                    Variables
##################################################
ABBREV_MAJOR_TAG=""
ABBREV_MINOR_TAG=""

##################################################
#                    Functions
##################################################
setup_repo() {
  if ! git checkout $DEFAULT_BRANCH; then
    echo "Failed to checkout the default branch"
    exit 1
  fi

  # Fetch tags from remote
  git fetch --tags --force
}

get_current_version() {
  # Fetch only a semver style tag
  LATEST_TAG=$(git tag --sort=-v:refname | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1)
  VERSION=${LATEST_TAG#v}
  : ${VERSION:=0.0.0}

  if [ "$VERSION" = "0.0.0" ]; then
    echo "Error: Couldn't find any SemVer tag" >&2
    exit 1
  else
    echo "$LATEST_TAG"
  fi
}

calc_abbrev_tags() {
  LATEST_TAG="$(get_current_version)"

  MAJOR=$(echo $LATEST_TAG | cut -d. -f1)
  MINOR=$(echo $LATEST_TAG | cut -d. -f2)

  ABBREV_MAJOR_TAG="${MAJOR}"
  ABBREV_MINOR_TAG="${MAJOR}.${MINOR}"
}

set_abbrev_tags() {
  # Delete existing tags
  git tag -d "$ABBREV_MAJOR_TAG" "$ABBREV_MINOR_TAG" \
    && echo "Deleted old abbrev tags(local)"
  git push origin :refs/tags/$ABBREV_MAJOR_TAG :refs/tags/$ABBREV_MINOR_TAG \
    && echo "Deleted old abbrev tags(remote)"

  # Re-create tags
  git tag "$ABBREV_MAJOR_TAG" && git tag "$ABBREV_MINOR_TAG" \
    && echo "Created new abbrev tags"
  git push --tags \
    && echo "Pushed new abbrev tags"
}

echo "Process starts"
setup_repo
get_current_version
calc_abbrev_tags
set_abbrev_tags
echo "Process ends"
