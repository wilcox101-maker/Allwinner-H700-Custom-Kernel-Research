// SPDX-License-Identifier: GPL-2.0-only
/*
 * oskprobe: device probe for the global on-screen keyboard (Redux OSK plan D5, checks K24-K28).
 * Kernel Research KR-1, 2026-11-18. Static aarch64 tool for the stock RG34XXSP kernel 4.9.170.
 *
 * Safety (Redux Owner letter FROM-REDUX-OWNER-2026-11-18-s):
 *  - writes no file, card or partition (output goes to stdout only);
 *  - the only display change is one layer on disp0 channel 2 or 3 (default 3), layer 0;
 *    channels 0 and 1 are refused; `oskprobe off` clears the layer;
 *  - `type` creates a uinput keyboard that can send only the letters a-z;
 *  - `grab` takes EVIOCGRAB on ANBERNIC-keys and releases it at once.
 *
 * Subcommands:
 *   layers          screen size, /sys/class/disp/disp/attr listing and its `sys` dump, HDMI state     (K24)
 *   nodes           /dev/uinput, /dev/ion, /dev/disp, /sys/class/misc/uinput/dev, input devices      (K25)
 *   bar [SECONDS]   half-transparent test bar on chN/l0, zorder Z, for SECONDS (default 10), then off   (K26)
 *   off             disable chN/l0                                                                        (K26)
 *   keys [SECONDS]  print key events from ANBERNIC-keys and event0 for SECONDS (default 20), no grab    (K27)
 *   type WORD       after 5 s, type WORD (letters a-z only, max 32) through a uinput keyboard          (K27)
 *   grab            try EVIOCGRAB on ANBERNIC-keys, release at once; EBUSY = another program grabs it  (K28)
 *   version         build information
 * Options (before the subcommand): --ch 2|3 (default 3), --z ZORDER (default 30), --h HEIGHT (bar, default 120)
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>
#include <linux/input.h>
#include <linux/uinput.h>

#include "sunxi_disp2_abi.h"

#ifndef OSKPROBE_VERSION
#define OSKPROBE_VERSION "dev"
#endif

#define ION_IOC_ALLOC_LEGACY _IOWR('I', 0, struct ion_allocation_data_legacy)
#define ION_IOC_FREE_LEGACY  _IOWR('I', 1, struct ion_handle_data_legacy)
#define ION_IOC_SHARE_LEGACY _IOWR('I', 4, struct ion_fd_data_legacy)
#define ION_IOC_ALLOC_NEW    _IOWR('I', 0, struct ion_allocation_data_new)

static int g_ch = 3, g_z = 30, g_h = 120;
static volatile sig_atomic_t g_stop;

static double now_s(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

static void say(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	vprintf(fmt, ap);
	va_end(ap);
	fflush(stdout);
}

static void cat_file(const char *path)
{
	char buf[4096];
	int fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0) {
		say("  %s: %s\n", path, strerror(errno));
		return;
	}
	say("----- %s -----\n", path);
	for (;;) {
		ssize_t n = read(fd, buf, sizeof buf);
		if (n <= 0)
			break;
		fwrite(buf, 1, (size_t)n, stdout);
	}
	close(fd);
	say("\n----- end %s -----\n", path);
}

static int read_int_file(const char *path, int *out)
{
	char buf[32] = { 0 };
	int fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return -1;
	ssize_t n = read(fd, buf, sizeof buf - 1);
	close(fd);
	if (n <= 0)
		return -1;
	*out = atoi(buf);
	return 0;
}

static int hdmi_state(void)
{
	int v;
	if (read_int_file("/sys/class/extcon/hdmi/state", &v) == 0)
		return v;
	if (read_int_file("/sys/class/switch/hdmi/state", &v) == 0)
		return v;
	return -1;
}

/* ---------------- /dev/disp ---------------- */

static int disp_open(void)
{
	int fd = open("/dev/disp", O_RDWR | O_CLOEXEC);
	if (fd < 0)
		say("open /dev/disp: %s\n", strerror(errno));
	return fd;
}

