# Framework Laptop 16 notes

The RX 7700S Expansion Bay's rear video output is physically attached to the
dGPU. That is the output used by this setup. Side DisplayPort/HDMI Expansion
Cards are generally routed through the Ryzen iGPU.

Framework USB-A Expansion Cards are hubs from Linux's topology perspective.
That alone does not make them unsuitable for the Sony adapter; test link speed,
permissions, and stability rather than applying desktop-PC advice about a
“rear motherboard port” that does not exist on this laptop.

Run `scripts/detect-hardware.sh`. Confirm:

- `054c:0cde` appears in `lsusb`.
- a dGPU DisplayPort connector is connected.
- the selected Vulkan ID is the RX 7700S, not the integrated 780M.

The example ID `1002:7480` is RX 7700S-specific. PCI address `0000:03:00.0` was
correct on the tested machine but must be detected, not assumed.
