##################################################
#                     Inputs
##################################################
# GITHUB_TOKEN: ${{ inputs.github_token }}
# PR_TOKEN: ${{ inputs.pr_token || inputs.github_token  }}
# SEMVER_CONFIG: ${{ inputs.semver_config }}
# CATEGORY_CONFIG: ${{ inputs.category_config }}

# GH_REPO: ${{ github.repository }}
# HEAD_SHA: ${{ github.sha }}

##################################################
#                    Variables
##################################################
FOUND_LABELS_ARRAY=""
REPO_API="https://api.github.com/repos/$GH_REPO"

##################################################
#                    Functions
##################################################
get_labels_between_shas() {
  git fetch --tags --force

  # Get HEAD_SHA
  if [ -z "$HEAD_SHA" ]; then
    # Set the sha of the latest commit
    HEAD_SHA=$(git rev-parse HEAD | cut -c 1-7)
  fi

  # Get BASE_SHA
  BASE_SHA=$(git tag --sort=-v:refname \
    | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1
  )
  if [ -z "$BASE_SHA" ]; then
    # Set the sha of the first commit
    BASE_SHA=$(git log --oneline | tail -n 1 | awk -F' ' '{print $1}')
  fi

  echo "HEAD_SHA: $HEAD_SHA"
  echo "BASE_SHA: $BASE_SHA"

  # Get commits between two SHAs
  commits=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "$REPO_API/compare/$BASE_SHA...$HEAD_SHA" \
    | jq -r '.commits[].sha' \
    | cut -c 1-7
  )

  # Array for storing PR numbers
  declare -A pr_numbers

  # Get PR numbers associated with the commits
  for commit in $commits; do
    pulls=$(curl -s -H "Authorization: token $PR_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      "$REPO_API/commits/$commit/pulls" \
      | jq -r '.[] | select(.merged_at != null) | .number'
    )

    for pr in $pulls; do
      echo "Found merged pull request: #$pr"
      pr_numbers[$pr]=1
    done
  done

  # Array for storing labels
  declare -A found_labels

  # Get all the labels set for the PRs
  for pr in "${!pr_numbers[@]}"; do
    echo "Fetching labels for Pull Request: #$pr"

    labels=$(curl -s -H "Authorization: token $PR_TOKEN" \
      "$REPO_API/pulls/$pr" \
      | jq -r '.labels[].name // empty'
    )

    for label in $labels; do
      label=$(echo "$label" | xargs) # Clean up the string
      [[ -n "$label" ]] && found_labels["$label"]=1
      echo "found a label: $label"
    done
  done

  # Set the labels to an array
  FOUND_LABELS_ARRAY=("${!found_labels[@]}")

  # Terminate this action if there is no label
  if [[ ${#FOUND_LABELS_ARRAY[@]} -eq 0 ]]; then
    echo "Warning: No label found."
  else
    echo "Found Labels:"
    for label in "${FOUND_LABELS_ARRAY[@]}"; do
      echo "- $label"
    done
  fi
}

search_commit_prefixes() {
  semver_type=""

  # Get commit messages between the previous tag and the HEAD
  commit_msgs=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "$REPO_API/compare/$BASE_SHA...$HEAD_SHA" \
    | jq -r '.commits[] | .commit.message'
  )

  # Get the number of categories from JSON input
  categories_count=$(echo "$CATEGORY_CONFIG" | jq '.categories | length')

  while IFS= read -r commit_msg; do
    [ -z "$commit_msg" ] && continue
    first_line=$(echo "$commit_msg" | head -n1)

    for ((i=0; i<categories_count; i++)); do
      prefixes=$(echo "$CATEGORY_CONFIG" | jq -r ".categories[$i].prefix[]")

      for prefix in $prefixes; do
        if [[ "$first_line" =~ ^${prefix}[\(\:] ]]; then
          semver_type="patch"
          break
        fi
      done
      [[ -n "$semver_type" ]] && break # Break if `semver_type` is already set
    done
    [[ -n "$semver_type" ]] && break # Break if `semver_type` is already set
  done <<< "$commit_msgs"

  [[ -z "$semver_type" ]] && semver_type="none"
  echo "$semver_type"
}

detect_version() {
  version=""
  types=("major" "minor" "patch")

  for type in "${types[@]}"; do
    labels=$(echo "$SEMVER_CONFIG" | jq -c -r --arg type "$type" \
      '.semver_types[] | select(.type == $type) | .label[]')

    for label in $labels; do
      label=$(echo "$label" | xargs) # clean up
      # Compare the JSON labels with the labels fetched from PRs
      for found_label in "${FOUND_LABELS_ARRAY[@]}"; do
        found_label=$(echo "$found_label" | xargs) # clean up
        if [[ "$label" == "$found_label" ]]; then
          version="$type"
          echo "Found match: $label -> version='$version'"
          break 3 # Exit the whole loops
        fi
      done
    done
    # Loop ends if `version` is already set
    [[ -n "$version" ]] && break
  done

  if [[ -z "$version" ]]; then
    version=$(search_commit_prefixes)
  fi

  echo "Detected version: $version"

  if [ "$version" == "none" ]; then
    echo "Warning: No semver type found. Update aborted."
    exit 0
  fi

  # Export the result
  echo "version=$version" >> $GITHUB_OUTPUT
}

get_labels_between_shas
detect_version
