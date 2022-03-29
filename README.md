Hack for updating RPMs in an OCP cluster until
https://github.com/openshift/enhancements/blob/master/enhancements/ocp-coreos-layering.md
finalizes.

Setup:

1. If you do not already have a quay.io account, create one

2. On quay.io, create a new repo named "overrides"

3. Check out this repo

4. `echo REPO=quay.io/${QUAY_USERNAME}/overrides > config.sh`


To build an override package:

1. Make a subdirectory with the "name" of this override package. Note
   that this name will end up being publicly visible on quay.io, so it
   shouldn't contain customer names or other confidential information.
   It should also be limited to alphanumeric characters. A bugzilla
   bug or support case number works.

2. Copy RPMs into the subdir. (All RPMs in the subdir will be copied
   into the image.)

3. Run `./build.sh ${NAME}` where `${NAME}` is the subdirectory name.
   This will build a container image containing the RPMs and an
   installer, and upload it to `${REPO}:${NAME}` (eg,
   `quay.io/danwinship/overrides:bz12345`)


To install the overrides in a customer cluster:

1. Give the customer a copy of `override.sh` from this repo and have
   them run it (from a host with a `KUBECONFIG` that has cluster-admin
   credentials in their cluster). The syntax is

     ./override.sh <install|uninstall> [--workers-only] OVERRIDE-IMAGE

   eg:

     ./override.sh install quay.io/danwinship/overrides:bz12345

   This will deploy a DaemonSet to their cluster using the indicated
   image which will run `rpm-ostree override` to install (or
   uninstall) the RPMs in the image. (If they specify
   `--workers-only`, it will only deploy the changes to the worker
   nodes, not the masters.) Once the rpm-ostree changes are staged on
   every node, it will write out a dummy MachineConfig object to force
   the nodes to reboot into the updated ostree image, and wait for the
   nodes to reboot.

2. To uninstall the overrides later, they can use `./override.sh
   uninstall`. For now, they have to pass the same arguments when
   uninstalling (image name and optional `--workers-only`), though in
   the future it may autodetect them.
