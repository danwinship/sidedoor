#!/bin/bash

set -e
trap "echo FAILED; sleep infinity" EXIT

case "$1" in
    install)
        hosttmpdir=$(mktemp -d /host/var/tmp/override.XXXXXX)
        cp /rpms/*.rpm ${hosttmpdir}/
        host_rpm_paths=$(echo ${hosttmpdir}/*.rpm | sed -e 's|/host/|/|g')
        chroot /host rpm-ostree override replace ${host_rpm_paths}
        ;;

    uninstall)
        rpm_names=$(rpm -qp --qf '%{NAME} ' /rpms/*.rpm)
        chroot /host rpm-ostree override reset ${rpm_names}
        ;;

    *)
        echo "Bad command '$1'. Should be 'install' or 'uninstall'."
        exit 1
esac

# DaemonSets MUST be "restartPolicy: Always", so don't exit
echo "SUCCESS"
sleep infinity
