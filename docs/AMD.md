# AMD GPU notes

The optional dGPU guard selects AMDGPU's VR-oriented power profile, prevents
runtime suspend while the headset adapter is present, and restores automatic
power management on disconnect. It is installed only by
`--framework16-rx7700s`.

The settings file forces Vulkan onto the GPU connected to PSVR2 using
`MESA_VK_DEVICE_SELECT`. Change or clear this value on other GPUs. Incorrect
GPU selection produces copies, jitter, failed direct display, or a black HMD.

Motion smoothing is disabled because the tested Linux path produced ghosting.
The target is native 120 Hz; tune individual game quality when a title cannot
hold the 8.33 ms frame budget rather than lowering the global headset default.
