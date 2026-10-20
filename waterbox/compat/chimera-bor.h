/* chimera-bor.h - included before every file of OpenBOR (sources.mk).
 *
 * OpenBOR names glibc's mallinfo2 in an out-of-memory message; the
 * sandbox's C library (musl) has none. Both builds answer it from seams.c,
 * the same in each.
 */
#ifndef CHIMERA_BOR_H
#define CHIMERA_BOR_H
#include <stdlib.h>
#if !defined(__GLIBC__)
struct mallinfo2
{
	size_t arena, ordblks, smblks, hblks, hblkhd, usmblks, fsmblks, uordblks, fordblks, keepcost;
};
struct mallinfo2 mallinfo2(void);
#endif
#endif
