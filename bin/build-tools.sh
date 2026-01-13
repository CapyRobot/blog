#!/bin/bash
# Build and copy tool submodules to source/tools/

set -e

BLOG_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Build BehaviorNet Editor (using PN editor config for this site)
echo "Building BehaviorNet Editor..."
cd "$BLOG_ROOT/behaviornet-viz"
npm install
VITE_TOOL_CONFIG=tool_config_PN_editor.json npm run build -- --base=/tools/behaviornet-viz/

# Copy to source/tools/
mkdir -p "$BLOG_ROOT/source/tools/behaviornet-viz"
cp -r dist/* "$BLOG_ROOT/source/tools/behaviornet-viz/"

echo "Tools built successfully!"
