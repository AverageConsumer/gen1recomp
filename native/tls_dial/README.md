# gen1tls — desktop TLS dialer

Native AOT library that gives mods a non-blocking TLS client with the same
handle/poll contract as the Android `TlsSocket` / `love.system.tls*` bridge.

- **Windows:** Schannel via `SslStream` (system trust store, SNI)
- **Linux / macOS:** same project, publish with `-r linux-x64` / `osx-x64` /
  `osx-arm64` when those builds are wired up

## Build

```powershell
dotnet publish native/tls_dial/Gen1Tls.csproj -c Release -r win-x64 -o dist/native/win-x64
```

The Windows game zip script already does this:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_windows.ps1 -Version 0.1.77
```

Ship `gen1tls.dll` (or `libgen1tls.so` / `libgen1tls.dylib`) **next to** the
fused executable. Mods load it through LuaJIT FFI; no .NET runtime is
required on the player's machine.

## Android

On Android, the matching API is exposed as `love.system.tlsOpen` /
`tlsStatus` / `tlsSend` / `tlsReceive` / `tlsError` / `tlsClose`, backed by
`org.love2d.android.TlsSocket`.
