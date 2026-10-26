#!/usr/bin/env bash
set -euo pipefail

package="${PACKAGE_NAME:?PACKAGE_NAME is required}"
scope="${PACKAGE_SCOPE:?PACKAGE_SCOPE is required}"
output="${PACKAGE_OUTPUT:?PACKAGE_OUTPUT is required}"
release="${RELEASE:?RELEASE is required}"
arch="${ARCH:?ARCH is required}"
target="${TARGET:?TARGET is required}"
subtarget="${SUBTARGET:?SUBTARGET is required}"
channel="${CHANNEL:?CHANNEL is required}"
repository="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
source_commit="${SOURCE_COMMIT:-${GITHUB_SHA:?GITHUB_SHA is required}}"

[[ -d "$output/packages" ]] || { echo "ERROR: missing packages directory for $package" >&2; exit 1; }
compgen -G "$output/packages/*.apk" >/dev/null || { echo "ERROR: no APKs found for $package" >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
short_sha="${source_commit:0:12}"
safe_target="${target}-${subtarget}"
tag="packages-${channel}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}-${package}-${release}-${arch}-${safe_target}-${short_sha}"

python3 "$repo_root/scripts/create-repository-update.py" \
  --packages-dir "$output/packages" \
  --context "$output/context.json" \
  --scope "$scope" \
  --channel "$channel" \
  --release-tag "$tag" \
  --repository "$repository" \
  --source-commit "$source_commit" \
  --output "$output/repository-update.json"

args=(release create "$tag" "$output"/packages/*.apk "$output/repository-update.json"
  --repo "$repository"
  --target "$source_commit"
  --title "$tag"
  --notes "AudioWRT ${package} for OpenWrt ${release} / ${arch} / ${target}/${subtarget}")
if [[ "$channel" == testing ]]; then
  args+=(--prerelease)
fi

gh "${args[@]}"
echo "Published $package for OpenWrt $release / $arch / $target/$subtarget"
