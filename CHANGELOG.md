# Changelog

All notable changes to this project will be documented in this file.

## [2.2.0] – 2025-06-27

### Added
- Full RPC rotation engine in `rpc-rotate.sh`  
  • Round-robin cycling through all `node:` entries in `provider.yaml` (skipping lines prefixed `##`).  
  • Automatic insertion of a “Managed by Paladin” header and skip-marker comments.  
  • Daily backup of `provider.yaml` to `provider.yaml.YYYY-MM-DD`.  
  • Public RPC fallback URLs injected immediately after your last node entry.  
- `--local` flag to `rpc-rotate.sh`  
  • Health-checks `http://localhost:26657/status` for `"catching_up": false`.  
  • Stamps a timestamp when first healthy, then waits a continuous 3-hour window before reverting the active `node:` back to your local RPC.  
- Example cron snippet for invoking `./rpc-rotate.sh --local` once daily (e.g. ~ 03:00 local).


### Fixed
- Script now fails early—before any mutation—if `provider.yaml` is missing or malformed.  
- Health-stamp file resets on probe failures to avoid stale revert windows.  

---

## [2.0]

- Added Cluster support by moving script to a pod

## [1.0]

- Basic script run by a cronjob on a controlplane.
