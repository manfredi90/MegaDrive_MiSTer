#!/bin/bash
# Run by sync.yml after an upstream merge (usage: sync-hook.sh <savestates before the merge>).
# The build generates the savestate netlist from md_core.v and Nuked-MD; when the merge changed
# those, the layout of the scan chain may change too. Its map must then be in savestate/layouts,
# so that the converter can bring the states of the previous builds over: generate it here and
# commit it.
set -e
before=$1
src="rtl/md_core.v rtl/nuked-md savestate"
git diff --quiet "$before" HEAD -- $src && exit 0

sudo apt-get update -q > /dev/null && sudo apt-get install -y -q yosys > /dev/null
yosys -V
sh savestate/gen_netlist.sh
new=$(sed -n "s/.*32'h\(........\);/\1/p" rtl/md_core_ss.vh)
rm -f rtl/md_core_ss.v rtl/md_core_ss.vh   # the netlist itself is not kept in git

git add savestate/layouts
if git diff --cached --quiet; then
  echo "::notice::savestate layout $new unchanged"
  exit 0
fi
up=$(git rev-parse --short HEAD^2 2> /dev/null || git rev-parse --short HEAD)
git commit -q -m "Savestate: layout map $new" -m "The scan chain changed with upstream $up: states saved with earlier builds convert with the script."
echo "::notice::new savestate layout $new"
