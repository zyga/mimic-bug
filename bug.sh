#!/bin/sh -e
case "${1:-}" in
	'')
		test -e bug-snap_1_all.snap || snap pack bug-snap
		test "$(id -u)" -eq 0 || ( echo "run this as root please"; exit 1 )
		"$0" ns:system > ns-system.log
		echo "test complete, examine ns-{system,snap,user}.log"
		;;
	ns:system)
		ns=ns:system
		# Prepare a throw-away tmpfs in /bug. Everything is mounted inside that
		# location and script cleanup ensures that the whole tree is detached.
		# This allows to re-run this script without significant problems.
		mkdir -p /bug
		mount -t tmpfs none /bug
		trap 'umount --lazy /bug && rmdir /bug' EXIT
		# Create private (unshared) space for preserved mount namespaces.  This
		# directory is prepared in a way similar to /run/snapd/ns. The files
		# /bug/ns/snap and /bug/ns/user will contain preserved mount namespaces
		# for interactive debugging.
		mkdir /bug/ns
		mount --bind /bug/ns /bug/ns
		mount --make-private /bug/ns
		touch /bug/ns/snap
		# XXX: because ns:user is captured by process in ns:snap the mount will
		# not be visible on the host. In snap-confine it is visible because all
		# captures are done by a helper process in ns:system.
		touch /bug/ns/user
		# The directory /bug/mimic will represent a writable mimic. The mimic
		# will "mimic" a file and directory from the "bug-snap" snap. The mimic
		# will be constructed in the ns:snap mount namespace below, after
		# ns:user already exists, to examine propagation behavior.
		mkdir /bug/mimic/
		mount -t squashfs -o ro ./bug-snap_1_all.snap /bug/mimic/
		# The directory /bug/sync will contain stamp files used for
		# synchronization amongst the three interacting processes.
	    mkdir /bug/sync	
		# We are ready, let's examine the namespace.
		echo "hello from $ns"
		findmnt --pairs -o+PROPAGATION,ID | tail -n 3
		# NOTE: propagation unchanged is to explicitly encode propagation
		# changes. Similarly, snap-confine does not globally change
		# propagation.
		unshare --mount=/bug/ns/snap --propagation unchanged "$0" ns:snap > ns-snap.log &
		# Wait for the ns:snap process and wrap up.
		wait
		echo "hello from $ns (after mimic)"
		findmnt --pairs -o+PROPAGATION,ID | tail -n 4
		echo "wrapping up $ns"
		;;
	ns:snap)
		ns=ns:snap
		mount --make-slave /bug
		mount --make-slave /bug/mimic
		echo "hello from $ns (before mimic)"
		findmnt --pairs -o+PROPAGATION,ID | tail -n 3
		unshare --mount=/bug/ns/user --propagation unchanged "$0" ns:user > ns-user.log &
		# Wait for the process inside ns:user to indicate readiness.
		while test ! -e /bug/sync/ns-user-ready; do sleep 0.1; done
		# Construct the writable mimic now.
		mkdir -p /bug/tmp/.snap/mimic
		mount --bind /bug/mimic /bug/tmp/.snap/mimic
		mount -t tmpfs none /bug/mimic/
		touch /bug/mimic/file
		mkdir /bug/mimic/dir
		mkdir /bug/mimic/meta
		mount --bind /bug/tmp/.snap/mimic/file /bug/mimic/file
		mount --bind /bug/tmp/.snap/mimic/dir /bug/mimic/dir
		mount --bind /bug/tmp/.snap/mimic/meta /bug/mimic/meta
		umount --detach /bug/tmp/.snap/mimic
		# Indicate that the mimic has been constructed.
		touch /bug/sync/mimic-ready
		# Show the mount table again.
		echo "hello from $ns (after mimic)"
		findmnt --pairs -o+PROPAGATION,ID | tail -n 8
		# Wait for the ns:user process and wrap up.
		wait
		echo "wrapping up $ns"
		;;
	ns:user)
		ns=ns:user
		mount --make-slave /bug
		mount --make-slave /bug/mimic
		touch /bug/sync/ns-user-ready
		echo "hello from $ns"
		findmnt --pairs -o+PROPAGATION,ID | tail -n 3
		# Wait for the process inside ns:snap to indicate mimic has been constructed.
		while test ! -e /bug/sync/mimic-ready; do sleep 0.1; done
		# Show the mount table again.
		echo "hello from $ns (after mimic)"
		findmnt --pairs -o+PROPAGATION,ID | tail -n 3
		# Wrap up and quit.
		echo "wrapping up $ns"
		;;
esac
