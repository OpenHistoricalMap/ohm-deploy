#!/usr/bin/make -f

# Builds changeset augmented diffs from stage-data/split-adiffs/*/ and writes
# them to bucket-data/*.adiff. Skips any output changeset that already exists
# and is newer than any of its constituent inputs.

.PHONY: all
.ONESHELL:
.SECONDEXPANSION:

SPLIT_ADIFFS_DIR ?= stage-data/split-adiffs
CHANGESET_DIR ?= stage-data/changesets
BUCKET_DIR ?= bucket-data/replication/minute
API_URL ?= https://api.openhistoricalmap.org
# A changeset whose fragments add up to more than this is not published.
ADIFF_MAX_OUTPUT_MB ?= 256


MAKEDIR := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))

# all: metadatas changesets
all: changesets

changesets: $(shell find $(SPLIT_ADIFFS_DIR)/ -mindepth 1 -type d | sed 's|$(SPLIT_ADIFFS_DIR)|$(CHANGESET_DIR)/|g' | sed 's|$$|.adiff.md5|')

# merge_adiffs.py can fail if it is given no input files or if one or more of its
# input files are not found. Either can happen if the split-adiffs/*/ directory is
# deleted by gc.sh while Make runs this script. So we only move the adiff into
# bucket-data and update the stamp file if the merged output is nonempty (-s).
# The leading @ (with .ONESHELL) silences command echo so the log stays readable.
#
# A changeset that edits many large relations can produce many GB of fragments.
# OSMCha cannot load an adiff that big, so it is not merged or uploaded. The
# fragments are deleted and a .too-big marker stays in the directory, so later
# fragments of the same changeset are dropped too instead of being published as
# a partial adiff. gc.sh removes the directory with the stamp file as usual.
$(CHANGESET_DIR)/%.adiff.md5: $$(wildcard $(SPLIT_ADIFFS_DIR)/%/*)
	@dir=$(SPLIT_ADIFFS_DIR)/$*
	size_mb=$$(du -sm $$dir | cut -f1)
	if [ -e $$dir/.too-big ] || [ $$size_mb -gt $(ADIFF_MAX_OUTPUT_MB) ]; then
		echo "changeset $(notdir $*): fragments are $${size_mb}MB (limit $(ADIFF_MAX_OUTPUT_MB)MB), not publishing"
		touch $$dir/.too-big
		rm -f $$dir/*.adiff
		echo too-big > $@
		exit 0
	fi
	tmpfile=$$(mktemp)
	python merge_adiffs.py $^ > $$tmpfile
	if [ -s $$tmpfile ]; then
		md5sum < $$tmpfile > $@
		gzip -c < $$tmpfile > $$tmpfile.gz
		mv $$tmpfile.gz $(BUCKET_DIR)/$*.adiff && rm $$tmpfile
	fi

metadatas: $(shell find $(SPLIT_ADIFFS_DIR)/ -mindepth 1 -type d | sed 's|$$|/metadata.xml|')

$(SPLIT_ADIFFS_DIR)/%/metadata.xml:
	curl -sL "$(API_URL)/api/0.6/changeset/$*" -o $@
