# The ShellOS kernel

Linux **6.18 LTS** (currently 6.18.58), built from kernel.org sources with
Clang, starting from Debian's own 6.18 config and tuned for one machine: a
12th–14th gen Intel Core i5 (Alder/Raptor Lake, hybrid P/E cores) running a
COSMIC desktop.

Everything here is reversible at boot. The Limine menu's **safe mode** entry
turns mitigations back on, switches to the stock TEO idle governor and
disables the sched_ext scheduler.

| Layer | What ShellOS does | Where |
|---|---|---|
| Codegen | Clang ThinLTO, `-march=alderlake`, **AutoFDO + Propeller from your own usage** | `kernel/build.sh`, `shellos-kernel-profile` |
| CPU scheduling | EEVDF + **BORE**, **POC** idle-CPU selector, **sched_ext** running **scx_lavd** | `kernel/patches/`, `shellos-scx.service` |
| Idle | **NAP**, an online-learning neural cpuidle governor (TEO fallback) | `kernel/patches/0003-*` |
| Timers & preemption | 1000 Hz, full preemption (dynamic), tickless idle | `kernel/config/shellos.config` |
| Memory | MGLRU + thrash protection, zram lz4 → **zstd idle recompression**, **TMO-style proactive reclaim** | `shellos-tuning` |
| I/O, network | per-device I/O schedulers, BBR + fq | `shellos-tuning` |

---

## 1. Personal profile-guided optimisation (AutoFDO + Propeller)

Compilers guess which branches are hot. Feeding them a profile of how the code
*actually* runs lets them lay out hot paths contiguously, inline the right
calls and move cold code out of the way. Google reported **up to ~10%** kernel
throughput gains from doing this to their fleet's kernels.

* **AutoFDO**: Chen, Li, Moseley, *"AutoFDO: Automatic Feedback-Directed
  Optimization for Warehouse-Scale Applications"*, CGO 2016. It samples the
  CPU's Last Branch Record (LBR) in production instead of using instrumented
  builds, so profiling costs almost nothing.
* **Propeller**: Shen et al., *"Propeller: A Profile Guided, Relinking
  Optimizer for Warehouse-Scale Applications"*, ASPLOS 2023. It is a
  post-link-style basic-block layout optimiser, done in the compiler and linker
  so it scales to kernel-sized binaries (cf. BOLT, Panchenko et al., CGO 2019).

Both landed upstream in Linux 6.13 (`CONFIG_AUTOFDO_CLANG`,
`CONFIG_PROPELLER_CLANG`). The novel part in ShellOS is the **loop**: the
profile comes from *your* machine and *your* workload, not a benchmark.

```
 stage 0  6.18.58-shellos            built with profiling metadata, no profile
            │  shellos-kernel-profile -r ~/src/Shell   (sample ~10 min of normal use)
            ▼  commits kernel/profiles/kernel.afdo → push → CI rebuilds
 stage 1  6.18.58-shellos-afdo       AutoFDO-optimised
            │  shellos-kernel-profile -r ~/src/Shell   (sample again)
            ▼  commits kernel/profiles/propeller_{cc,ld}_profile.txt → CI rebuilds
 stage 2  6.18.58-shellos-afdo-prop  AutoFDO + Propeller
```

`uname -r` tells you the stage, and the tool picks the next one
automatically. Sampling uses `br_inst_retired.near_taken` with the LBR stack.
On hybrid Alder Lake perf opens it on both the P-core (`cpu_core`) and E-core
(`cpu_atom`) PMUs. Samples are mapped back through the kernel's debug info,
which CI publishes as a GitHub release because it is too large for the apt
repo. Conversion uses `llvm-profgen` (AutoFDO) and `create_llvm_prof` from
google/autofdo v0.30.1 (Propeller), which ShellOS packages as `shellos-autofdo`.

Re-profile after big kernel updates. A stale profile still helps, just less.

`-march=alderlake` (in `kernel/MARCH`) lets the compiler schedule for Golden
Cove/Gracemont and use their integer ISA extensions (BMI2, ADX, MOVBE …). The
kernel's own `-mno-sse/-mno-avx` still keep FP/SIMD state out of normal kernel
code. `-march=native` isn't usable because CI compiles on a different CPU.

## 2. CPU scheduling

**EEVDF** (Stoica & Abdel-Wahab, *"Earliest Eligible Virtual Deadline First"*,
1995) has been Linux's fair scheduler since 6.6. ShellOS layers three things
on it:

* **BORE 7.0.0** (Burst-Oriented Response Enhancer, Masahito Suzuki) tracks
  each task's *burst time*, meaning how long it runs before sleeping, and
  scales its weight so short-burst interactive tasks (compositor, input,
  audio, terminal) win over long CPU hogs. It degrades gracefully to plain
  EEVDF. Tunable in `/proc/sys/kernel/sched_bore*`.
* **POC selector v2.1.0** (Piece-Of-Cake) replaces `select_idle_cpu()`'s
  linear scan with cached per-LLC idle bitmasks, an idea borrowed from the
  `scx_cake` BPF scheduler. Wakeups find an idle core with a bitmap lookup
  instead of walking the whole LLC.
