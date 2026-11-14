#!/bin/bash
# Called by release-notes.sh with the commit of the previous publish: whether the savestate
# layout changed since then, and so whether the states need the converter. The layout of a
# build is the "current" file of its package (sd/ for this one, releases/sd/ for the previous).
f=Scripts/.megadrive_savestates/maps/current
b=$(cat "sd/$f" 2> /dev/null)
a=$(git show "$1:releases/sd/$f" 2> /dev/null)
[ -n "$a" ] && [ -n "$b" ] || exit 0
echo
if [ "$a" = "$b" ]; then
  echo "Savestate layout $b, as in the previous release: states load as they are."
else
  echo "Savestate layout $a -> $b: run megadrive_savestates.sh from the Scripts menu once to"
  echo "convert the states saved with the previous release."
fi
