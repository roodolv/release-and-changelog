#!/bin/bash

# The action needs these labels
gh label create semver-major -d "Update MAJOR version with this PR" -c 70090F \
&& gh label create semver-minor -d "Update MINOR version with this PR" -c 00DD55 \
&& gh label create semver-patch -d "Update PATCH version with this PR" -c 0000FF

# If necessary, these labels should also be created.
# gh label create feature -d "New feature etc" -c A2EEEF \
# && gh label create hotfix -d "Small, urgent patches other than usual updates" -c FF5075 \
# && gh label create breaking-change -d "Something could break existing usage" -c 110000 \
# && gh label create skip-changelog -d "This will not be added to CHANGELOG" -c BFDADC