static void screen_size(int disp, unsigned *w, unsigned *h)
{
	unsigned long arg[4] = { 0, 0, 0, 0 };
	int rw = ioctl(disp, DISP_GET_SCN_WIDTH, arg);
	int rh = ioctl(disp, DISP_GET_SCN_HEIGHT, arg);
	*w = rw > 0 ? (unsigned)rw : 0;
	*h = rh > 0 ? (unsigned)rh : 0;
}

static int layer_commit(int disp, struct disp_layer_config2 *cfg)
{
	unsigned long arg[4] = { 0, (unsigned long)cfg, 1, 0 };
	int r = ioctl(disp, DISP_LAYER_SET_CONFIG2, arg);
	if (r < 0)
		say("SET_CONFIG2 ch%u/l%u enable=%d: %s\n", cfg->channel, cfg->layer_id, cfg->enable, strerror(errno));
	return r;
}

static int layer_off(int disp)
{
	struct disp_layer_config2 cfg;
	memset(&cfg, 0, sizeof cfg);
	cfg.enable = false;
	cfg.channel = (uint32_t)g_ch;
	cfg.layer_id = 0;
	int r = layer_commit(disp, &cfg);
	if (r == 0)
		say("layer ch%d/l0: off\n", g_ch);
	return r;
}

/* ---------------- ION ---------------- */

static int ion_buffer_fd(size_t len)
{
	int ion = open("/dev/ion", O_RDONLY | O_CLOEXEC);
	if (ion < 0) {
		say("open /dev/ion: %s\n", strerror(errno));
		return -1;
	}
	struct ion_allocation_data_legacy a = { .len = len, .align = 4096, .heap_id_mask = 1, .flags = 0, .handle = 0 };
	if (ioctl(ion, ION_IOC_ALLOC_LEGACY, &a) == 0) {
		struct ion_fd_data_legacy s = { .handle = a.handle, .fd = -1 };
		int r = ioctl(ion, ION_IOC_SHARE_LEGACY, &s);
		struct ion_handle_data_legacy f = { .handle = a.handle };
		ioctl(ion, ION_IOC_FREE_LEGACY, &f); /* the dma-buf fd keeps the buffer */
		close(ion);
		if (r < 0) {
			say("ION share: %s\n", strerror(errno));
			return -1;
		}
		say("ION: legacy ABI, heap mask 1, %zu bytes, dma-buf fd %d\n", len, s.fd);
		return s.fd;
	}
	int e1 = errno;
	struct ion_allocation_data_new n = { .len = len, .heap_id_mask = 1, .flags = 0, .fd = 0, .unused = 0 };
	if (ioctl(ion, ION_IOC_ALLOC_NEW, &n) == 0) {
		close(ion);
		say("ION: new ABI (legacy failed: %s), heap mask 1, %zu bytes, dma-buf fd %u\n", strerror(e1), len, n.fd);
		return (int)n.fd;
	}
	say("ION alloc failed: legacy %s, new %s\n", strerror(e1), strerror(errno));
	close(ion);
	return -1;
}

/* ---------------- subcommands ---------------- */

static int cmd_layers(void)
{
	int disp = disp_open();
	if (disp >= 0) {
		unsigned w, h;
		screen_size(disp, &w, &h);
		say("screen 0: %u x %u\n", w, h);
		close(disp);
	}
	say("hdmi state: %d\n", hdmi_state());
	DIR *d = opendir("/sys/class/disp/disp/attr");
	if (!d) {
		say("/sys/class/disp/disp/attr: %s\n", strerror(errno));
	} else {
		struct dirent *e;
		say("----- ls /sys/class/disp/disp/attr -----\n");
		while ((e = readdir(d)) != NULL) {
			if (e->d_name[0] == '.')
				continue;
			char p[512];
			struct stat st;
			snprintf(p, sizeof p, "/sys/class/disp/disp/attr/%s", e->d_name);
			if (stat(p, &st) == 0)
				say("  %04o %s\n", st.st_mode & 07777, e->d_name);
			else
				say("  ? %s\n", e->d_name);
		}
		closedir(d);
	}
	cat_file("/sys/class/disp/disp/attr/sys");
	return 0;
}

