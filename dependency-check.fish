#!/usr/bin/env fish
# Copyright (C) 2025 Sohum Mendon
# SPDX-License-Identifier: MIT

# defaults
set -l IMAGE docker.io/owasp/dependency-check:latest
# TODO: now i'm using volumes, so remove this.
set -l CACHE_DIR ~/.cache/dependency-check
set -l DATA_DIR ~/.local/share/dependency-check
set -l PROJECT "dependency check scan: $PWD"

# TODO: this is probably only useful for rootful containers
set -l USER "$USER"

# TODO: fish_opt doesn't add any clarity here. it's more confusing to use it.
set -l options \
    (fish_opt -s h -l help) \
    (fish_opt -r -s i -l image) \
    (fish_opt -r --long-only -s c -l cache-dir) \
    (fish_opt -r --long-only -s a -l data-dir) \
    (fish_opt -r -s p -l project) \
    (fish_opt --long-only -s o -l offline) \
    (fish_opt --long-only -s n -l append) \
    (fish_opt -r -s s -l src) \
    (fish_opt -r -s d -l dst)

function usage
    echo "Usage: dependency-check.fish [OPTIONS]... [-s SRC] [-d OUT] [--] [ARGS]...
    Example: dependency-check.fish --cache-dir ~/.cache ./project-src ./project-reports

    SRC is a directory containing source code to analyze.
    OUT is a directory where the report should be written.
    ARGS are passed directly to dependency-check.

    If SRC and DST are not specified, then ARGS must be specified.
    SRC and DST and ARGS can be specified at the same time.

    Any remaining arguments are passed directly to dependency-check.

    Options:
      -h, --help        Print this help message
      -i, --image       Select the image to use
                            (default: $IMAGE)
      --cache-dir       The cache directory to use
                            (default: $CACHE_DIR)
      --data-dir        The data directory to use
                            (default: $DATA_DIR)
      -p, --project     The project name to use.
                            (default: $PROJECT)
      --offline         Whether to allow network access.
      --append          Whether to append command-line args.
      -s, --src         The code to analyze.
      -d, --dst         Where to store the report."
end

# argument validation
argparse $options -- $argv
or return
if set -q $_flag_h
    usage
    return
end

set -q _flag_src; and set src (path resolve $_flag_src)
set -q _flag_dst; and set dst (path resolve $_flag_dst)

# src,dst both must be set OR additional args must be set
# or both.
if not set -q _flag_src _flag_dst; and not set -q argv[1]
    echo >&2 "error: at least one of SRC,DST and ARGS must be set"
    echo >&2 "SRC=" $src
    echo >&2 "DST=" $dst
    echo >&2 "ARGS=" $argv
    usage
    return 1
end

# override defaults if passed
set -q _flag_image; and set IMAGE $_flag_image
set -q _flag_cache_dir; and set CACHE_DIR $_flag_cache_dir
set -q _flag_data_dir; and set DATA_DIR $_flag_data_dir
set -q _flag_project; and set PROJECT $_flag_project; or set PROJECT "dependency check scan: $src"

# TODO: rootful containers
not string length -q $USER; and set USER (id -n -u)
if not string length -q $USER
    echo >&2 "Failed to determine current user"
    return 1
end
set -l uid (id -u $USER); or return
set -l gid (id -g $USER); or return

# make podman options, volumes
set -l podman_options \
    --env "user=$USER" \
    --pull=newer \
    --rm \
    --user "$uid:$gid"
set -q _flag_online; and set -a podman_options --network=none
set -l podman_volumes \
    --mount=type=volume,src=dependency-check-data,dst=/usr/share/dependency-check/data,U=true \
    --mount=type=volume,src=dependency-check-cache,dst=/usr/share/dependency-check/data/cache,U=true
set -q src; and set -a podman_volumes --mount=type=bind,src="$src",dst=/src,ro=true
set -q dst; and set -a podman_volumes --mount=type=bind,src="$dst",dst=/report,U=true
set -l args \
    --scan /src \
    --format "ALL" \
    --project "$PROJECT" \
    --out /report
if set -q argv[1]
    if set -q _flag_append
        set -a args $argv
    else
        set args $argv
    end
end

# TODO: using volumes, eliminate this useless code
# make mount directories before launching
#mkdir -p "$CACHE_DIR" "$DATA_DIR"; or return
if set -q dst
    mkdir -p "$dst"; or return
end
podman run $podman_options $podman_volumes $IMAGE $args
