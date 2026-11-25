// SPDX-License-Identifier: GPL-2.0-only
/*
 * Large NPU buffer allocation test for the rknpu driver (DRM interface).
 *
 * In IOMMU mode, non-contiguous buffers far larger than CMA must succeed;
 * without the IOMMU they fail beyond what CMA can provide. Every buffer is
 * mmapped, written and read back to check that it is real.
 *
 * Usage: rknpu_bigalloc [/dev/dri/renderD129] size_MiB[c] ...
 *   "c" suffix: request a contiguous buffer (RKNPU_MEM_CONTIGUOUS),
 *   otherwise non-contiguous (RKNPU_MEM_NON_CONTIGUOUS). Buffers are kept
 *   until the end, so the sizes add up.
 *
 * Build: gcc -O2 -Wall -o rknpu_bigalloc tests/rknpu_bigalloc.c
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define DRM_IOCTL_BASE 'd'
#define DRM_COMMAND_BASE 0x40
#define DRM_IOWR(nr, type) _IOWR(DRM_IOCTL_BASE, nr, type)

struct rknpu_mem_create {
	uint32_t handle;
	uint32_t flags;
	uint64_t size;
	uint64_t obj_addr;
	uint64_t dma_addr;
	uint64_t sram_size;
	int32_t iommu_domain_id;
	uint32_t core_mask;
};

struct rknpu_mem_map {
	uint32_t handle;
	uint32_t reserved;
	uint64_t offset;
};

struct rknpu_mem_destroy {
	uint32_t handle;
	uint32_t reserved;
	uint64_t obj_addr;
};

#define RKNPU_MEM_CONTIGUOUS 0
#define RKNPU_MEM_NON_CONTIGUOUS (1 << 0)
#define RKNPU_MEM_CACHEABLE (1 << 1)

#define DRM_IOCTL_RKNPU_MEM_CREATE \
	DRM_IOWR(DRM_COMMAND_BASE + 0x02, struct rknpu_mem_create)
#define DRM_IOCTL_RKNPU_MEM_MAP \
	DRM_IOWR(DRM_COMMAND_BASE + 0x03, struct rknpu_mem_map)
#define DRM_IOCTL_RKNPU_MEM_DESTROY \
	DRM_IOWR(DRM_COMMAND_BASE + 0x04, struct rknpu_mem_destroy)

struct buf {
	struct rknpu_mem_create c;
	void *va;
};

static double now(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

int main(int argc, char **argv)
{
	const char *path = "/dev/dri/renderD129";
	struct buf bufs[32];
	int nbuf = 0, fd, i, failed = 0;
	uint64_t total = 0;

	i = 1;
	if (argc > 1 && argv[1][0] == '/')
		path = argv[i++];

	fd = open(path, O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		perror(path);
		return 1;
	}

	for (; i < argc && nbuf < 32; i++) {
		char *end;
		uint64_t mb = strtoull(argv[i], &end, 10);
		int contig = (*end == 'c');
		struct buf *b = &bufs[nbuf];
		struct rknpu_mem_map m = { 0 };
		uint64_t *p, n, k, bad = 0;
		double t0;

		memset(b, 0, sizeof(*b));
		b->c.size = mb << 20;
		b->c.flags = RKNPU_MEM_CACHEABLE |
			     (contig ? RKNPU_MEM_CONTIGUOUS :
				       RKNPU_MEM_NON_CONTIGUOUS);
		t0 = now();
		if (ioctl(fd, DRM_IOCTL_RKNPU_MEM_CREATE, &b->c) < 0) {
			printf("%6llu MiB %-14s: MEM_CREATE failed (%s)\n",
			       (unsigned long long)mb,
			       contig ? "contiguous" : "non-contiguous",
			       strerror(errno));
			failed++;
			continue;
		}
		m.handle = b->c.handle;
		if (ioctl(fd, DRM_IOCTL_RKNPU_MEM_MAP, &m) < 0) {
			printf("%6llu MiB: MEM_MAP failed (%s)\n",
			       (unsigned long long)mb, strerror(errno));
			failed++;
			continue;
		}
		b->va = mmap(NULL, b->c.size, PROT_READ | PROT_WRITE,
			     MAP_SHARED, fd, m.offset);
		if (b->va == MAP_FAILED) {
			printf("%6llu MiB: mmap failed (%s)\n",
			       (unsigned long long)mb, strerror(errno));
			failed++;
			continue;
		}
		p = b->va;
		n = b->c.size / sizeof(*p);
		for (k = 0; k < n; k++)
			p[k] = k ^ 0x5a5a5a5a5a5a5a5aULL ^ ((uint64_t)nbuf << 56);
		for (k = 0; k < n; k++)
			if (p[k] != (k ^ 0x5a5a5a5a5a5a5a5aULL ^
				     ((uint64_t)nbuf << 56)))
				bad++;
		total += b->c.size;
		printf("%6llu MiB %-14s: ok, flags=0x%x iova=0x%llx, %s, %.2f s (total %llu MiB)\n",
		       (unsigned long long)mb,
		       contig ? "contiguous" : "non-contiguous", b->c.flags,
		       (unsigned long long)b->c.dma_addr,
		       bad ? "READ-BACK ERRORS" : "read-back ok",
		       now() - t0, (unsigned long long)(total >> 20));
		if (bad)
			failed++;
		nbuf++;
	}

	for (i = 0; i < nbuf; i++) {
		struct rknpu_mem_destroy d = { .handle = bufs[i].c.handle,
					       .obj_addr = bufs[i].c.obj_addr };

		if (bufs[i].va && bufs[i].va != MAP_FAILED)
			munmap(bufs[i].va, bufs[i].c.size);
		if (ioctl(fd, DRM_IOCTL_RKNPU_MEM_DESTROY, &d) < 0)
			printf("MEM_DESTROY %u failed (%s)\n", d.handle,
			       strerror(errno));
	}
	close(fd);
	printf("%s\n", failed ? "FAIL" : "PASS");
	return failed ? 1 : 0;
}
