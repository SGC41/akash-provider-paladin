---

## 📦 Akash RPC Rotation Tool: `rpc-rotate.sh`

This script automates the selection and activation of a healthy Akash RPC node by scanning and toggling entries in `provider.yaml`. It’s designed for Kubernetes deployments and works seamlessly with Helm and etcd.

---

### 🧠 Purpose

- ✅ Prefer a healthy local RPC node each day
- 🔁 Rotate among fallback nodes when needed
- 🧪 Probe node health based on Tendermint sync status
- 📄 Preserve provider config formatting
- 🪛 Sync updates via Helm and etcd

---

### 🗂️ Files + Dependencies

| Path                                  | Role                         |
|--------------------------------------|------------------------------|
| `provider.yaml`                      | Lists all available RPCs     |
| `price_script_generic.sh`           | Sourced and synced post-rotation |
| `update-provider-configuration.sh`  | Helm redeployment script     |
| `.last_rpc_rotate`                  | Timestamp of last rotation   |
| `rpc-rotate.sh`                     | Main rotation logic          |

---

### 🚥 How It Works

1. **Startup**
   - Pull latest configs from etcd
   - Annotate `provider.yaml` with structured headers (on first run)

2. **Daily Logic**
   - If it's the first run of the day:
     - Prefers local RPC (`localhost` or `akash-node-1`) if healthy
   - Else:
     - Scans available nodes in circular order

3. **Health Checking**
   - Calls `/status` endpoint
   - Requires:
     - `catching_up: false`
     - Chain age > `MIN_HOURS` (default 3)

4. **Config Switching**
   - Comments previously active node (`#node:`)
   - Uncomments selected healthy node (`node:`)

5. **Cluster Sync**
   - Runs `update-provider-configuration.sh`
   - Pushes updated files back to etcd

---

### 🔍 Health Check Details

Performed via:

```bash
curl --max-time 5 http://<ip>:26657/status
```

Parsed for:

- `catching_up == false`
- `earliest_block_time` → must be older than `MIN_HOURS`

---

### 📌 Local Preference

The script prioritizes local connectivity once per day:

```bash
FORCE_LOCAL=1
```

This causes rotation to begin at the local pod, evaluated via its resolved cluster IP—not `localhost`.

If local node is unreachable, it gracefully skips to external nodes.

---

### 🔄 Rotation Behavior

- Circular scanning using index math
- Skips double-commented entries (`##node:`)
- Leaves `provider.yaml` formatting intact (quotes, spacing, order)

---

### 🧯 Failsafe Design

- No eligible nodes → logs clearly, exits cleanly
- Each probe failure → logs reason
- Health failures do not stall the loop

---

### 🛠️ Maintenance Tips

- To re-trigger local preference:  
  Delete `.last_rpc_rotate`

- To update min chain age requirement:  
  Change `MIN_HOURS` near top of script

- To debug substitution issues:  
  Use `kubectl get pod akash-node-1-0 -n akash-services -o jsonpath='{.status.podIP}'`

---

### 📘 Version Compatibility

Tested on:
- Akashnet-2
- Tendermint v0.34.x
- Kubernetes 1.22+
- Helm 3+

---

### 🧪 Example Usage

```bash
cd ~/akash-provider-paladin/scripts
./rpc-rotate.sh
```

Returns:
- Successful node activation
- Helm redeploy log
- etcd sync results
- Comment toggle confirmation

---
