#!/bin/bash
# Installation script for zig-model-gen

set -e

echo "🚀 Installing Zig Model Generator..."

# Build the generator
echo "📦 Building..."
zig build -Doptimize=ReleaseFast

# Determine install location
if [ -n "$PREFIX" ]; then
    INSTALL_DIR="$PREFIX/bin"
elif [ -w "/usr/local/bin" ]; then
    INSTALL_DIR="/usr/local/bin"
elif [ -w "$HOME/.local/bin" ]; then
    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"
else
    echo "❌ Error: No writable installation directory found"
    echo "   Try: sudo $0"
    echo "   Or:  PREFIX=$HOME/.local $0"
    exit 1
fi

# Copy binary
echo "📥 Installing to $INSTALL_DIR..."
cp zig-out/bin/zig-model-gen "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/zig-model-gen"

echo "✅ Installation complete!"
echo ""
echo "Usage: zig-model-gen <schemas_dir> [output_dir]"
echo "Example: zig-model-gen schemas src/models"
echo ""
echo "Run 'zig-model-gen --help' for more information"

