# Bazzite notes

These items are Bazzite-specific; do not copy them verbatim to mutable Fedora,
Arch, Ubuntu, or NixOS.

The tested host is Bazzite 44 with GNOME Wayland. Layer the small host packages
that must integrate with udev, OpenXR, or screenshots, then reboot:

```bash
rpm-ostree install envision openxr-devel wmctrl ImageMagick
```

Use Homebrew for rapidly changing build dependencies where practical:

```bash
brew install cmake ninja meson rust shaderc pkgconf \
  alsa-lib dav1d pipewire libxkbcommon dbus openssl@3 \
  vulkan-headers vulkan-loader
```

The additional libraries are WayVR build dependencies. Keeping them in the
same Homebrew prefix lets `scripts/build-wayvr.sh` provide Cargo a consistent
pkg-config and linker search path on the immutable host.

The tested Framework 16/RX 7700S boot arguments are:

```bash
sudo rpm-ostree kargs \
  --append-if-missing=bluetooth.disable_ertm=1 \
  --append-if-missing=amdgpu.dcdebugmask=0xc10
```

- `bluetooth.disable_ertm=1` is a controller compatibility fallback. Try a
  current kernel without it first.
- `amdgpu.dcdebugmask=0xc10` is AMD/direct-display specific and experimental.
  Do not use it on Intel or NVIDIA systems.

Steam is launched through `/usr/bin/bazzite-steam` by the example settings.
If your Bazzite image uses another launcher, update `STEAM_COMMAND`.
