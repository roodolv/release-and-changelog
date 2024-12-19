#!/bin/bash

# The action needs this label
gh label create release -d "Create release with this label" -c 00DD55

# If necessary, these labels should also be created.
# gh label create feature -d "New feature etc" -c A2EEEF \
# && gh label create hotfix -d "Small, urgent patches other than usual updates" -c FF5075 \
# && gh label create breaking-change -d "Something could break existing usage" -c 110000 \
# && gh label create skip-changelog -d "This will not be added to CHANGELOG" -c BFDADC
