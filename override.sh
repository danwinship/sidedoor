#!/bin/sh

# This is run by the administrator from outside the cluster to install
# or uninstall the overrides.
# 
# Note: The administrator may run this on a system without bash, or on
# OS X, so it needs to be portable.

set -e

function usage() {
    exec 1>&2
    echo "Usage: $0 <install|uninstall> [--workers-only] OVERRIDE-IMAGE"
    echo ""
    echo "This will install or uninstall the overrides from OVERRIDE-IMAGE."
    echo ""
    echo "If --workers-only is passed, then the master nodes will not be touched."
}

while [ -n "$*" ]; do
    case "$1" in
        install|uninstall)
            action=$1
            shift
            ;;

        --workers-only|--worker-only)
            workers_only=true
            # "workers-only" really means "not masters". (eg, it includes infra nodes)
            node_affinity="affinity: { nodeAffinity: { requiredDuringSchedulingIgnoredDuringExecution: { nodeSelectorTerms: [ { matchExpressions: [ { key: node-role.kubernetes.io/master, operator: DoesNotExist } ] } ] } } }"
            node_filter="-l node-role.kubernetes.io/master!="
            shift
            ;;

        */*:*)
            image=$1
            tag=$(echo "${image}" | sed -e 's/.*://')
            shift
            ;;

        *)
            usage
            exit 1
            ;;
    esac
done

if [ -z "${action}" ] || [ -z "${image}" ]; then
    usage
    exit 1
fi

clustername=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}' 2>/dev/null || /bin/true)
version=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || /bin/true)

if [ -z "${clustername}" ] || [ -z "${version}" ]; then
    exec 1>&2
    echo "Unable to fetch cluster information. Do you need to set KUBECONFIG?"
    echo ""
    echo "$ oc get clusterversion"
    oc get clusterversion
    # not expected to be reached due to "set -e", but...
    exit 1
fi

# FIXME: double-check version against the override...

echo "${action}ing overrides from '${image}' in cluster '${clustername}' at version '${version}'"
echo ""

namespace="openshift-overrides-${tag}"
oc create namespace "${namespace}"
oc create serviceaccount -n "${namespace}" overrides
oc adm policy add-scc-to-user privileged -n "${namespace}" -z overrides

oc create -f - <<EOF
kind: DaemonSet
apiVersion: apps/v1
metadata:
  name: overrides
  namespace: ${namespace}
  labels:
    name: overrides
spec:
  selector:
    matchLabels:
      name: overrides
  template:
    metadata:
      labels:
        name: overrides
    spec:
      containers:
        - name: do-overrides
          image: '${image}'
          imagePullPolicy: Always
          command: ["/do-overrides.sh", "${action}"]
          securityContext:
            privileged: true
            runAsUser: 0
          volumeMounts:
          - mountPath: /host
            name: host-slash
      serviceAccount: overrides
      hostNetwork: true
      hostPID: true
      restartPolicy: Always
      terminationGracePeriodSeconds: 0
      nodeSelector:
        kubernetes.io/os: linux
      volumes:
      - name: host-slash
        hostPath:
          path: /
      tolerations:
      - operator: Exists
      ${node_affinity}
EOF

num_nodes=$(oc get nodes ${node_filter} --no-headers | wc -l)
echo ""
echo "Waiting for ${num_nodes} nodes to stage the RPM changes."

# Wait for all Pods to be deployed and then parse their logs. (DaemonSets have to
# be "restartPolicy: Always", so we can't just have the pods exit and then check their
# status. :-/
for try in $(seq 1 10); do
    num_success=0
    sleep ${try}
    for pod in $(oc get pods -n "${namespace}" -o jsonpath='{range .items[*]}{.metadata.name} {end}'); do
        result=$(oc logs --tail=1 -n "${namespace}" "${pod}")
        case "${result}" in
            SUCCESS)
                num_success=$(echo ${num_success} + 1 | bc)
                ;;
            FAILED)
                exec 1>&2
                echo "Pod ${pod} failed:"
                echo ""
                oc logs -n "${namespace}" "${pod}"
                exit 1
                ;;
        esac
    done
    if [ "${num_success}" = "${num_nodes}" ]; then
        break
    fi
    echo "${num_success} of ${num_nodes} nodes have staged the changes... Waiting..."
done

if [ "${num_success}" != "${num_nodes}" ]; then
    exec 1>&2
    echo "Timed out waiting for all nodes to stage changes."
    exit 1
fi
echo "All nodes have staged the changes."
echo ""

oc delete daemonset -n "${namespace}" overrides
oc delete namespace "${namespace}"

function reboot_nodes() {
    role="$1"

    old_generation=$(oc get machineconfigpool "${role}" -o jsonpath="{.status.observedGeneration}")

    echo ""
    if [ "${action}" = "install" ]; then
        echo "Creating override MachineConfig for ${role} nodes"

        # The base64-encoded message is:
        #
        # The presence of this file indicates that RPM overrides have been applied
        # to this host. Note that removing the MachineConfig that created this
        # file will not cause the RPM overrides to be removed.
        oc create -f - <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: ${role}
  name: overrides-${tag}-${role}
spec:
  config:
    ignition:
      version: 2.2.0
    storage:
      files:
      - contents:
          source: "data:text/plain;base64,VGhlIHByZXNlbmNlIG9mIHRoaXMgZmlsZSBpbmRpY2F0ZXMgdGhhdCBSUE0gb3ZlcnJpZGVzIGhhdmUgYmVlbiBhcHBsaWVkCnRvIHRoaXMgaG9zdC4gTm90ZSB0aGF0IHJlbW92aW5nIHRoZSBNYWNoaW5lQ29uZmlnIHRoYXQgY3JlYXRlZCB0aGlzCmZpbGUgd2lsbCBub3QgY2F1c2UgdGhlIFJQTSBvdmVycmlkZXMgdG8gYmUgcmVtb3ZlZC4K"
        filesystem: root
        mode: 0644
        path: /etc/openshift/overrides-${tag}
EOF
    else
        echo "Deleting override MachineConfig for ${role} nodes"
        oc delete machineconfig overrides-${tag}-${role}
    fi

    echo ""
    echo "Waiting for the ${role} MachineConfigPool to be updated with the new MachineConfig" 
    for try in $(seq 1 10); do
        sleep ${try}
        generation=$(oc get machineconfigpool "${role}" -o jsonpath="{.status.observedGeneration}")
        if [ "${generation}" != "${old_generation}" ]; then
            break
        fi
    done

    if [ "${generation}" = "${old_generation}" ]; then
        exec 1>&2
        echo "MachineConfigPool '${role}' is not updating"
        exit 1
    fi

    num=$(oc get machineconfigpool "${role}" -o jsonpath="{.status.machineCount}")

    echo "Waiting for the ${role} MachineConfigPool to update all nodes. (This will take several minutes per node.)"
    while :; do
        sleep 10
        updated=$(oc get machineconfigpool "${role}" -o jsonpath="{.status.updatedMachineCount}")
        echo "${updated}/${num} nodes updated..."
        if [ "${updated}" = "${num}" ]; then
            break
        fi
    done
}


# Install dummy MachineConfig(s) to force reboots.
reboot_nodes worker
if [ "${workers_only}" != "true" ]; then
    reboot_nodes master
fi

echo ""
echo "Overrides installed."
