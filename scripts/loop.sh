while true; do
  echo "[🧪] Running control-plane test loop at $(date)"

  /bin/bash $HOME/akash-provider-paladin/scripts/ticker-control-plane.sh

  sleep 60
done
