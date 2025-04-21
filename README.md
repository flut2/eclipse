![Eclipse picture](https://github.com/flut2/eclipse/blob/main/eclipse.png?raw=true)

**Requirements:**

- Vulkan SDK set up
- A Redis-compatible server running (or Dragonfly if toggled on in the server build options)
- Latest Zig master (last tested with 0.15.0-dev.377+f01833e03)

**Usage:**

Should work on localhost without any changes, just compile and run the server and the client. First user to register is automatically ranked Admin.

To expose the server to other people, head into ``assets/server/settings.ziggy`` and ``client/build.zig`` and change the relevant IPs (``public_ip``, ``login_server_uri``), with the latter being optional (can also specify it as a build option).
You probably should use a release mode (like ``-Doptimize=ReleaseSafe``) when distributing the client or hosting a public-facing server though.
