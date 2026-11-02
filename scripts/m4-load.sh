#!/bin/bash
# Usage: az vm run-command invoke -g <rg> -n <vm> --command-id RunShellScript --scripts @scripts/m4-load.sh
# M4 test load: saturate CPU and data disk (LUN 0) bandwidth for 15 minutes.
DEV=/dev/disk/azure/scsi1/lun0
[ -e "$DEV" ] || DEV=$(readlink -f /dev/disk/azure/scsi1/lun0 2>/dev/null)
TOOLS=builtin
if timeout 120 apt-get update -qq >/dev/null 2>&1 && timeout 300 apt-get install -y -qq fio stress-ng >/dev/null 2>&1; then TOOLS=fio+stress-ng; fi
echo "tools=$TOOLS dev=$DEV nproc=$(nproc)" > /tmp/m4-load.info
if [ "$TOOLS" = "fio+stress-ng" ]; then
  # run-command processes live in the agent's CPU-limited cgroup (azure-vmextensions.slice); systemd-run escapes it
  systemd-run --unit=m4cpu --collect stress-ng --cpu 0 --cpu-load 100 --timeout 900s
  setsid nohup fio --name=bw --filename=$DEV --rw=write --bs=1M --direct=1 --iodepth=32 --ioengine=libaio --time_based --runtime=900 >/tmp/fio.log 2>&1 &
else
  for i in $(seq $(nproc)); do setsid nohup timeout 900 sh -c 'while :; do :; done' >/dev/null 2>&1 & done
  setsid nohup timeout 900 sh -c "while :; do dd if=/dev/zero of=$DEV bs=1M oflag=direct status=none; done" >/dev/null 2>&1 &
fi
sleep 5; cat /tmp/m4-load.info; uptime
