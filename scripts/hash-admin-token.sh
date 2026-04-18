#!/bin/bash
set -e
python3 -m pip install --quiet 'argon2-cffi==23.1.0'
cat > /tmp/hash-admin-token.py << 'PYEOF'
{{PYTHON_SCRIPT}}
PYEOF
python3 /tmp/hash-admin-token.py
