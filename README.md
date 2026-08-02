# MacErnet

## Features

- Shows a native Ethernet icon in the macOS menu bar only while Ethernet is active, then hides it automatically when the connection becomes inactive.
- Displays the connected network service name, adapter name, and BSD interface name when you open the menu.
- Shows live download and upload speeds using macOS network-interface counters, with a setting to turn speed monitoring off.
- Opens macOS Network Settings directly from the menu.
- Can launch automatically at login.
- Checks for and installs updates in-app through the public `agraja38/app-update-feeds` feed.
- Supports macOS 13 and later on Apple silicon and Intel Macs.
- MacErnet will receive updates only until macOS 27 is released, because macOS 27 automatically changes the Wi-Fi icon to an Ethernet icon when Ethernet is connected.

## Installation

1. Download `MacErnet-1.0.0-universal.dmg` from the latest release.
2. Open the disk image and drag **MacErnet** into **Applications**.
3. Open **Applications**, Control-click **MacErnet**, and choose **Open** the first time.
4. If macOS still blocks the unsigned app, open Terminal and run:

   ```sh
   xattr -dr com.apple.quarantine /Applications/MacErnet.app
   ```

5. Launch MacErnet. Its menu bar icon appears automatically whenever an active Ethernet connection is detected.
