##################################################
#                     Inputs
##################################################
# GITHUB_TOKEN: ${{ inputs.github_token }}
# PR_TOKEN: ${{ inputs.pr_token || inputs.github_token  }}
# DEFAULT_BRANCH: ${{ inputs.default_branch }}
# TAG_PREFIX="${{ inputs.tag_prefix }}"
# JSON_CONFIG="${{ inputs.json_config }}"

# GH_REPO="${{ github.repository }}"
# GH_SHA="${{ github.sha }}"
# SEMVER_LABEL="${{ steps.semver_label.outputs.semver_label }}"
# TZ="$TZ"

##################################################
#                    Variables
##################################################
CURRENT_VERSION=""
NEW_VERSION=""
PREV_TAG=""
PREV_FULL_SHA=""
RELEASE_NOTE_BODY=""

REPO_API="https://api.github.com/repos/$GH_REPO"
REPO_URL="https://github.com/$GH_REPO"

##################################################
#                    Functions
##################################################
validate_tag_prefix() {
  if [ "$TAG_PREFIX" != "v" ] && [ "$TAG_PREFIX" != "" ]; then
    echo "Error: TAG_PREFIX must be either an empty string or 'v'" >&2
    exit 1
  fi
}

get_current_version() {
  git fetch --tags --force
  PREV_TAG=$(git tag --sort=-v:refname | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1)
  version=${PREV_TAG#v}
  : ${version:=0.0.0}

  CURRENT_VERSION="$version"
}

calc_new_version() {
  major=$(echo $CURRENT_VERSION | cut -d. -f1)
  minor=$(echo $CURRENT_VERSION | cut -d. -f2)
  patch=$(echo $CURRENT_VERSION | cut -d. -f3)

  if [ "$SEMVER_LABEL" = 'major' ]; then
    NEW_VERSION="$((major + 1)).0.0"
  elif [ "$SEMVER_LABEL" = 'minor' ]; then
    NEW_VERSION="${major}.$((minor + 1)).0"
  elif [ "$SEMVER_LABEL" = 'patch' ]; then
    NEW_VERSION="${major}.${minor}.$((patch + 1))"
  else
    NEW_VERSION=$CURRENT_VERSION
  fi
}

# Update tag prefixes and the SHA
update_tag_and_sha() {
  NEW_VERSION="${TAG_PREFIX}${NEW_VERSION}"

  if [ "$CURRENT_VERSION" = "0.0.0" ]; then
    # Set the SHA of the initial commit to the previous tag
    PREV_FULL_SHA="$(git rev-list --max-parents=0 HEAD)"
    PREV_TAG="$(echo "$PREV_FULL_SHA" | cut -c 1-7)"
  else
    PREV_FULL_SHA=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
      "$REPO_API/git/refs/tags/$PREV_TAG" \
      | jq -r '.object.sha')
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

  # Check whether the prev tag exists and returns an empty string if not
  prev_tag_name=$(echo "$PREV_TAG" | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$')

  release_notes=$(curl -s -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token $GITHUB_TOKEN" \
    "$REPO_API/releases/generate-notes" \
    -d "{
      \"tag_name\": \"$NEW_VERSION\",
      \"previous_tag_name\": \"$prev_tag_name\",
      \"target_commitish\": \"$DEFAULT_BRANCH\"
    }" | jq -r ".body" | tr -d "\r")

  processed_notes=$(echo "$release_notes" | while IFS= read -r line; do
    process_line "$line"
  done)
  processed_notes=${processed_notes%\\n\\n\\n}

  echo "$processed_notes"
}

get_commits_between_tags() {
  # Get commit messages and SHAs between the previous tag and the current HEAD
  commits_and_sha=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "$REPO_API/compare/$PREV_FULL_SHA...$GH_SHA" \
    | jq -r '.commits[] | .commit.message, .sha')

  # Combine a commit message with a SHA
  results=$(echo "$commits_and_sha" | awk -v repo_url="$REPO_URL" '{
    if (NR % 2 == 1) {
      commit_message = $0
    } else {
      printf("%s ([%s](%s/commit/%s))\n", commit_message, substr($0, 1, 7), repo_url, substr($0, 1))
    }
  }')

  echo "$results"
}

categorize_other_changes() {
  commits=$(get_commits_between_tags)
  formatted_changes=""

  # Create arrays for classification and for order
  declare -A category_changes
  declare -a category_order

  # Processes each category in JSON
  categories_count=$(echo "$JSON_CONFIG" | jq '.categories | length')
  for ((i=0; i<categories_count; i++)); do
    title=$(echo "$JSON_CONFIG" | jq -r ".categories[$i].title")
    category_order+=("$title")
  done

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
    [ -z "$commit" ] && continue
    first_line=$(echo "$commit" | head -n1)

    for ((i=0; i<categories_count; i++)); do
      prefixes=$(echo "$JSON_CONFIG" | jq -r ".categories[$i].prefix[]")
      title=$(echo "$JSON_CONFIG" | jq -r ".categories[$i].title")

      for prefix in $prefixes; do
        if [[ "$first_line" =~ ^${prefix}[\(\:] ]]; then
          formatted_msg=$(get_scope_and_message "$first_line" "$prefix")
          category_changes["$title"]="${category_changes["$title"]:-}\\n- $formatted_msg"
          break
        fi
      done
    done
  done <<< "$commits"

  # Output categories in JSON order
  for title in "${category_order[@]}"; do
    if [[ -n "${category_changes["$title"]}" ]]; then
      formatted_changes="$formatted_changes\\n### $title${category_changes["$title"]}"
    fi
  done

  echo "$formatted_changes"
}

compose_release_note() {
  repo_url_esc="$(echo $REPO_URL | sed 's/\//\\\//g')"
  date_today=$(TZ="$TZ" date +'%Y-%m-%d')

  top_heading="## [$NEW_VERSION]($REPO_URL/compare/$PREV_TAG...$NEW_VERSION) ($date_today)"
  pr_changes=$(generate_pr_changes | sed 's/\(#\{3,6\}\) /\\n\1 /g')
  other_changes=$(categorize_other_changes | sed 's/\(#\{3,6\}\) /\\n\1 /g')
  RELEASE_NOTE_BODY="$(printf '%s%s%s' "$top_heading$pr_changes$other_changes" | awk ' \
    BEGIN {
      RS="EOF"
    }
    {
      gsub(/\\n\* /, "\\n- ")      # Unify bullet points
      gsub(/(\\n){3,}/, "\\n\\n")  # Normalize consecutive line breaks

      print
    }' \
    | sed 's/ by @[^ ]* in \(https[^\\ \*]*\)/ (\1)/g' \
    | sed "s/(#\([0-9]\+\))/($repo_url_esc\/pull\/\1)/g" \
    | sed "s/(\($repo_url_esc\/pull\)\/\([0-9]\+\))/([#\2](\1\/\2))/g" \
  )"
}

update_changelog() {
  changelog_body="$(echo -e $RELEASE_NOTE_BODY)"

  if [ ! -f CHANGELOG.md ]; then
    echo "# Changelog" > CHANGELOG.md
    echo "" >> CHANGELOG.md
  fi

  echo "# Changelog" > temp_changelog.md
  echo "" >> temp_changelog.md
  echo "$changelog_body" >> temp_changelog.md
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
  git commit -m "chore(release): $NEW_VERSION"
  git push
}

create_release() {
  response=$(curl -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -d "{ \
      \"tag_name\": \"$NEW_VERSION\", \
      \"target_commitish\": \"$DEFAULT_BRANCH\", \
      \"name\": \"$NEW_VERSION\", \
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
  validate_tag_prefix

  get_current_version
  calc_new_version
  update_tag_and_sha

  compose_release_note

  update_changelog
  create_release
}

main
