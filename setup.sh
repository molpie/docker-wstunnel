#!/bin/sh
set -e

# ---------------------------------------------------------------------------
# setup.sh — Prepare host-side config files for wstunnel bastion container
# ---------------------------------------------------------------------------
# Run this script once before the first `docker compose up`.
# It creates:
#   config/ssh_host_keys/   — sshd host keys (owned by root, mounted read-only)
#   config/                 — placeholder reminder for authorized_keys
# ---------------------------------------------------------------------------

CONFIG_DIR="./config"
HOST_KEYS_DIR="$CONFIG_DIR/ssh_host_keys"
AUTH_KEYS="$CONFIG_DIR/authorized_keys"

# --- Host keys ---

echo "INFO: Creating host keys directory: $HOST_KEYS_DIR"
mkdir -p "$HOST_KEYS_DIR"

for keytype in rsa ecdsa ed25519; do
    keyfile="$HOST_KEYS_DIR/ssh_host_${keytype}_key"
    if [ -f "$keyfile" ]; then
        echo "INFO: Host key already exists, skipping: $keyfile"
    else
        echo "INFO: Generating host key: $keytype"
        ssh-keygen -t "$keytype" -f "$keyfile" -N "" -q
    fi
done

echo "INFO: Setting ownership (root:root) and permissions on host keys..."
chown 0:0 "$HOST_KEYS_DIR"/ssh_host_*_key
chown 0:0 "$HOST_KEYS_DIR"/ssh_host_*_key.pub
chmod 600 "$HOST_KEYS_DIR"/ssh_host_*_key
chmod 644 "$HOST_KEYS_DIR"/ssh_host_*_key.pub

echo "INFO: Host keys ready."
echo ""

# --- authorized_keys ---

if [ ! -f "$AUTH_KEYS" ]; then
    echo "------------------------------------------------------------------------"
    echo "ACTION REQUIRED: authorized_keys not found."
    echo ""
    echo "Copy your SSH public key to:"
    echo "  $AUTH_KEYS"
    echo ""
    echo "Example:"
    echo "  cp ~/.ssh/id_rsa.pub $AUTH_KEYS"
    echo "  # or paste your public key manually into $AUTH_KEYS"
    echo ""
    echo "Then set correct ownership and permissions:"
    echo "  chown 1000:1000 $AUTH_KEYS"
    echo "  chmod 600 $AUTH_KEYS"
    echo "------------------------------------------------------------------------"
else
    echo "INFO: authorized_keys found: $AUTH_KEYS"
    echo "INFO: Ensuring correct ownership (1000:1000) and permissions (600)..."
    chown 1000:1000 "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
    echo "INFO: authorized_keys ready."
fi

echo ""
echo "Setup complete. You can now run: docker compose up -d"
