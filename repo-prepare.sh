#!/bin/bash
# repo-prepare.sh
# Runs the repo's prepare.sh with a TEMPORARY pacman config that includes the
# EndeavourOS repo, so your system's /etc/pacman.conf is never modified.
#
# Usage:
#   ./repo-prepare.sh            # run prepare.sh only
#   ./repo-prepare.sh --build    # run prepare.sh, then: sudo ./mkarchiso -v .

set -euo pipefail

CONF=/tmp/eos-pacman.conf
MIRRORLIST=/etc/pacman.d/endeavouros-mirrorlist
MIRRORLIST_URL=https://raw.githubusercontent.com/endeavouros-team/PKGBUILDS/master/endeavouros-mirrorlist/endeavouros-mirrorlist
KEYSERVER=keyserver.ubuntu.com
KEYS=(
  497AF50C92AD2384C56E1ACA003DB8B0CB23504F
  0F20FADC599D1C46EB556455AED8858E4B9813F1
)
PATCHED=.prepare.patched.sh

cd "$(dirname "$(readlink -f "$0")")"

[[ -f prepare.sh ]] || { echo "ERROR: prepare.sh not found in $(pwd)"; exit 1; }

cleanup() { rm -f "$CONF" "$PATCHED"; }
trap cleanup EXIT

# 1. EndeavourOS mirrorlist (only downloaded if missing)
if [[ ! -s $MIRRORLIST ]]; then
  echo "==> Downloading EndeavourOS mirrorlist"
  tmp=$(mktemp)
  wget -qO "$tmp" "$MIRRORLIST_URL"
  sudo install -m644 "$tmp" "$MIRRORLIST"
  rm -f "$tmp"
fi

if ! grep -q '^Server' "$MIRRORLIST"; then
  echo "ERROR: $MIRRORLIST has no active 'Server =' lines. Uncomment a few and rerun."
  exit 1
fi

# 2. Signing keys (only imported if missing)
for key in "${KEYS[@]}"; do
  if ! sudo pacman-key --list-keys "$key" &>/dev/null; then
    echo "==> Importing key $key"
    sudo pacman-key --recv-key "$key" --keyserver "$KEYSERVER"
    sudo pacman-key --lsign-key "$key"
  fi
done

# 3. Temporary pacman.conf = your normal one + [endeavouros]
cp /etc/pacman.conf "$CONF"
if ! grep -q '^\[endeavouros\]' "$CONF"; then
  cat >> "$CONF" <<EOF

[endeavouros]
SigLevel = PackageRequired
Include = $MIRRORLIST
EOF
fi

# 4. Patched COPY of prepare.sh: every `pacman <args>` call gets --config.
#    (pacman-key, pacman.conf, pacman.d etc. are not touched.)
sed -E "s#(^|[[:space:];&|(]|/usr/bin/)pacman([[:space:]])#\1pacman --config $CONF\2#g" \
  prepare.sh > "$PATCHED"

# 4b. The liveuser skel package needs a PKGBUILD. Try to restore it from git
#     history; if that fails, skip building it so the rest of the build works.
SKEL=airootfs/root/lineos-skel-liveuser
if [[ ! -f $SKEL/PKGBUILD ]]; then
  echo "==> $SKEL/PKGBUILD is missing"
  restored=0
  c=$(git log --all -1 --format=%H -- "$SKEL/PKGBUILD" 2>/dev/null || true)
  if [[ -n $c ]]; then
    if git cat-file -e "$c:$SKEL/PKGBUILD" 2>/dev/null; then
      git checkout "$c" -- "$SKEL" && restored=1
    else
      git checkout "$c^" -- "$SKEL" && restored=1
    fi
  fi
  if [[ $restored -eq 1 && -f $SKEL/PKGBUILD ]]; then
    echo "==> Restored $SKEL from git history (commit ${c:0:7})"
  else
    echo "WARNING: no PKGBUILD in git history either. Skipping the skel build."
    echo "         The ISO will build, but without the lineos-skel-liveuser package."
    sed -i -e '\#^cd "airootfs/root/lineos-skel-liveuser"#d' -e '/^makepkg -f/d' "$PATCHED"
  fi
fi

count=$(grep -c -- "--config $CONF" "$PATCHED" || true)
if [[ $count -eq 0 ]]; then
  echo "WARNING: no pacman calls found in prepare.sh to patch."
  echo "         It may call pacman indirectly; check: grep -n pacman prepare.sh"
else
  echo "==> Patched $count pacman call(s) in a temporary copy of prepare.sh"
fi

# 5. Run it
echo "==> Running prepare.sh with EndeavourOS repo enabled"
bash "$PATCHED"

# 6. Optional build
if [[ ${1:-} == "--build" ]]; then
  echo "==> Building ISO"
  sudo ./mkarchiso -v .
fi

echo "==> Done"