* **sched_ext + scx_lavd.** sched_ext (6.12) lets a BPF program *be* the
  scheduler and swap it at runtime. ShellOS runs **LAVD**
  (Latency-criticality Aware Virtual Deadline; Changwoo Min, Igalia, built for
  Valve's Steam Deck, presented at Linux Plumbers 2024). LAVD infers *latency
  criticality* from the task wake/wait graph: a task that wakes many others and
  is woken by many is on a critical path, so it gets a tighter virtual
  deadline. Its **core compaction** keeps light loads on the efficient cores
  of a hybrid CPU, which makes it a strong fit for Alder Lake. `--autopower`
  follows the power profile from COSMIC's applet.

If LAVD ever exits or crashes, the kernel instantly falls back to EEVDF+BORE.
That is sched_ext's safety design. To switch schedulers, edit
`/etc/default/shellos-scx` (scx_bpfland, scx_flash, scx_cosmos and scx_rusty
are installed too). To use only BORE, run `systemctl disable --now shellos-scx`.

Also: **1000 Hz** tick, **full preemption** (`PREEMPT_DYNAMIC`, so
`preempt=lazy` still works from the cmdline), **tickless idle**
(`NO_HZ_IDLE`, not `NO_HZ_FULL`, whose syscall-entry overhead only pays off
with isolated cores), `SCHED_MC_PRIO`/ITMT plus `INTEL_HFI_THERMAL` so the
scheduler sees Intel Thread Director's per-core performance and efficiency
hints, `NR_CPUS=64` and no NUMA balancing (single socket).

## 3. Idle: NAP, a neural cpuidle governor

Choosing a C-state is a prediction problem: "how long until the next wakeup?".
Sleep too shallow and you waste power. Sleep too deep and you pay exit latency.
Upstream governors use heuristics: *menu* uses correction factors and *TEO*
(Rafael Wysocki) matches against timer events. **NAP** (Neural Adaptive
Predictor v0.5.0, Masahito Suzuki) uses a tiny **16→16→10 MLP**. Its weights
start from the hardware's idle-state table and are refined **online by
deferred back-propagation (SGD)** as it observes real sleep durations. Inference
uses AVX2 when available, which Alder Lake has. It is experimental, so:

* the normal boot uses `cpuidle.governor=nap`
* **safe mode** uses `cpuidle.governor=teo`
* switch live with
  `echo teo | sudo tee /sys/devices/system/cpu/cpuidle/current_governor`

## 4. Memory

* **MGLRU** (multi-generational LRU, Yu Zhao, 6.1) is on, with
  `min_ttl_ms=1000`: the working set of the last second is never evicted. Under
  real exhaustion the kernel OOM-kills instead of thrashing, and
  **systemd-oomd** acts even earlier on PSI.
* **zram swap, two-tier.** zram is the size of RAM, with **lz4** for every page
  swapped out (fast). `shellos-zram-recompress.timer` marks pages untouched for
  10 minutes as idle and **recompresses them with zstd**
  (`CONFIG_ZRAM_MULTI_COMP`, Sergey Senozhatsky, 6.2). That keeps the hot path
  fast and makes cold storage dense, the same trick Android and ChromeOS use.
  `vm.swappiness=180` and `page-cluster=0` tell the kernel zram is cheap.
* **shellos-senpai: proactive reclaim** modelled on Meta's **TMO**
  (Weiner et al., *"TMO: Transparent Memory Offloading in Datacenters"*,
  ASPLOS 2022, built on PSI, the pressure-stall information Weiner added in
  4.20). Every 6 s it reads each cgroup's memory stall time. While stalls stay
  below 0.1% of wall time it writes a small amount (0.05% of usage, at most
  64 MiB) to `memory.reclaim`. MGLRU picks the coldest pages, they land
  compressed in zram, and the RAM they used becomes page cache for whatever you
  open next. The step shrinks linearly as stalls approach the target, so it
  never fights a busy workload. It backs off completely under system-wide
  pressure or when zram is nearly full. Tune it in `/etc/default/shellos-senpai`
  and preview with `-n` (dry run).
* **THP** on `madvise` with background defrag: huge pages where apps ask for
  them, without fault-time compaction stalls.

## 5. I/O and network

* I/O schedulers by device type (udev): NVMe → `none`, SATA SSD →
  `mq-deadline`, HDD → `bfq` (Valente & Checconi, budget fair queueing).
* **BBR** congestion control (Cardwell et al., *"BBR: Congestion-Based
  Congestion Control"*, ACM Queue 2016) with the `fq` qdisc, plus TCP Fast Open
  and MTU probing.

## 6. Your trade-offs

* **`mitigations=off`**, as you chose. Spectre/Meltdown-class mitigations are
  disabled at boot, which is worth ~2–15% in syscall/context-switch heavy
  work. The risk is real (browsers run untrusted JavaScript). Safe mode turns
  them back on, and removing it from `SHELLOS_CMDLINE` in
  `/etc/default/shellos-boot` makes that permanent.
* `kernel.split_lock_mitigate=0`, `nmi_watchdog=0`, `nowatchdog`: fewer
  interrupts and no split-lock penalty for games.

## Not included (yet), and why

* **BBRv3**: the CachyOS port targets ≤6.14 and doesn't apply to 6.18.
  Porting it is real work for a small desktop gain.
* **Reflex cpufreq governor**: needs `intel_pstate=passive`. On HWP-capable
  Alder Lake, the hardware's own P-state control with EPP is generally better.
* **Full `-march=native`**: impossible in CI. `alderlake` is the same ISA.

## Patch provenance

`kernel/patches/series` lists each patch with its upstream URL and commit.
`kernel/build.sh` applies them with `--fuzz=0` (no silent misapplication), and
verifies that **all 53 pinned config options** in `kernel/config/shellos.config`
survive `olddefconfig`, failing the build if Kconfig drops any.
