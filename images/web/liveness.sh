#!/usr/bin/env bash
# This is a script for the complex evaluation of whether Apache or other processes are running in the container.
check_process() {
    if ps aux | grep "$1" | grep -v grep > /dev/null; then
        return 0
    else
        return 1
    fi
}

# Check for openstreetmap-cgimap process
check_process "/usr/local/bin/openstreetmap-cgimap"
cgimap_status=$?

# Check for apache2 process
check_process "apache2"
apache_status=$?

# Evaluate results
if [ $cgimap_status -eq 0 ] && [ $apache_status -eq 0 ]; then
    echo "Both openstreetmap-cgimap and apache2 are running."
    exit 0
else
    echo "One or both processes are not running!" 1>&2
    exit 1
fi