static void node_line(const char *path)
{
	struct stat st;
	if (stat(path, &st) != 0) {
		say("  %-28s missing (%s)\n", path, strerror(errno));
		return;
	}
	int fd = open(path, O_RDWR | O_CLOEXEC | O_NONBLOCK);
	int e = errno;
	say("  %-28s mode %04o uid %u gid %u dev %u:%u open-rw: %s\n", path, st.st_mode & 07777, st.st_uid, st.st_gid,
	    major(st.st_rdev), minor(st.st_rdev), fd >= 0 ? "ok" : strerror(e));
	if (fd >= 0)
		close(fd);
}

static int find_input(const char *want, char *path_out, size_t cap)
{
	for (int i = 0; i < 32; i++) {
		char p[64], name[128] = { 0 };
		snprintf(p, sizeof p, "/dev/input/event%d", i);
		int fd = open(p, O_RDONLY | O_CLOEXEC | O_NONBLOCK);
		if (fd < 0)
			continue;
		ioctl(fd, EVIOCGNAME(sizeof name - 1), name);
		close(fd);
		if (strcmp(name, want) == 0) {
			snprintf(path_out, cap, "%s", p);
			return 0;
		}
	}
	return -1;
}

static int cmd_nodes(void)
{
	say("device nodes (uid %u):\n", (unsigned)getuid());
	node_line("/dev/uinput");
	node_line("/dev/ion");
	node_line("/dev/disp");
	node_line("/dev/fb0");
	cat_file("/sys/class/misc/uinput/dev");
	say("input devices:\n");
	for (int i = 0; i < 32; i++) {
		char p[64], name[128] = { 0 };
		snprintf(p, sizeof p, "/dev/input/event%d", i);
		int fd = open(p, O_RDONLY | O_CLOEXEC | O_NONBLOCK);
		if (fd < 0)
			continue;
		ioctl(fd, EVIOCGNAME(sizeof name - 1), name);
		close(fd);
		say("  %-20s %s\n", p, name);
	}
	return 0;
}

static void on_signal(int sig)
{
	(void)sig;
	g_stop = 1;
}

