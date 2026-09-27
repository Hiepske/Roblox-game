#!/usr/bin/env bash
# Downloads the Linux x86_64 builds of the tools pinned in rokit.toml into a
# folder (default: .tools/bin). Used by CI; on your own machine prefer
# `rokit install`, which reads the same rokit.toml.
set -euo pipefail

DEST="${1:-.tools/bin}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

version_of() {
	# rojo = "rojo-rbx/rojo@7.7.0" -> 7.7.0
	grep -E "^$1 *=" "$ROOT/rokit.toml" | sed -E 's/.*@([^"]+)".*/\1/'
}

fetch() {
	local name="$1" url="$2"
	echo "Downloading $name: $url"
	curl -fsSL --retry 3 -o "$TMP/$name.zip" "$url"
	unzip -o -q "$TMP/$name.zip" -d "$DEST"
}

ROJO="$(version_of rojo)"
LUNE="$(version_of lune)"
SELENE="$(version_of selene)"
STYLUA="$(version_of stylua)"
LUAU_LSP="$(version_of luau-lsp)"

fetch rojo "https://github.com/rojo-rbx/rojo/releases/download/v$ROJO/rojo-$ROJO-linux-x86_64.zip"
fetch lune "https://github.com/lune-org/lune/releases/download/v$LUNE/lune-$LUNE-linux-x86_64.zip"
fetch selene "https://github.com/Kampfkarren/selene/releases/download/$SELENE/selene-$SELENE-linux.zip"
fetch stylua "https://github.com/JohnnyMorganz/StyLua/releases/download/v$STYLUA/stylua-linux-x86_64.zip"
fetch luau-lsp "https://github.com/JohnnyMorganz/luau-lsp/releases/download/$LUAU_LSP/luau-lsp-linux-x86_64.zip"

chmod +x "$DEST"/*
echo "Installed to $DEST"
