Hack for updating RPMs in an OCP cluster until
https://github.com/openshift/enhancements/blob/master/enhancements/ocp-coreos-layering.md
finalizes.

Quay.io setup:

1. If you do not already have a quay.io account, create one by logging
   into quay.io using the "Sign in with Red Hat" option to use SSO,
   and then filling out the rest of the account information (including
   selecting a quay.io username).

2. After creating the account (or if you already have an account but
   don't have a non-SSO password), click your username in the top
   right then click "Account Settings" in the menu, and then click
   "Change Password" near the bottom. Create a new password for this
   account which will only be used for docker/podman. (There's not
   really any need to follow this up with the "Generate Encrypted
   Password" option, because if your account is linked to RH SSO, then
   the password you set here can't be used to log in to the web site
   anyway, so it doesn't matter that it can be extracted in plaintext
   from your docker/podman config.)

3. Click "+ Create New Repository" and create a repository called
   "overrides". (With the options "Public" and "(Empty repository)".)


Local (development machine) setup:

1. Check out the sidedoor repo

2. In the checkout directory, create a `config.sh` with a variable
   pointing to your quay.io "overrides" repo:

       echo REPO=quay.io/${QUAY_USERNAME}/overrides > config.sh

3. Cache your password with podman:

       podman login quay.io


To build an override package:

1. Make a subdirectory with the "name" of this override package. Note
   that this name will end up being publicly visible on quay.io, so it
   shouldn't contain customer names or other confidential information.
   It should also be limited to alphanumeric characters. A bugzilla
   bug or support case number works.

2. Create subdirs "replace" and "new" of that directory and copy RPMs
   into the appropriate subdir. (RPMs that are replacements for RPMs
   already in the OCP image go into "replace/", while new RPMs go into
   "new/".)

3. Run `./build.sh ${NAME}` where `${NAME}` is the subdirectory name.
   This will build a container image containing the RPMs and an
   installer, and upload it to `${REPO}:${NAME}` (eg,
   `quay.io/danwinship/overrides:bz12345`)


To install the overrides in a customer cluster:

1. Give the customer a copy of `override.sh` from this repo
   (https://raw.githubusercontent.com/danwinship/sidedoor/master/override.sh)
   and have them run it (from a host with a `KUBECONFIG` that has
   cluster-admin credentials in their cluster). The syntax is

       ./override.sh <install|uninstall> [--workers-only] OVERRIDE-IMAGE

   eg:

       ./override.sh install quay.io/danwinship/overrides:bz12345

   This will deploy a DaemonSet to their cluster using the indicated
   image which will run `rpm-ostree override` to install (or
   uninstall) the RPMs in the image. (If they specify
   `--workers-only`, it will only deploy the changes to the worker
   nodes, not the masters.) Once the rpm-ostree changes are staged on
   every node, it will write out a dummy MachineConfig object to force
   MCO to drain and reboot the nodes one by one, to get them running the
   updated ostree image. The script will wait for the nodes to reboot.
   If updating both workers and masters it will do all of the workers
   first, and then the masters (because this requires two separate
   MachineConfigs).

2. To uninstall the overrides later, they can use `./override.sh
   uninstall`. For now, they have to pass the same arguments when
   uninstalling (image name and optional `--workers-only`), though in
   the future it may autodetect them.