static int cmd_bar(int seconds)
{
	int disp = disp_open();
	if (disp < 0)
		return 1;
	unsigned sw, sh;
	screen_size(disp, &sw, &sh);
	if (sw == 0 || sh == 0) {
		say("screen size unknown (%u x %u); using 720 x 480\n", sw, sh);
		sw = 720;
		sh = 480;
	}
	unsigned w = sw, h = (unsigned)g_h;
	if (h > sh)
		h = sh;
	size_t len = ((size_t)w * h * 4 + 4095) & ~(size_t)4095;
	int buf = ion_buffer_fd(len);
	if (buf < 0) {
		close(disp);
		return 1;
	}
	uint32_t *px = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_SHARED, buf, 0);
	if (px == MAP_FAILED) {
		say("mmap dma-buf: %s\n", strerror(errno));
		close(buf);
		close(disp);
		return 1;
	}
	/* ARGB8888: 8 vertical colour bars at alpha 0x80, opaque white 2-px border */
	static const uint32_t bars[8] = { 0xffffff, 0xffff00, 0x00ffff, 0x00ff00, 0xff00ff, 0xff0000, 0x0000ff, 0x000000 };
	for (unsigned y = 0; y < h; y++)
		for (unsigned x = 0; x < w; x++) {
			uint32_t c = 0x80000000u | bars[(x * 8) / w];
			if (x < 2 || y < 2 || x >= w - 2 || y >= h - 2)
				c = 0xffffffffu;
			px[(size_t)y * w + x] = c;
		}
	msync(px, len, MS_SYNC);

	struct sigaction sa;
	memset(&sa, 0, sizeof sa);
	sa.sa_handler = on_signal;
	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGHUP, &sa, NULL);

	struct disp_layer_config2 cfg;
	memset(&cfg, 0, sizeof cfg);
	cfg.info.mode = LAYER_MODE_BUFFER;
	cfg.info.zorder = (uint8_t)g_z;
	cfg.info.alpha_mode = 0;
	cfg.info.alpha_value = 0xff;
	cfg.info.screen_win.x = 0;
	cfg.info.screen_win.y = (int32_t)(sh - h);
	cfg.info.screen_win.width = w;
	cfg.info.screen_win.height = h;
	cfg.info.fb.fd = buf;
	for (int i = 0; i < 3; i++) {
		cfg.info.fb.size[i].width = w;
		cfg.info.fb.size[i].height = h;
	}
	cfg.info.fb.format = DISP_FORMAT_ARGB_8888;
	cfg.info.fb.color_space = DISP_BT601;
	cfg.info.fb.pre_multiply = false;
	cfg.info.fb.crop.width = (int64_t)w << 32;
	cfg.info.fb.crop.height = (int64_t)h << 32;
	cfg.info.fb.flags = DISP_BF_NORMAL;
	cfg.info.fb.scan = DISP_SCAN_PROGRESSIVE;
	cfg.enable = true;
	cfg.channel = (uint32_t)g_ch;
	cfg.layer_id = 0;
	if (layer_commit(disp, &cfg) < 0) {
		munmap(px, len);
		close(buf);
		close(disp);
		return 1;
	}
	say("bar on: ch%d/l0 zorder %d, %u x %u at y=%u on %u x %u, pid %d, %d s\n", g_ch, g_z, w, h, sh - h, sw, sh,
	    (int)getpid(), seconds);
	double t0 = now_s();
	int last_hdmi = hdmi_state();
	unsigned lw = sw, lh = sh;
	while (!g_stop && now_s() - t0 < seconds) {
		sleep(1);
		int hs = hdmi_state();
		unsigned cw, ch;
		screen_size(disp, &cw, &ch);
		say("  t=%5.1f s hdmi=%d screen=%u x %u%s\n", now_s() - t0, hs, cw, ch,
		    (hs != last_hdmi || cw != lw || ch != lh) ? "  <- changed" : "");
		last_hdmi = hs;
		lw = cw;
		lh = ch;
	}
	if (g_stop)
		say("signal received\n");
	layer_off(disp);
	munmap(px, len);
	close(buf);
	close(disp);
	return 0;
}

static int cmd_off(void)
{
	int disp = disp_open();
	if (disp < 0)
		return 1;
	int r = layer_off(disp);
	close(disp);
	return r < 0 ? 1 : 0;
}

static const char *key_name(unsigned code)
{
	switch (code) {
	case KEY_UP: return "KEY_UP";
	case KEY_DOWN: return "KEY_DOWN";
	case KEY_LEFT: return "KEY_LEFT";
	case KEY_RIGHT: return "KEY_RIGHT";
	case KEY_VOLUMEUP: return "KEY_VOLUMEUP";
	case KEY_VOLUMEDOWN: return "KEY_VOLUMEDOWN";
	case KEY_POWER: return "KEY_POWER";
	case KEY_INSERT: return "KEY_INSERT";
	case KEY_DELETE: return "KEY_DELETE";
	case BTN_SOUTH: return "BTN_SOUTH";
	case BTN_EAST: return "BTN_EAST";
	case BTN_C: return "BTN_C";
	case BTN_NORTH: return "BTN_NORTH";
	case BTN_WEST: return "BTN_WEST";
	case BTN_Z: return "BTN_Z";
	case BTN_TL: return "BTN_TL";
	case BTN_TR: return "BTN_TR";
	case BTN_TL2: return "BTN_TL2";
	case BTN_TR2: return "BTN_TR2";
	case BTN_SELECT: return "BTN_SELECT";
	case BTN_START: return "BTN_START";
	case BTN_MODE: return "BTN_MODE";
	case BTN_THUMBL: return "BTN_THUMBL";
	case BTN_THUMBR: return "BTN_THUMBR";
	default: return "";
	}
}

