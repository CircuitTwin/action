#!/bin/sh
# Install a pinned `ct` CLI and put it on PATH.
#
# Environment:
#   CT_PATH                  Use this already-built ct instead of downloading one.
#   CT_URL                   https URL of a ct archive (.tar.gz holding `ct`) or of the binary.
#   CT_SHA256                SHA-256 (64 hex digits) the download must have. Required with CT_URL.
#   CT_VERSION               Version `ct --version` must report. Optional but recommended.
#   CT_COSIGN_PUBLIC_KEY     Release public key (PEM text). When set, the download is also verified with cosign.
#   CT_SIGNATURE_URL         Sigstore bundle of the download (default: CT_URL + .sigstore.json).
#   CT_ALLOW_INSECURE_HTTP   "true" permits an http URL (a mirror on a private network); the checksum still applies.
#   CT_INSTALL_DIR           Where ct is installed (default: a temporary directory).
#
# Exit codes: 0 installed, 2 invalid input or a failed check.
set -eu

fail() {
  printf 'circuittwin: %s\n' "$*" >&2
  exit 2
}

dir="${CT_INSTALL_DIR:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/circuittwin-ct}"
work="$dir/download"
mkdir -p "$work"

if [ -n "${CT_PATH:-}" ]; then
  [ -f "$CT_PATH" ] || fail "ct-path does not name a file"
  cp -- "$CT_PATH" "$dir/ct"
  if [ -n "${CT_SHA256:-}" ]; then
    printf '%s  %s\n' "$CT_SHA256" "$dir/ct" | sha256sum -c - >/dev/null 2>&1 \
      || fail "ct-path does not have the pinned SHA-256"
  fi
else
  [ -n "${CT_URL:-}" ] || fail "set ct-url (with ct-sha256) or ct-path"
  case "${CT_SHA256:-}" in
    *[!0-9a-f]* | '') fail "ct-sha256 must be the 64 lowercase hex digits of the download's SHA-256" ;;
  esac
  [ "${#CT_SHA256}" -eq 64 ] || fail "ct-sha256 must be 64 hex digits"
  proto='=https'
  if [ "${CT_ALLOW_INSECURE_HTTP:-false}" = "true" ]; then proto='=https,http'; fi
  fetch() {
    curl --fail --silent --show-error --location --proto "$proto" --proto-redir "$proto" \
      --connect-timeout 10 --max-time 300 --retry 2 -o "$2" "$1"
  }
  file="$work/download"
  fetch "$CT_URL" "$file" || fail "could not download ct from the given URL"
  printf '%s  %s\n' "$CT_SHA256" "$file" | sha256sum -c - >/dev/null 2>&1 \
    || fail "the download does not match ct-sha256; refusing to run it"
  if [ -n "${CT_COSIGN_PUBLIC_KEY:-}" ]; then
    # cosign 3.1.3, pinned by digest like the release chain (ADR-0042).
    cosign="$work/cosign"
    fetch https://github.com/sigstore/cosign/releases/download/v3.1.3/cosign-linux-amd64 "$cosign" \
      || fail "could not download cosign"
    printf '%s  %s\n' 4629c757b7618056f8ddd7e2625ae9fdd94c0372a65049520bc7d9df9efc7f71 "$cosign" \
      | sha256sum -c - >/dev/null 2>&1 || fail "the cosign download does not match its pinned digest"
    chmod 0755 "$cosign"
    printf '%s\n' "$CT_COSIGN_PUBLIC_KEY" >"$work/release.pub"
    fetch "${CT_SIGNATURE_URL:-$CT_URL.sigstore.json}" "$work/bundle.sigstore.json" \
      || fail "could not download the signature bundle"
    "$cosign" verify-blob --key "$work/release.pub" --bundle "$work/bundle.sigstore.json" "$file" >/dev/null 2>&1 \
      || fail "the cosign signature of the ct download is not valid for the given public key"
  fi
  if tar -tzf "$file" >/dev/null 2>&1; then
    # Only the file named ct is taken from the archive.
    mkdir -p "$work/extract"
    tar -xzf "$file" -C "$work/extract" --no-same-owner
    found=$(find "$work/extract" -type f -name ct | head -n 1)
    [ -n "$found" ] || fail "the archive holds no file named ct"
    cp -- "$found" "$dir/ct"
  else
    cp -- "$file" "$dir/ct"
  fi
fi

chmod 0755 "$dir/ct"
rm -rf "$work"
reported=$("$dir/ct" --version 2>/dev/null) || fail "the installed ct does not run on this machine"
if [ -n "${CT_VERSION:-}" ]; then
  case "$reported" in
    *"$CT_VERSION"*) ;;
    *) fail "ct reports '$reported', not the pinned version $CT_VERSION" ;;
  esac
fi
printf 'circuittwin: installed %s\n' "$reported"
PATH="$dir:$PATH"
export PATH
if [ -n "${GITHUB_PATH:-}" ]; then printf '%s\n' "$dir" >>"$GITHUB_PATH"; fi
