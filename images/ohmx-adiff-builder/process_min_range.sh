#!/bin/bash
# Usage: ./process_min_range.sh SEQNO_START SEQNO_END [generate_adiffs|process_adiffs|both]
# Example: ./process_min_range.sh 1884610 1884615 generate_adiffs
#          ./process_min_range.sh 1884610 1884615 process_adiffs

source "config.sh"
source "functions.sh"

min_seqno="$1"
max_seqno="$2"
mode="$3"

if [ "$mode" == "generate_adiffs" ]; then
    download_and_generate_adiffs "$min_seqno" "$max_seqno"
    process_adiff_range "$min_seqno" "$max_seqno"
elif [ "$mode" == "process_adiffs" ]; then
    process_adiff_range "$min_seqno" "$max_seqno"
fi