static int cmd_keys(int seconds)
{
	char pk[64] = "", pp[64] = "/dev/input/event0";
	if (find_input("ANBERNIC-keys", pk, sizeof pk) != 0)
		say("ANBERNIC-keys not found\n");
	struct pollfd fds[2];
	const char *names[2] = { pk, pp };
	int n = 0;
	for (int i = 0; i < 2; i++) {
		if (!names[i][0])
			continue;
		int fd = open(names[i], O_RDONLY | O_CLOEXEC | O_NONBLOCK);
		if (fd < 0) {
			say("open %s: %s\n", names[i], strerror(errno));
			continue;
		}
		fds[n].fd = fd;
		fds[n].events = POLLIN;
		names[n] = names[i];
		n++;
	}
	if (n == 0)
		return 1;
	say("reading %s%s%s for %d s (no grab). Press the chords now.\n", names[0], n > 1 ? " and " : "",
	    n > 1 ? names[1] : "", seconds);
	double t0 = now_s();
	while (now_s() - t0 < seconds) {
		int r = poll(fds, (nfds_t)n, 200);
		if (r <= 0)
			continue;
		for (int i = 0; i < n; i++) {
			if (!(fds[i].revents & POLLIN))
				continue;
			struct input_event ev;
			while (read(fds[i].fd, &ev, sizeof ev) == (ssize_t)sizeof ev) {
				if (ev.type == EV_SYN)
					continue;
				say("  t=%6.3f %-18s type %u code %3u value %6d %s\n", now_s() - t0, names[i], ev.type, ev.code,
				    ev.value, ev.type == EV_KEY ? key_name(ev.code) : (ev.type == EV_ABS ? "(abs)" : ""));
			}
		}
	}
	for (int i = 0; i < n; i++)
		close(fds[i].fd);
	return 0;
}

static const int letter_key[26] = {
	KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_I, KEY_J, KEY_K, KEY_L, KEY_M,
	KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R, KEY_S, KEY_T, KEY_U, KEY_V, KEY_W, KEY_X, KEY_Y, KEY_Z,
};

static void emit(int fd, int type, int code, int value)
{
	struct input_event ev;
	memset(&ev, 0, sizeof ev);
	ev.type = (unsigned short)type;
	ev.code = (unsigned short)code;
	ev.value = value;
	if (write(fd, &ev, sizeof ev) != (ssize_t)sizeof ev)
		say("uinput write: %s\n", strerror(errno));
}

static int cmd_type(const char *word)
{
	size_t len = strlen(word);
	if (len == 0 || len > 32) {
		say("type: WORD must be 1-32 letters\n");
		return 2;
	}
	for (size_t i = 0; i < len; i++)
		if (word[i] < 'a' || word[i] > 'z') {
			say("type: only the letters a-z are allowed\n");
			return 2;
		}
	int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK | O_CLOEXEC);
	if (fd < 0) {
		say("open /dev/uinput: %s\n", strerror(errno));
		return 1;
	}
	ioctl(fd, UI_SET_EVBIT, EV_KEY);
	for (int i = 0; i < 26; i++)
		ioctl(fd, UI_SET_KEYBIT, letter_key[i]);
	struct uinput_user_dev ud;
	memset(&ud, 0, sizeof ud);
	snprintf(ud.name, sizeof ud.name, "oskprobe-letters");
	ud.id.bustype = BUS_VIRTUAL;
	ud.id.vendor = 0x0001;
	ud.id.product = 0x0001;
	ud.id.version = 1;
	if (write(fd, &ud, sizeof ud) != (ssize_t)sizeof ud || ioctl(fd, UI_DEV_CREATE) < 0) {
		say("uinput create: %s\n", strerror(errno));
		close(fd);
		return 1;
	}
	say("uinput keyboard 'oskprobe-letters' created; typing \"%s\" in 5 s (focus the app now)\n", word);
	sleep(5);
	for (size_t i = 0; i < len; i++) {
		int k = letter_key[word[i] - 'a'];
		emit(fd, EV_KEY, k, 1);
		emit(fd, EV_SYN, SYN_REPORT, 0);
		usleep(40000);
		emit(fd, EV_KEY, k, 0);
		emit(fd, EV_SYN, SYN_REPORT, 0);
		usleep(80000);
	}
	say("typed %zu letters\n", len);
	sleep(1);
	ioctl(fd, UI_DEV_DESTROY);
	close(fd);
	say("uinput keyboard removed\n");
	return 0;
}

