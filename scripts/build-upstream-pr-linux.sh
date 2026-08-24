#!/usr/bin/env bash
# Usage: SCREENSCRAPER_DEV_ID=... SCREENSCRAPER_DEV_PASSWORD=... \
#   ./scripts/build-upstream-pr-linux.sh <pr-number>
set -euo pipefail

pr_number="${1:?Usage: $0 <upstream-pr-number>}"
: "${SCREENSCRAPER_DEV_ID:?Set SCREENSCRAPER_DEV_ID before running this script}"
: "${SCREENSCRAPER_DEV_PASSWORD:?Set SCREENSCRAPER_DEV_PASSWORD before running this script}"

if [[ "$SCREENSCRAPER_DEV_ID$SCREENSCRAPER_DEV_PASSWORD" == *$'\n'* ||
      "$SCREENSCRAPER_DEV_ID$SCREENSCRAPER_DEV_PASSWORD" == *$'\r'* ]]; then
  echo 'ScreenScraper values must not contain line breaks.' >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64) builder=build-utils/build-linux.sh ;;
  aarch64) builder=build-utils/build-linuxarm.sh ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

git fetch https://github.com/misobadev/neostation-frontend.git \
  "pull/$pr_number/head:refs/remotes/neostation/pr/$pr_number"
git switch --detach "neostation/pr/$pr_number"

umask 077
env_file="$(mktemp)"
trap 'rm -f "$env_file"' EXIT
printf 'SCREENSCRAPER_DEV_ID=%s\nSCREENSCRAPER_DEV_PASSWORD=%s\n' \
  "$SCREENSCRAPER_DEV_ID" "$SCREENSCRAPER_DEV_PASSWORD" > "$env_file"

ENV_FILE="$env_file" bash "$builder"
