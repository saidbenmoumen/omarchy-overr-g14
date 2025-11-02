a modified omarchy .conf to match my preferences :)

# DGPU (NVIDIA)

#### Laptop / Hybrid GPU Power Management Issues NVIDIA, iGPU + dGPU

<https://github.com/basecamp/omarchy/issues/1776>

1. use supergfxctl instead of envycontrol

2. add S0ix power management to the kernel `/etc/modprobe.d/nvidia-power-management.conf`

```
options nvidia NVreg_DynamicPowerManagement=0x02 NVreg_EnableS0ixPowerManagement=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1
```

and

```
sudo limine-update
```

NOTE: if integrated make sure /etc/supergfxctl.conf has mode "Hybrid"

#### Walker using DGPU

there is only nvidia icd in `/usr/share/vulkan/icd.d/` ?

```
sudo pacman -S vulkan-radeon lib32-vulkan-radeon
```

VK_ICD_FILENAMES env which exists should work now

#### Xorg DGPU keeps it up (SDDM)

etc/sddm.conf.d/wayland.conf

```
[General]
DisplayServer=wayland

[Autologin]
User=said
Session=hyprland-uwsm

[Theme]
Current=breeze
```
