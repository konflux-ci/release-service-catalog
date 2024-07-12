#!/bin/bash

mkdir -p /tmp/mock-bin

cat << 'EOF' > /tmp/mock-bin/push-cgw-metadata
#!/bin/bash
echo "push-cgw-metadata mock called with: $@" >&2
EOF

chmod +x /tmp/mock-bin/push-cgw-metadata
export PATH=/tmp/mock-bin:$PATH
