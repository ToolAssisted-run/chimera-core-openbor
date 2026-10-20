/*
 * OpenBOR's version.h, which its build writes with engine/version.sh from git
 * (the number of commits, the commit's hash). Here it is the pinned commit's,
 * written by hand when the pin moves: extern/openbor at 65a7f0b, the 8027th
 * commit of DCurrent/openbor's master.
 */
#ifndef VERSION_H
#define VERSION_H

#define VERSION_NAME "OpenBOR"
#define VERSION_MAJOR "4"
#define VERSION_MINOR "0"
#define VERSION_BUILD "8027"
#define VERSION_BUILD_INT 8027
#define VERSION_COMMIT "65a7f0b"
#define VERSION "v"VERSION_MAJOR"."VERSION_MINOR" Build "VERSION_BUILD" (commit hash: "VERSION_COMMIT")"

#endif
