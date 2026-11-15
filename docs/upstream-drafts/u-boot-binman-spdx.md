# DRAFT, not sent: u-boot report on the SPDX tag of lib/binman.c and include/binman.h

For Dale to review and send (or not) under his own name. Drafted by Deep Research, 2026-11-15, from the u-boot
source at v2026.10 (`5508406`) and the raw files at older tags. **Before sending:** search lore for an existing report
or patch (<https://lore.kernel.org/u-boot/?q=binman.c+SPDX> and `?q=%22License-Identifier%3A+Intel%22`; not reachable
from this environment without approval), and re-check the files on u-boot `master`.

- **To:** u-boot@lists.denx.de
- **Cc:** Simon Glass <sjg@chromium.org> (author of both files; BINMAN maintainer), Tom Rini <trini@konsulko.com>
- **Subject:** `binman: SPDX tag "Intel" on lib/binman.c and include/binman.h?`

```
Hi Simon,

lib/binman.c and include/binman.h carry

    SPDX-License-Identifier: Intel

but their headers say "Copyright 2019 Google LLC, Written by Simon Glass", and the
rest of binman (tools/binman/*.py) is GPL-2.0+. The tag has been there since the
files were added (present in v2020.04, not in v2020.01) and is unchanged in
v2026.10.

"Intel" is not an identifier on the SPDX licence list and has no text in
Licenses/; in-tree it otherwise marks Intel-released x86 code (arch/x86/cpu/quark,
the FSP configs). So it looks like a copy-paste slip rather than an intended
licence.

We noticed it while generating licence notices for a board that enables
CONFIG_BINMAN_FDT, which compiles lib/binman.c into u-boot proper. Was GPL-2.0+
intended? If so, would you send (or ack) a patch changing both tags? Only the
copyright holder can confirm the licence, so we haven't sent a patch ourselves.

Thanks,
Dale
```

Notes for Dale:
- Plain text, no attachments, wrapped at 72–80 columns (u-boot list conventions).
- Disclosure: this draft was written with an AI assistant (Claude). If you send it, you can add a line saying so;
  it is a question, not a patch, so no `Signed-off-by` or coding-assistants trailer is required.
- If Simon confirms GPL-2.0+, the flag in `tools/bootloader_notices.py` (`KNOWN_FLAGS`) can go once we move to a
  u-boot release with the fix; until then the notices reproduce the files' headers verbatim.
