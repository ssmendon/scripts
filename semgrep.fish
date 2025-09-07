#!/usr/bin/env fish
# Copyright (C) 2025 Sohum Mendon
# SPDX-License-Identifier: MIT

set -l options \
    's/src=' \
    'd/dst=' \
    \
    'append' \
    'h/help' \
    'offline'

function usage
    echo "Usage: semgrep.fish [OPTIONS]... [-s SRC] [-d DST] [--] [ARGS]...
    Example: semgrep.fish -s code -d report

    SRC is the directory containing source code to analyze.
    DST is the directory where the reports should be written.
    ARGS are passed directly to semgrep.

    If SRC and DST are not specified, then ARGS must be specified.
    SRC and DST and ARGS can be specified at the same time.

    Options:
        -h, --help      Print this help message

        -s, --src       Directory where code is read
        -d, --dst       Directory where outputs should be saved

        --append        Whether to append ARGS to existing parameters
        --offline       Whether to disable network connectivity"
end

argparse $options -- $argv
or return

if set -q _flag_help
    usage
    return
end

if not set -q _flag_src _flag_dst; and not set -q argv[1]
    echo >&2 "error: not enough arguments"
    usage >&2
    return 1
end

for p in _flag_src _flag_dst
    not set -q $p; and continue
    if not set $p (path resolve $$p)
        echo >&2 "error: failed to resolve path:" $pp
        return 1
    end
end
set -q _flag_src; and set src $_flag_src
set -q _flag_dst; and set dst $_flag_dst

set -q src; and set -a podman_volumes --mount=type=bind,src="$src",dst=/src,ro=true
set -q dst; and set -a podman_volumes --mount=type=bind,src="$dst",dst=/report,U=true


# defaults
set -l image docker.io/semgrep/semgrep:latest
set -l basename /report/semgrep-scan

# construct cli
set -l podman_options \
    --env SEMGREP_SEND_METRICS=off \
    --pull=newer \
    --rm
set -q _flag_offline; and set -a podman_options --network=none


set -l semgrep_args \
    semgrep scan \
        /src \
        --oss-only \
        --json-output="$basename.json" \
        --sarif-output="$basename.sarif" \
        --text-output="$basename.txt" \
        --config p/default
if set -q argv[1]
    if set -q _flag_append
        set -a semgrep_args $argv
    else
        set semgrep_args $argv
    end
end
set -q dst; and mkdir -p "$dst"
podman run $podman_options $podman_volumes $image $semgrep_args
