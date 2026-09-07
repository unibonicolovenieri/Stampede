#!/usr/bin/env bash
# Compila EagleFoot in modalità release e lo rende richiamabile da qualunque cartella.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

if ! xcode-select -p >/dev/null 2>&1; then
    echo "Servono le Command Line Tools di Xcode. Lancia: xcode-select --install" >&2
    exit 1
fi

echo "Compilo (la prima volta scarica swift-argument-parser)…"
swift build -c release

BINARY="$ROOT/.build/release/eaglefoot"
[ -x "$BINARY" ] || { echo "Compilazione fallita: binario non trovato." >&2; exit 1; }

# Preferiamo ~/.local/bin: non richiede sudo e sopravvive agli aggiornamenti di sistema.
TARGET_DIR="$HOME/.local/bin"
mkdir -p "$TARGET_DIR"
ln -sf "$BINARY" "$TARGET_DIR/eaglefoot"

echo
echo "Installato: $TARGET_DIR/eaglefoot -> $BINARY"

case ":$PATH:" in
    *":$TARGET_DIR:"*)
        echo "Pronto. Prova:  eaglefoot doctor"
        ;;
    *)
        SHELL_RC="$HOME/.zshrc"
        echo
        echo "$TARGET_DIR non è nel PATH. Aggiungilo con:"
        echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> $SHELL_RC && source $SHELL_RC"
        echo
        echo "Nel frattempo puoi usare il percorso completo:  $TARGET_DIR/eaglefoot doctor"
        ;;
esac

echo
echo "Il link punta alla build nel repo: dopo un 'git pull' basta 'swift build -c release'."
echo
echo "Per l'app con interfaccia grafica:  ./scripts/build-app.sh"
