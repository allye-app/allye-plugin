#!/bin/bash
# Test fixture (ALY-290.5): a stand-in for getent. `getent passwd UID` prints one passwd line whose home is $GETENT_HOME.
# Every call is logged to $GETENT_LOG (argv only), so a test can prove the hook passes nothing but the uid.
printf "%s\n" "$*" >>"${GETENT_LOG:-/dev/null}"
[ "$1" = passwd ] && [ -n "${2-}" ] && [ -n "${GETENT_HOME-}" ] || exit 2
printf "%s:x:%s:%s::%s:/bin/sh\n" shimuser "$2" "$2" "$GETENT_HOME"
