#!/bin/bash

set -e
trap "echo FAILED; sleep infinity" EXIT

case "$1" in
    install)
        hosttmpdir=$(mktemp -d /host/var/tmp/override.XXXXXX)
        mkdir ${hosttmpdir}/new ${hosttmpdir}/replace
        cp /rpms/new/*.rpm ${hosttmpdir}/new
        cp /rpms/replace/*.rpm ${hosttmpdir}/replace
        host_new_rpm_paths=$(echo ${hosttmpdir}/new/*.rpm | sed -e 's|/host/|/|g')
        host_replace_rpm_paths=$(echo ${hosttmpdir}/replace/*.rpm | sed -e 's|/host/|/|g')
        chroot /host rpm-ostree install ${host_new_rpm_paths}
        chroot /host rpm-ostree override replace ${host_replace_rpm_paths}
        ;;

    uninstall)
        new_rpm_names=$(rpm -qp --qf '%{NAME} ' /rpms/new/*.rpm)
        replace_rpm_names=$(rpm -qp --qf '%{NAME} ' /rpms/new/*.rpm)
        chroot /host rpm-ostree uninstall ${new_rpm_names}
        chroot /host rpm-ostree override reset ${replace_rpm_names}
        ;;

    *)
        echo "Bad command '$1'. Should be 'install' or 'uninstall'."
        exit 1
esac

# DaemonSets MUST be "restartPolicy: Always", so don't exit
echo "SUCCESS"
sleep infinity
