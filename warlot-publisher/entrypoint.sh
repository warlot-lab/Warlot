#!/usr/bin/env bash
set -euo pipefail

abort() {
  echo "🛑 Caught SIGTERM/SIGINT—shutting down."
  kill -TERM "$child" 2>/dev/null || true
  wait "$child"
  exit
}
trap 'abort' TERM INT

echo "🔨 Starting Warlot Publisher entrypoint…"

# Import key
if [[ -n "${SUI_KEY_PATH:-}" && -f "$SUI_KEY_PATH" ]]; then
  echo "🔑 Importing Sui key from file at \$SUI_KEY_PATH"
  sui keytool import --name default --path "$SUI_KEY_PATH"
elif [[ -n "${USER_MNEMONIC:-}" ]]; then
  echo "🔑 Importing Sui key from mnemonic (hidden)"
  sui keytool import "$USER_MNEMONIC" ed25519
  unset SUI_MNEMONIC
else
  echo "⚠️  No SUI_KEY_PATH or SUI_MNEMONIC—skipping key import."
fi

# Bootstrap Sui config if missing
if [[ ! -f "$HOME/.sui/sui_config/client.yaml" ]]; then
  echo "📡 Bootstrapping Sui client configuration..."

  printf "y\n\n0\n" | sui client
fi


# Switch address
if [[ -n "${SUI_ADDRESS:-}" ]]; then
  echo "📌 Switching to address \$SUI_ADDRESS"
  sui client switch --address "$SUI_ADDRESS"
else
  echo "ℹ️  No SUI_ADDRESS—using default address"
fi

# Show envs
echo "🔍 Sui client environments:"
sui client envs


#  show active address
echo "⚙️ active address"
sui client active-address


# ──────────────────────────────────────────────────────────────────────────────
# Bootstrap Walrus config if missing
# ──────────────────────────────────────────────────────────────────────────────
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
if [[ ! -f "$XDG_CONFIG_HOME/walrus/client_config.yaml" ]]; then
  echo "📦 Bootstrapping Walrus config at $XDG_CONFIG_HOME/walrus/client_config.yaml"
  mkdir -p "$XDG_CONFIG_HOME/walrus"
  curl -fsSL \
    https://docs.wal.app/setup/client_config.yaml \
    -o "$XDG_CONFIG_HOME/walrus/client_config.yaml"
fi



walrus list-blobs --context testnet




: "${PORT:=8080}"
: "${TLS_CERT:=/home/appuser/server.crt}"
: "${TLS_KEY:=/home/appuser/server.key}"

echo "🚀 Launching Warlot Publisher on port $PORT"
if [[ -f "$TLS_CERT" && -f "$TLS_KEY" ]]; then
  echo "🔐 TLS enabled → cert=$TLS_CERT key=$TLS_KEY"
  CMD=(/usr/local/bin/warlot-publisher --http "$PORT" --tls-cert "$TLS_CERT" --tls-key "$TLS_KEY")
else
  echo "🌐 TLS cert or key not found, starting HTTP only"
  CMD=(/usr/local/bin/warlot-publisher --http "$PORT")
fi

# Start the server and wait
"${CMD[@]}" &
PID=$!
wait "$PID"
