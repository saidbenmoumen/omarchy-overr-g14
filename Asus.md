Looks like this is a known issue and asus-linux already has a (slightly hacky) solution for it but I can confirm it absolutely works. Had to hop on their Discord to find it:

1. Enable VFIO support in '/etc/supergfxd.conf' -> "vfio_enable": true
2. After resuming from sleep and having the dGPU waking up, set video mode to Vfio and back to Integrated. This will turn the dGPU back off.
3. (optional) Create a service to automatically do step 2 when resuming from suspend: Create a file '/etc/systemd/system/dgpu_toggle_forceoff.service' :

```
[Unit]
Description=toggle vfio mode after suspend...
After=suspend.target

[Service]
User=root
Type=simple
ExecStart=/usr/local/bin/dgpu_toggle_forceoff.sh

[Install]
WantedBy=suspend.target
```

Then create a script `/usr/local/bin/dgpu_toggle_forceoff.sh` and make it executable:

```
#!/bin/bash

sleep 4
supergfxctl -m Vfio

sleep 1
supergfxctl -m Integrated
```

Finally enable this service so it executes the script on suspend:

`sudo systemctl enable --now dgpu_toggle_forceoff.service`

TLDR: Switching off of and back onto 'Integrated' will turn the dGPU off after resuming from suspend, but that normally requires a restart or log out. Enable the VFIO option for 'supergfxctl', since switching between that and Integrated happens instantly. Create and enable a new service that does that toggle whenever you suspend/resume.
