#!/bin/bash
set -euo pipefail

# Compiles the Bicep template into an ARM JSON template.

mkdir -p docs/arm
az bicep build --file bicep/main.bicep --outfile docs/arm/main.json
echo "ARM template compiled successfully"
