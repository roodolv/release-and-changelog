##################################################
#                     Inputs
##################################################
# GITHUB_TOKEN: ${{ inputs.github_token }}
# PR_TOKEN: ${{ inputs.pr_token || inputs.github_token  }}
# DEFAULT_BRANCH: ${{ inputs.default_branch }}
# GH_REPO="${{ github.repository }}"
# GH_SHA="${{ github.sha }}"
# SEMVER_LABEL="${{ steps.semver_label.outputs.semver_label }}"
# TZ="$TZ"

##################################################
#                    Variables
##################################################
CURRENT_VERSION=""
NEW_VERSION=""
RELEASE_NOTE_BODY=""

REPO_API="https://api.github.com/repos/$GH_REPO"
REPO_URL="https://github.com/$GH_REPO"

##################################################
#                    Functions
##################################################
get_current_version() {
  git fetch --tags --force
  VERSION=$(git describe --tags --abbrev=0 2>/dev/null)
  VERSION=${VERSION#v}
  : ${VERSION:=0.0.0}

  CURRENT_VERSION="$VERSION"
}

calc_new_version() {
  MAJOR=$(echo $CURRENT_VERSION | cut -d. -f1)
  MINOR=$(echo $CURRENT_VERSION | cut -d. -f2)
  PATCH=$(echo $CURRENT_VERSION | cut -d. -f3)

  if [ "$SEMVER_LABEL" = 'major' ] ; then
    NEW_VERSION="$((MAJOR + 1)).0.0"
  elif [ "$SEMVER_LABEL" = 'minor' ] ; then
    NEW_VERSION="${MAJOR}.$((MINOR + 1)).0"
  elif [ "$SEMVER_LABEL" = 'patch' ] ; then
    NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"
  else
    NEW_VERSION=$CURRENT_VERSION
  fi
}

# This step requires `.github/release.yml`
generate_pr_changes() {
  extract_scope() {
    local message="$1"
    if [[ "$message" =~ ^[^\(\):]+\(([^\)]+)\): ]]; then
      echo "${BASH_REMATCH[1]}"
      return 0
    fi
    return 1
  }

  get_pr_number() {
    local line="$1"
    if [[ "$line" =~ /pull/([0-9]+) ]]; then
      echo "${BASH_REMATCH[1]}"
      return 0
    fi
    return 1
  }

  get_pr_last_commit() {
    local pr_number="$1"
    curl -s -H "Authorization: token $PR_TOKEN" \
      "$REPO_API/pulls/${pr_number}/commits" \
      | jq 'last.commit.message'
  }

  process_heading() {
    local line="$1"
    local hash_count=$(echo "$line" | grep -o '^#\+' | wc -c)

    if [ "$hash_count" -gt 3 ]; then
      echo -n "\\n${line}\\n"
    else
      echo -n "${line}\\n"
    fi
  }

  process_pr_line() {
    local line="$1"
    local content
    local pr_number

    pr_number=$(get_pr_number "$line")

    if [[ "$line" =~ ^\*[[:space:]]+(.+)[[:space:]]https:// ]]; then
      content="${BASH_REMATCH[1]}"
    else
      echo -n "${line}\\n"
      return
    fi

    local scope
    scope=$(extract_scope "$content")

    if [[ -z "$scope" ]] && [[ -n "$pr_number" ]]; then
      local commit_message
      commit_message=$(get_pr_last_commit "$pr_number")
      scope=$(extract_scope "$commit_message")
    fi

    if [[ -n "$scope" ]]; then
      local body
      if [[ "$content" =~ ^[^\(\):]+\([^\)]+\):[[:space:]](.+)$ ]]; then
        body="${BASH_REMATCH[1]}"
      else
        body="$content"
      fi
      echo -n "* **${scope}**: ${body} $REPO_URL/pull/${pr_number}\\n"
    else
      echo -n "${line}\\n"
    fi
  }

  process_line() {
    local line="$1"

    if [[ -z "$line" ]]; then
      echo -n "\\n"
      return
    fi

    if [[ "$line" =~ ^###+ ]]; then
      process_heading "$line"
      return
    fi

    if [[ "$line" =~ https://github\.com/[^/]+/[^/]+/pull/[0-9]+ ]]; then
      process_pr_line "$line"
      return
    fi
  }

  RELEASE_NOTES=$(curl -s -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token $GITHUB_TOKEN" \
    "$REPO_API/releases/generate-notes" \
    -d "{
      \"tag_name\": \"v$NEW_VERSION\",
      \"previous_tag_name\": \"v$CURRENT_VERSION\",
      \"target_commitish\": \"$DEFAULT_BRANCH\"
    }" | jq -r ".body" | tr -d "\r")

  PROCESSED_NOTES=$(echo "$RELEASE_NOTES" | while IFS= read -r line; do
    process_line "$line"
  done)
  PROCESSED_NOTES=${PROCESSED_NOTES%\\n\\n\\n}

  echo "$PROCESSED_NOTES"
}

get_commits_between_tags() {
  # Get the previous tag's commit SHA
  PREV_TAG_SHA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "$REPO_API/git/refs/tags/v$CURRENT_VERSION" \
    | jq -r '.object.sha')

  # Get commit messages and SHAs between the previous tag and the current HEAD
  COMMITS_AND_SHA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "$REPO_API/compare/$PREV_TAG_SHA...$GH_SHA" \
    | jq -r '.commits[] | .commit.message, .sha')

  # Combine a commit message with a SHA
  RESULTS=$(echo "$COMMITS_AND_SHA" | awk -v repo_url="$REPO_URL" '{
    if (NR % 2 == 1) {
      commit_message = $0
    } else {
      printf("%s ([%s](%s/commit/%s))\n", commit_message, substr($0, 1, 7), repo_url, substr($0, 1))
    }
  }')

  echo "$RESULTS"
}

categorize_other_changes() {
  COMMITS=$(get_commits_between_tags)
  REVERTS=""
  PERFS=""
  REFACTOR=""

  # Function to extract scope and message
  get_scope_and_message() {
    local msg="$1"
    local type="$2"

    case "$msg" in
      ${type}\(*\):*)
        local scope=$(echo "$msg" | cut -d'(' -f2 | cut -d')' -f1)
        local message=$(echo "$msg" | cut -d':' -f2- | sed 's/^ *//')
        echo "**$scope**: $message"
        ;;
      ${type}:*)
        local message=$(echo "$msg" | cut -d':' -f2- | sed 's/^ *//')
        echo "$message"
        ;;
    esac
  }

  while IFS= read -r commit; do
    # Skip empty lines
    [ -z "$commit" ] && continue

    # Extract the first line of commit message
    FIRST_LINE=$(echo "$commit" | head -n1)

    # Categorize based on prefix and preserve scope
    if [[ "$FIRST_LINE" =~ ^revert[\(\:] ]]; then
      FORMATTED_MSG=$(get_scope_and_message "$FIRST_LINE" "revert")
      REVERTS="$REVERTS\\n- $FORMATTED_MSG"
    elif [[ "$FIRST_LINE" =~ ^perf[\(\:] ]]; then
      FORMATTED_MSG=$(get_scope_and_message "$FIRST_LINE" "perf")
      PERFS="$PERFS\\n- $FORMATTED_MSG"
    elif [[ "$FIRST_LINE" =~ ^refactor[\(\:] ]]; then
      FORMATTED_MSG=$(get_scope_and_message "$FIRST_LINE" "refactor")
      REFACTOR="$REFACTOR\\n- $FORMATTED_MSG"
    fi
  done <<< "$COMMITS"

  FORMATTED_CHANGES=""

  if [ ! -z "$REVERTS" ]; then
    FORMATTED_CHANGES="$FORMATTED_CHANGES\\n### Reverts$REVERTS"
  fi
  if [ ! -z "$PERFS" ]; then
    FORMATTED_CHANGES="$FORMATTED_CHANGES\\n### Performance$PERFS"
  fi
  if [ ! -z "$REFACTOR" ]; then
    FORMATTED_CHANGES="$FORMATTED_CHANGES\\n### Refactor$REFACTOR"
  fi

  echo "$FORMATTED_CHANGES"
}

compose_release_note() {
  REPO_URL_ESC="$(echo $REPO_URL | sed 's/\//\\\//g')"
  DATE_TODAY=$(TZ="$TZ" date +'%Y-%m-%d')

  TOP_HEADING="## [v$NEW_VERSION]($REPO_URL/compare/v$CURRENT_VERSION...v$NEW_VERSION) ($DATE_TODAY)\\n"
  PR_CHANGES=$(generate_pr_changes)
  OTHER_CHANGES=$(categorize_other_changes | sed 's/\(#\{3,6\}\) /\\n\1 /g')

  RELEASE_NOTE_BODY="$(printf '%s%s%s' "$TOP_HEADING$PR_CHANGES$OTHER_CHANGES" | awk ' \
    BEGIN {
      RS="EOF"
    }
    {
      gsub(/\\n\* /, "\\n- ")           # Unify bullet points
      gsub(/(\\n){3,}/, "\\n\\n")       # Normalize consecutive line breaks

      print
    }' \
    | sed 's/ by @[^ ]* in \(https[^\\ \*]*\)/ (\1)/g' \
    | sed "s/(#\([0-9]\+\))/($REPO_URL_ESC\/pull\/\1)/g" \
    | sed "s/(\($REPO_URL_ESC\/pull\)\/\([0-9]\+\))/([#\2](\1\/\2))/g" \
  )"
}

update_changelog() {
  CHANGELOG_BODY="$(echo -e $RELEASE_NOTE_BODY)"

  if [ ! -f CHANGELOG.md ]; then
    echo "# Changelog" > CHANGELOG.md
    echo "" >> CHANGELOG.md
  fi

  echo "# Changelog" > temp_changelog.md
  echo "" >> temp_changelog.md
  echo "$CHANGELOG_BODY" >> temp_changelog.md
  echo "" >> temp_changelog.md

  if [ -f CHANGELOG.md ]; then
    tail -n +3 CHANGELOG.md >> temp_changelog.md
  fi
  mv -f temp_changelog.md CHANGELOG.md

  git config --local user.email "github-actions[bot]@users.noreply.github.com"
  git config --local user.name "github-actions[bot]"

  if ! git checkout $DEFAULT_BRANCH; then
    echo "Failed to checkout default branch"
    exit 1
  fi
  git add CHANGELOG.md
  git commit -m "chore(release): v$NEW_VERSION"
  git push
}

create_release() {
  response=$(curl -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -d "{ \
      \"tag_name\": \"v$NEW_VERSION\", \
      \"target_commitish\": \"$DEFAULT_BRANCH\", \
      \"name\": \"v$NEW_VERSION\", \
      \"body\": \"$RELEASE_NOTE_BODY\" \
    }" \
    -w "%{http_code}" \
    -o response_body.txt \
    $REPO_API/releases)
  status_code=$(echo "$response" | tail -n1)
  echo "Status Code: $status_code"
  body=$(cat response_body.txt)
  echo "Response Body: $body"
  if [ $status_code -ne 201 ]; then
    echo "Failed to create release"
    exit 1
  fi
}

main() {
  get_current_version
  calc_new_version

  compose_release_note

  update_changelog
  create_release
}

main
