// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * shellos-senpai: pressure-driven proactive memory reclaim.
 *
 * A desktop-sized take on Meta's Senpai / TMO ("TMO: Transparent Memory
 * Offloading in Datacenters", Weiner et al., ASPLOS '22). Every interval we
 * look at how much time each cgroup spent stalled on memory (PSI). While
 * that stays under a tiny target, we ask the kernel to reclaim a small
 * slice of the cgroup via memory.reclaim. MGLRU picks the coldest pages,
 * which land compressed in zram, so the freed RAM becomes page cache and
 * headroom for whatever you open next. As soon as stalls approach the
 * target the step shrinks to zero, so reclaim never fights a workload.
 *
 * Usage: shellos-senpai [-i SECONDS] [-p PRESSURE_PCT] [-r RATIO]
 *                       [-m MAX_STEP_MB] [-w MIN_SWAP_FREE_PCT] [-n] CGROUP...
 *   -w  hold off while free swap is below this percentage (default 10)
 *   -n  dry run: log what would be reclaimed, write nothing
 */
#define _GNU_SOURCE
#include <errno.h>
#include <getopt.h>
#include <inttypes.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define MAX_CGROUPS 16
#define MIB (1024ULL * 1024ULL)

struct target {
	const char *path;
	uint64_t last_stall_us;
	bool primed;
};

static volatile sig_atomic_t stop;

static void on_signal(int sig)
{
	(void)sig;
	stop = 1;
}

/* Read the "some ... total=N" counter (microseconds) from a PSI file. */
static int read_stall_total(const char *file, uint64_t *out)
{
	char line[256];
	FILE *f = fopen(file, "re");
	int ret = -1;

	if (!f)
		return -1;
	while (fgets(line, sizeof(line), f)) {
		char *t;

		if (strncmp(line, "some ", 5) != 0)
			continue;
		t = strstr(line, "total=");
		if (t && sscanf(t + 6, "%" SCNu64, out) == 1)
			ret = 0;
		break;
	}
	fclose(f);
	return ret;
}

/* Read the "some avg10=X.XX" figure from a PSI file. */
static double read_avg10(const char *file)
{
	char line[256];
	double v = 0;
	FILE *f = fopen(file, "re");

	if (!f)
		return 0;
	while (fgets(line, sizeof(line), f)) {
		char *a;

		if (strncmp(line, "some ", 5) != 0)
			continue;
		a = strstr(line, "avg10=");
		if (a)
			v = strtod(a + 6, NULL);
		break;
	}
	fclose(f);
	return v;
}

static int read_u64(const char *file, uint64_t *out)
{
	FILE *f = fopen(file, "re");
	int ok;

	if (!f)
		return -1;
	ok = fscanf(f, "%" SCNu64, out) == 1;
	fclose(f);
	return ok ? 0 : -1;
}

/* Swap headroom in percent (0 if there is no swap at all). */
static double swap_free_pct(void)
{
	char key[64];
	uint64_t val, total = 0, avail = 0;
	FILE *f = fopen("/proc/meminfo", "re");

	if (!f)
		return 0;
	while (fscanf(f, "%63s %" SCNu64 " kB\n", key, &val) == 2) {
		if (!strcmp(key, "SwapTotal:"))
			total = val;
		else if (!strcmp(key, "SwapFree:"))
			avail = val;
	}
	fclose(f);
	return total ? 100.0 * (double)avail / (double)total : 0;
}

static void reclaim(const char *cg, uint64_t bytes, bool dry_run)
{
	char file[512];
	FILE *f;

	if (dry_run) {
		printf("%s: would reclaim %" PRIu64 " KiB\n", cg, bytes / 1024);
		return;
	}
	snprintf(file, sizeof(file), "%s/memory.reclaim", cg);
	f = fopen(file, "we");
	if (!f)
		return;
	/* EAGAIN just means the kernel found less to reclaim than asked. */
	fprintf(f, "%" PRIu64, bytes);
	if (fclose(f) != 0 && errno != EAGAIN)
		fprintf(stderr, "%s: memory.reclaim: %s\n", cg, strerror(errno));
}

static void usage(const char *argv0)
{
	fprintf(stderr,
		"usage: %s [-i SECONDS] [-p PRESSURE_PCT] [-r RATIO] [-m MAX_STEP_MB]\n"
		"       [-w MIN_SWAP_FREE_PCT] [-n] CGROUP...\n",
		argv0);
	exit(2);
}

int main(int argc, char **argv)
{
	double interval = 6.0;      /* seconds between probes          */
	double target_pct = 0.1;    /* tolerated stall time, % of wall */
	double ratio = 0.0005;      /* fraction of usage per step      */
	uint64_t max_step = 64 * MIB;
	double min_swap_free = 10.0;
	bool dry_run = false;
	struct target targets[MAX_CGROUPS];
	int ntargets = 0, opt;

	while ((opt = getopt(argc, argv, "i:p:r:m:w:nh")) != -1) {
		switch (opt) {
		case 'i': interval = strtod(optarg, NULL); break;
		case 'p': target_pct = strtod(optarg, NULL); break;
		case 'r': ratio = strtod(optarg, NULL); break;
		case 'm': max_step = strtoull(optarg, NULL, 10) * MIB; break;
		case 'w': min_swap_free = strtod(optarg, NULL); break;
		case 'n': dry_run = true; break;
		default: usage(argv[0]);
		}
	}
	if (optind >= argc || interval <= 0 || target_pct <= 0 || ratio <= 0)
		usage(argv[0]);
	for (; optind < argc && ntargets < MAX_CGROUPS; optind++)
		targets[ntargets++] = (struct target){ .path = argv[optind] };

	signal(SIGTERM, on_signal);
	signal(SIGINT, on_signal);
	setvbuf(stdout, NULL, _IOLBF, 0);

	while (!stop) {
		struct timespec ts = {
			.tv_sec = (time_t)interval,
			.tv_nsec = (long)((interval - (time_t)interval) * 1e9),
		};
		/* Back off entirely if the whole machine is under pressure or
		 * there is nowhere cheap left to put cold anonymous pages. */
		bool hold = read_avg10("/proc/pressure/memory") > target_pct * 10 ||
			    swap_free_pct() < min_swap_free;

		for (int i = 0; i < ntargets; i++) {
			struct target *t = &targets[i];
			char file[512];
			uint64_t stall, current;
			double pressure_pct, step;

			snprintf(file, sizeof(file), "%s/memory.pressure", t->path);
			if (read_stall_total(file, &stall) < 0)
				continue;
			if (!t->primed) {
				t->last_stall_us = stall;
				t->primed = true;
				continue;
			}
			pressure_pct = 100.0 * (double)(stall - t->last_stall_us) /
				       (interval * 1e6);
			t->last_stall_us = stall;
			if (hold || pressure_pct >= target_pct)
				continue;

			snprintf(file, sizeof(file), "%s/memory.current", t->path);
			if (read_u64(file, &current) < 0)
				continue;
			/* Scale the step down linearly as stalls approach target. */
			step = (double)current * ratio * (1.0 - pressure_pct / target_pct);
			if (step > (double)max_step)
				step = (double)max_step;
			if (step >= (double)MIB)
				reclaim(t->path, (uint64_t)step & ~4095ULL, dry_run);
		}
		nanosleep(&ts, NULL);
	}
	return 0;
}
