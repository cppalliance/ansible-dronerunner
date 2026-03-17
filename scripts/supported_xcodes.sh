#!/bin/bash

# Function to compare versions (returns true if $1 >= $2)
version_ge() {
  [ "$1" = "$(echo -e "$1\n$2" | sort -V | tail -n1)" ]
}

# Get current macOS version (e.g., "15.6")
CURRENT_OS=$(sw_vers -productVersion)

# Check architecture (arm64 for Apple Silicon, x86_64 for Intel)
ARCH=$(uname -m)

# Fetch JSON data
DATA=$(curl -s https://xcodereleases.com/data.json)

# Extract stable Xcode versions, requires, and arch info (if present)
# Output format: "version requires is_arm_only" (is_arm_only=1 if arm64-only, else 0)
EXTRACTED=$(echo "$DATA" | jq -r '.[] | select(.version.release.release == true) | 
  .version.number + " " + .requires + " " + (if (.links.download.architectures // []) == ["arm64"] then "1" else "0" end)')

# Build list of supported versions
supported_versions=()
while IFS=' ' read -r version requires is_arm_only; do
  if version_ge "$CURRENT_OS" "$requires"; then
    if [ "$ARCH" = "x86_64" ] && [ "$is_arm_only" = "1" ]; then
      # Skip arm64-only on Intel
      continue
    fi
    supported_versions+=("$version")
  fi
done <<< "$EXTRACTED"

# Space-separated string
xcodeversions="${supported_versions[*]}"

# Example usage: Print the list
echo "Supported stable Xcode versions: $xcodeversions"

# Example: Install them all (assumes xcodes is installed and authenticated)
for v in "${supported_versions[@]}"; do
  xcodes install "$v"
done
