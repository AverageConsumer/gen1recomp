# LÖVE UWP binaries

These x64 UWP Release binaries were built from [`caorthann-celt/love-xbox-uwp`](https://github.com/caorthann-celt/love-xbox-uwp) at commit `62275ed10190afbec01f65754b3bcc04f244dd35`.

The build uses LÖVE 11.5, LuaJIT, SDL2, and ANGLE. Keep the DLLs and import libraries together; they are one binary interface.

The normal package build consumes these files directly. Rebuilding the backend is a separate dependency maintenance task.
