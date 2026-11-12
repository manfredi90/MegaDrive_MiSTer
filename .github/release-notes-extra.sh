#!/bin/bash
# Called by release-notes.sh with the tag of the previous full release: whether the savestate
# layout changed since then, and so whether the states need the converter. The layout of a
# build is the "current" file of its package (sd/ for this one, an asset for the previous).
b=$(cat sd/Scripts/.megadrive_savestates/maps/current 2> /dev/null)
a=$(gh release download "$1" -p current -O - 2> /dev/null)
[ -n "$a" ] && [ -n "$b" ] || exit 0
echo
if [ "$a" = "$b" ]; then
  echo "Savestate layout $b, as in $1: states load as they are."
else
  echo "> [!IMPORTANT]"
  echo "> Savestate layout $a → $b: run megadrive_savestates.sh from the Scripts menu once to convert the states saved with $1."
fi
