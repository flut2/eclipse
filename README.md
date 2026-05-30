![Eclipse picture](https://github.com/flut2/eclipse/blob/main/eclipse.png?raw=true)

**Requirements:**

- Vulkan SDK set up
- A Redis-compatible server running (or Dragonfly if toggled on in the server build options)
- The Zig version specified in the root `build.zig.zon`

**Usage:**

Make sure the following all point to the correct IPs and ports (they're all localhost by default):
- Server settings (`assets/server/settings.ziggy`) 
- Client build options (`login_server_ip`, `login_server_port`)
