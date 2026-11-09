#!/bin/bash
# MiSTer Scripts menu: convert the MegaDrive savestates in /media/fat/savestates/MegaDrive
# to the core build in use (originals are kept as .bak). Needs the layout maps of the
# builds that saved them in .megadrive_savestates/maps (each build package adds its own).
cd "$(dirname "$0")/.megadrive_savestates" || exit 1
python3 mdss_convert.py "$@"
