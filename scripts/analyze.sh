#!/usr/bin/env bash
# Strict type check of src/ with luau-lsp, using a Rojo sourcemap so
# requires like ReplicatedStorage.Shared.Config.PowerConfig resolve.
set -euo pipefail
cd "$(dirname "$0")/.."

DEFS=".tools/globalTypes.d.luau"
if [ ! -f "$DEFS" ]; then
	mkdir -p .tools
	curl -fsSL --retry 3 -o "$DEFS" \
		https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi

rojo sourcemap default.project.json --output sourcemap.json

# Fails (exit 1) if luau-lsp reports any diagnostic.
luau-lsp analyze \
	--platform=roblox \
	--sourcemap=sourcemap.json \
	--definitions=@roblox="$DEFS" \
	--base-luaurc=.luaurc \
	src
