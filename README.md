# About
This repository shows how writable mimic construction is NOT propagated to
per-user mount namespace.

# Usage
Ensure that you have `snap pack` on your path and that you can run as root. The
script will use the directory `/bug` for all the work it performs.

# Debugging
Feel free to edit `bug.sh` create _breakpoints_ so that you can nsenter into
mount namespaces stored in /bug/ns and perform interactive analysis.
