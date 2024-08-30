#!/bin/bash --login
# The --login ensures the bash configuration is loaded,
# enabling Conda.

# Enable strict mode.
#set -euo pipefail
# ... Run whatever commands ...


# exec the final command:
python3 "$@"
