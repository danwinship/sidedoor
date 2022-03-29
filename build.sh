#!/bin/bash

set -e

if [[ $# != 1 ]] || [[ ! -d $1 ]]; then
    exec 2>&1
    echo "Usage: $0 SUBDIR"
    echo "Builds an override installer for the RPMs in the indicated SUBDIR."
    exit 1
fi

if [[ -f config.sh ]]; then
    . config.sh
fi

if [[ -z "${REPO}" ]]; then
    exec 2>&1
    echo "Error: must set REPO in environment or config.sh"
    exit 1
fi

name=$1

cp do-overrides.sh ${name}/
cat > ${name}/Dockerfile <<EOF
FROM registry.access.redhat.com/ubi8/ubi-minimal
RUN mkdir /rpms
COPY do-overrides.sh /
COPY *.rpm /rpms/

LABEL io.k8s.display-name="overrides (${name})" \
      io.k8s.description="This installs or removes a set of RPM overrides."
EOF

pushd "${name}"
podman build -t "${REPO}:${name}" .
popd
podman push "${REPO}:${name}"

echo ""
echo "Override image saved to ${REPO}:${name}"
