#!/usr/bin/env bash

show_help() {
  echo "Options:"
  echo ""
  echo "--leases                [displays current leases, earnings ...]"
  echo "--node <nodename>       [pods on a node]"
  echo ""
}

# If no arguments are passed, show help
if [ $# -eq 0 ]; then
  show_help
  exit 0
fi

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --leases)
      ~/akash-provider-paladin/scripts/check-unpaid-leases.sh
      shift
      ;;
    --node)
      if [ -n "$2" ]; then
        NODE_NAME="$2"
        kubectl get pods --all-namespaces --field-selector spec.nodeName="$NODE_NAME" -o wide
        shift 2
      else
        echo "Error: --node requires a nodename argument"
        show_help
        exit 1
      fi
      ;;
    *)
      echo "Unrecognized option: $1"
      show_help
      exit 1
      ;;
  esac
done
