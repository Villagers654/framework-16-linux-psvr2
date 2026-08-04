# AMD GPU notes

The optional dGPU guard selects AMDGPU's VR-oriented power profile, prevents
runtime suspend while the headset adapter is present, and restores automatic
power management on disconnect. It is installed only by
`--framework16-rx7700s`. The guard remains running while PSVR2 is connected and
reasserts the profile if the desktop power manager resets it after login; a
one-shot profile change is not persistent enough on the tested Bazzite system.

The settings file forces Vulkan onto the GPU connected to PSVR2 using
`MESA_VK_DEVICE_SELECT`. Change or clear this value on other GPUs. Incorrect
GPU selection produces copies, jitter, failed direct display, or a black HMD.

Motion smoothing is disabled because the tested Linux path produced ghosting.
The target is native 120 Hz; tune individual game quality when a title cannot
hold the 8.33 ms frame budget rather than lowering the global headset default.

The RX 7700S sends PSVR2 audio over DisplayPort. PipeWire can briefly drop
DisplayPort audio when a new stream joins its graph, so the Framework install
adds LVRA's device-scoped 64-sample period and 512-sample ALSA headroom rule.
If dropouts remain, double both values together. This rule is AMD/Framework
specific only because it matches the expansion-bay GPU's stable sink name.