static int cmd_grab(void)
{
	char p[64];
	if (find_input("ANBERNIC-keys", p, sizeof p) != 0) {
		say("ANBERNIC-keys not found\n");
		return 1;
	}
	int fd = open(p, O_RDONLY | O_CLOEXEC | O_NONBLOCK);
	if (fd < 0) {
		say("open %s: %s\n", p, strerror(errno));
		return 1;
	}
	int r = ioctl(fd, EVIOCGRAB, 1);
	int e = errno;
	if (r == 0) {
		ioctl(fd, EVIOCGRAB, 0);
		say("grab %s: OK (no other program holds a grab); released\n", p);
	} else {
		say("grab %s: %s%s\n", p, strerror(e), e == EBUSY ? " (another program holds a grab)" : "");
	}
	close(fd);
	return 0;
}

static void usage(void)
{
	say("usage: oskprobe [--ch 2|3] [--z ZORDER] [--h HEIGHT] layers|nodes|bar [S]|off|keys [S]|type WORD|grab|version\n");
}

int main(int argc, char **argv)
{
	int i = 1;
	setvbuf(stdout, NULL, _IOLBF, 0);
	for (; i + 1 < argc && strncmp(argv[i], "--", 2) == 0; i += 2) {
		int v = atoi(argv[i + 1]);
		if (strcmp(argv[i], "--ch") == 0) {
			if (v != 2 && v != 3) {
				say("--ch must be 2 or 3 (channels 0 and 1 belong to video and fb0)\n");
				return 2;
			}
			g_ch = v;
		} else if (strcmp(argv[i], "--z") == 0) {
			if (v < 0 || v > 255) {
				say("--z must be 0-255\n");
				return 2;
			}
			g_z = v;
		} else if (strcmp(argv[i], "--h") == 0) {
			if (v < 8 || v > 480) {
				say("--h must be 8-480\n");
				return 2;
			}
			g_h = v;
		} else {
			usage();
			return 2;
		}
	}
	if (i >= argc) {
		usage();
		return 2;
	}
	const char *c = argv[i];
	const char *a = i + 1 < argc ? argv[i + 1] : NULL;
	if (strcmp(c, "layers") == 0)
		return cmd_layers();
	if (strcmp(c, "nodes") == 0)
		return cmd_nodes();
	if (strcmp(c, "bar") == 0) {
		int s = a ? atoi(a) : 10;
		return cmd_bar(s > 0 && s <= 600 ? s : 10);
	}
	if (strcmp(c, "off") == 0)
		return cmd_off();
	if (strcmp(c, "keys") == 0) {
		int s = a ? atoi(a) : 20;
		return cmd_keys(s > 0 && s <= 600 ? s : 20);
	}
	if (strcmp(c, "type") == 0) {
		if (!a) {
			usage();
			return 2;
		}
		return cmd_type(a);
	}
	if (strcmp(c, "grab") == 0)
		return cmd_grab();
	if (strcmp(c, "version") == 0) {
		say("oskprobe %s (KR-1), disp_layer_config2 %zu bytes\n", OSKPROBE_VERSION, sizeof(struct disp_layer_config2));
		return 0;
	}
	usage();
	return 2;
}
