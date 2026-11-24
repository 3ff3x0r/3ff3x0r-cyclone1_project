# Vendor inventory

The root repository ignores `vendor/`. These pins identify the local upstream checkouts independently of the root Git index. Each origin and HEAD was checked locally. The MiST tree's `.gitmodules`, its T80 gitlink, and the nested checkout agree.

| Local tree | Upstream and exact revision | Use in this port | License at the pinned revision |
|---|---|---|---|
| `vendor/ZX_Spectrum-128K_MIST` | [sorgelig/ZX_Spectrum-128K_MIST](https://github.com/sorgelig/ZX_Spectrum-128K_MIST/tree/9713924d41865f3d5712f9daf8fbd9b0489f8697) · `9713924d41865f3d5712f9daf8fbd9b0489f8697` | Primary CPU integration, paging, ULA and peripheral donor | Root `LICENSE` contains GPLv2. File notices differ. `zxspectrum.sv`, `u765.sv` and `wd1793.sv` say GPL-2.0-or-later. `ula.sv` and `sdram.sv` say GPL-3.0-or-later. `ym2149.sv` carries a BSD-style notice covering source and synthesized forms. Preserve each notice and check the terms of the selected files as a set before distributing derivatives. |
| `vendor/ZX_Spectrum-128K_MIST/T80` | [mist-devel/T80](https://github.com/mist-devel/T80/tree/0e89c1826cf750630ff6bddd26b833882eb9823b) · `0e89c1826cf750630ff6bddd26b833882eb9823b` | Nested Git submodule. T80pa and its VHDL core dependencies | T80 `README` and VHDL headers carry BSD-style terms. Preserve the notice, conditions and disclaimer in source and reproduce them in the materials accompanying synthesized redistribution. The authors' and contributors' names require permission for endorsement. |
| `vendor/trhmsx` | [cristianoag/trhmsx](https://github.com/cristianoag/trhmsx/tree/f330fe7be308d1dbc701e790ec99c644e76e12fc) · `f330fe7be308d1dbc701e790ec99c644e76e12fc` | v1.51 production hardware reference under `hardware/trhmsx/` | Root README declares CC BY-NC-SA 4.0 for the project and explicitly restricts sales. The bundled `hardware/hidman-micro/firmware/LICENSE` contains GPLv3. Treat the firmware's own notices separately from the hardware files. The Spectrum wrapper uses board connectivity facts. |
| `vendor/ocm-pld-dev` | [gnogni/ocm-pld-dev](https://github.com/gnogni/ocm-pld-dev/tree/9392554e0a586fe47dfdcc03a1dba5c548396745) · `9392554e0a586fe47dfdcc03a1dba5c548396745` | `esemsx3` electrical and programming reference | Root `LICENSE` permits redistribution under notice and disclaimer conditions and restricts sale and commercial use absent written permission. Check component-specific terms separately. Use the QSF to corroborate pad assignments and derive new wrapper and constraints from board facts. |

Section 1 also names UnAmigaReloaded's `zx` at
[`1e2741c4ecd323ab3c6fdde87edc0ddda4a0384c`](https://github.com/UnAmigaReloaded-fpga/zx/tree/1e2741c4ecd323ab3c6fdde87edc0ddda4a0384c)
and the [MiSTer Spectrum tree](https://github.com/MiSTer-devel/ZX-Spectrum_MISTer).
These are external references. MiSTer has no pin in the handoff, and neither tree is in the local vendor inventory.

For any later extraction, record source paths, the revision above, and preserved
file notices with the adaptation. Treat bundled ROM images and firmware blobs
as separate assets requiring their own provenance and terms. Keep user-supplied
Spectrum ROMs outside the repository.
