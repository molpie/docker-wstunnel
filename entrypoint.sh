#!/bin/sh
set -e

# --- Pre-flight check ---
ABORT=0
for keytype in rsa ecdsa ed25519; do
    keyfile="/etc/ssh/ssh_host_${keytype}_key"
    if [ ! -f "$keyfile" ] || [ ! -s "$keyfile" ]; then
        echo "ERROR: Missing or empty host key: $keyfile"
        echo "ERROR: Run setup.sh on the host before docker compose up."
        ABORT=1
    fi
done
[ "$ABORT" -eq 1 ] && exit 1
# --- Fine pre-flight ---

echo "INFO: Starting sshd on port 2222..."
/usr/sbin/sshd -E /dev/stderr -o PidFile=/run/sshd/sshd.pid

echo "INFO: Starting wstunnel..."
exec wstunnel "$@"
