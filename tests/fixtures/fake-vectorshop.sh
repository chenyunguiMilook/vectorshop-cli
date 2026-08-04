#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  --help)
    printf 'vectorshop test fixture\n'
    ;;
  --mcp)
    while IFS= read -r line; do
      if [[ "$line" == *'"method":"initialize"'* ]]; then
        printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{}},"serverInfo":{"name":"vectorshop","version":"test"}}}'
      fi
    done
    ;;
  *)
    ;;
esac
