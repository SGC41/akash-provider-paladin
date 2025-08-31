# Changelog

Most notable changes to this project, should be documented in this file.
## 2.7.1	changed ticker from 20min to 15min
		rewritten akash-provider-online-check.sh .... should most likely also rename it.

## 2.7.0 -	moved clear-stuck-pods run to control-plane
		clear_stuck_pods.sh renamed to clear-stuck-pods.sh

		added custom exclusions to clear-stuck-pods.sh and set it to exclude hardware discovery pods (shouldn't matter, i think)
		added graceful delete attempt to clear-stuck-pods.sh		
		
		
## 2.6.3 - 	fixed installer's cronjob injection, so that its a date variable
		the previous version would make a cronjob with the install date. lol

		Fixed ticker-control-plane.sh so it should log which scripts get loaded for executing from control-plane.do file.

## 2.6.2 -	Critical bug fix, solved looping withdrawal attempts for closed leases.

## 2.4.1 - critical bug fix to cold wallet feature.

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
