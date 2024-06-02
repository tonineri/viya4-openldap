#!/bin/bash
set -euxo pipefail
source /container/env

apt-get clean
rm -rf /tmp/* \
    /var/tmp/* \
    /var/lib/apt/lists/* \
    /container/file \
    /container/build.sh /container/Dockerfile