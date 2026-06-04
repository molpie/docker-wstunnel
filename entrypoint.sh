#!/bin/sh
set -e

for keytype in rsa ecdsa ed25519; do
    keyfile="/etc/ssh/ssh_host_${keytype}_key"
    if [ ! -f "$keyfile" ]; then
        echo "INFO: Generating host key: $keytype"
        ssh-keygen -t "$keytype" -f "$keyfile" -N "" -q
    else
        echo "INFO: Using existing host key: $keytype"
    fi
done

echo "INFO: Starting sshd on port 2222..."
/usr/sbin/sshd -E /dev/stderr

echo "INFO: Starting wstunnel..."
exec wstunnel "$@"
