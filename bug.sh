#!/bin/bash -ex
trap 'printf "\nFAILED\n"; exit 1;' ERR
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
		mount --make-rshared /bug
		trap 'umount --lazy /bug && rmdir /bug' EXIT
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
		echo "hello from $ns (before mimic)"
		tail -n 3 /proc/self/mountinfo
		# NOTE: propagation unchanged is to explicitly encode propagation
		# changes. Similarly, snap-confine does not globally change
		# propagation.
		unshare --mount --propagation unchanged "$0" ns:snap > ns-snap.log &
		# Wait for the ns:snap process and wrap up.
		wait
		echo
		echo "hello from $ns (after mimic)"
		tail -n 4 /proc/self/mountinfo
		echo "wrapping up $ns"
		;;
	ns:snap)
		ns=ns:snap
		mount --make-rslave /
		mount --make-rshared /
		# New behavior: create a propagation=private /tmp
		mkdir /bug/tmp
		mount --bind /bug/tmp /bug/tmp
		mount --make-private /bug/tmp
		echo "hello from $ns (before mimic)"
		tail -n 3 /proc/self/mountinfo
		unshare --mount --propagation unchanged "$0" ns:user > ns-user.log &
		# Wait for the process inside ns:user to indicate readiness.
		while test ! -e /bug/sync/ns-user-ready; do sleep 0.1; done
		# Construct the writable mimic now.
		mkdir -p /bug/tmp/.snap/mimic
		mount --rbind /bug/mimic /bug/tmp/.snap/mimic
		mount --make-rprivate /bug/tmp/.snap/mimic
		mount -t tmpfs none /bug/mimic
		touch /bug/mimic/file
		mkdir /bug/mimic/dir
		mkdir /bug/mimic/meta
		mount --bind  /bug/tmp/.snap/mimic/file /bug/mimic/file
		mount --bind  /bug/tmp/.snap/mimic/dir  /bug/mimic/dir
		mount --bind  /bug/tmp/.snap/mimic/meta /bug/mimic/meta
		umount --lazy /bug/tmp/.snap/mimic
		# Indicate that the mimic has been constructed.
		touch /bug/sync/mimic-ready
		# Show the mount table again.
		echo
		echo "hello from $ns (after mimic)"
		tail -n 7 /proc/self/mountinfo
		# Wait for the ns:user process and wrap up.
		wait
		echo "wrapping up $ns"
		;;
	ns:user)
		ns=ns:user
		mount --make-rslave /
		touch /bug/sync/ns-user-ready
		echo "hello from $ns (before mimic)"
		tail -n 3 /proc/self/mountinfo
		# Wait for the process inside ns:snap to indicate mimic has been constructed.
		while test ! -e /bug/sync/mimic-ready; do sleep 0.1; done
		# Show the mount table again.
		echo
		echo "hello from $ns (after mimic)"
		tail -n 7 /proc/self/mountinfo
		# Wrap up and quit.
		echo "wrapping up $ns"
		;;
esac
