#!/bin/bash
docker run --rm -it \
    --platform linux/amd64 \
    -v ~/ti-am62x/workspace:/workspace \
    --name ti-build \
    ti-am62x-dev
