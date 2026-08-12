using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net.Security;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Authentication;
using System.Text;
using System.Threading;

namespace Gen1Tls;

/// <summary>
/// Non-blocking TLS client with the same handle/poll contract as the Android
/// TlsSocket bridge.  Connect and handshake run on a background thread; send
/// queues until the stream is ready; receive drains a chunk queue.  Certificate
/// validation and SNI are SslStream's defaults (platform trust store).
/// </summary>
public static class TlsDialer
{
    public const int StatusConnecting = 0;
    public const int StatusOpen = 1;
    public const int StatusClosed = 2;

    const int ConnectTimeoutMs = 15000;
    const int ReadChunk = 16384;
    const int MaxBuffered = 4 * 1024 * 1024;

    static readonly ConcurrentDictionary<int, Conn> Live = new();
    static int NextHandle = 1;

    sealed class Conn
    {
        public required string Host;
        public required int Port;
        public int Status = StatusConnecting;
        public string? Error;
        public bool Closing;
        public SslStream? Stream;
        public TcpClient? Client;

        public readonly object InLock = new();
        public readonly Queue<byte[]> InChunks = new();
        public int InHeadOffset;
        public int InAvailable;

        public readonly object OutLock = new();
        public readonly Queue<byte[]> OutChunks = new();
        public readonly ManualResetEventSlim OutPulse = new(false);
    }

    // ---------------------------------------------------------------- C ABI

    [UnmanagedCallersOnly(EntryPoint = "gen1tls_open")]
    public static int Open(nint hostPtr, int port)
    {
        if (hostPtr == 0 || port <= 0 || port > 65535) return -1;
        string? host = Marshal.PtrToStringUTF8(hostPtr);
        if (string.IsNullOrEmpty(host)) return -1;

        int handle = Interlocked.Increment(ref NextHandle);
        var conn = new Conn { Host = host, Port = port };
        if (!Live.TryAdd(handle, conn)) return -1;

        var dialer = new Thread(() => Dial(conn))
        {
            IsBackground = true,
            Name = "gen1tls-dial-" + handle,
        };
        dialer.Start();
        return handle;
    }

    [UnmanagedCallersOnly(EntryPoint = "gen1tls_status")]
    public static int Status(int handle)
        => Live.TryGetValue(handle, out var conn) ? conn.Status : -1;

    [UnmanagedCallersOnly(EntryPoint = "gen1tls_send")]
    public static int Send(int handle, nint dataPtr, int length)
    {
        if (!Live.TryGetValue(handle, out var conn) || dataPtr == 0) return -1;
        if (conn.Status == StatusClosed) return -1;
        if (length <= 0) return 0;

        var copy = new byte[length];
        Marshal.Copy(dataPtr, copy, 0, length);
        lock (conn.OutLock)
        {
            conn.OutChunks.Enqueue(copy);
            conn.OutPulse.Set();
        }
        return length;
    }

    [UnmanagedCallersOnly(EntryPoint = "gen1tls_receive")]
    public static int Receive(int handle, nint bufPtr, int max)
    {
        if (!Live.TryGetValue(handle, out var conn) || bufPtr == 0 || max <= 0)
            return 0;
        return Take(conn, bufPtr, max);
    }

    [UnmanagedCallersOnly(EntryPoint = "gen1tls_error")]
    public static int Error(int handle, nint bufPtr, int max)
    {
        if (!Live.TryGetValue(handle, out var conn)) return 0;
        string? err = conn.Error;
        if (string.IsNullOrEmpty(err) || bufPtr == 0 || max <= 1) return 0;

        byte[] utf8 = Encoding.UTF8.GetBytes(err);
        int n = Math.Min(utf8.Length, max - 1);
        Marshal.Copy(utf8, 0, bufPtr, n);
        Marshal.WriteByte(bufPtr, n, 0);
        return 1;
    }

    [UnmanagedCallersOnly(EntryPoint = "gen1tls_close")]
    public static void Close(int handle)
    {
        if (Live.TryRemove(handle, out var conn))
            Shutdown(conn, null);
    }

    // ------------------------------------------------------------ internals

    static void Dial(Conn conn)
    {
        try
        {
            var client = new TcpClient();
            var connect = client.ConnectAsync(conn.Host, conn.Port);
            if (!connect.Wait(ConnectTimeoutMs))
                throw new TimeoutException($"connect to {conn.Host}:{conn.Port} timed out");
            connect.GetAwaiter().GetResult();
            client.NoDelay = true;
            conn.Client = client;

            var ssl = new SslStream(client.GetStream(), leaveInnerStreamOpen: false);
            // AuthenticateAsClient sets SNI from targetHost and validates against
            // the platform trust store -- the whole reason this dialer exists.
            var auth = ssl.AuthenticateAsClientAsync(conn.Host);
            if (!auth.Wait(ConnectTimeoutMs))
                throw new TimeoutException($"TLS handshake with {conn.Host} timed out");
            auth.GetAwaiter().GetResult();

            conn.Stream = ssl;
            if (conn.Closing) { Shutdown(conn, null); return; }
            conn.Status = StatusOpen;

            var writer = new Thread(() => PumpOut(conn))
            {
                IsBackground = true,
                Name = "gen1tls-write",
            };
            writer.Start();
            PumpIn(conn);
        }
        catch (Exception ex)
        {
            Shutdown(conn, Describe(ex));
        }
    }

    static void PumpIn(Conn conn)
    {
        var stream = conn.Stream;
        if (stream == null) return;
        var buf = new byte[ReadChunk];
        try
        {
            while (!conn.Closing)
            {
                int n = stream.Read(buf, 0, buf.Length);
                if (n <= 0) break;
                var chunk = new byte[n];
                Buffer.BlockCopy(buf, 0, chunk, 0, n);
                lock (conn.InLock)
                {
                    // A stalled Lua pump must not grow forever; drop the
                    // connection rather than the room's backlog.
                    if (conn.InAvailable + n > MaxBuffered)
                        throw new InvalidOperationException("TLS receive buffer overflow");
                    conn.InChunks.Enqueue(chunk);
                    conn.InAvailable += n;
                }
            }
        }
        catch (Exception ex)
        {
            if (!conn.Closing) Shutdown(conn, Describe(ex));
            return;
        }
        Shutdown(conn, null);
    }

    static void PumpOut(Conn conn)
    {
        var stream = conn.Stream;
        if (stream == null) return;
        try
        {
            while (!conn.Closing)
            {
                byte[]? chunk = null;
                lock (conn.OutLock)
                {
                    if (conn.OutChunks.Count == 0)
                    {
                        conn.OutPulse.Reset();
                        // fall through to wait outside the lock
                    }
                    else
                    {
                        chunk = conn.OutChunks.Dequeue();
                    }
                }
                if (chunk == null)
                {
                    conn.OutPulse.Wait(250);
                    continue;
                }
                stream.Write(chunk, 0, chunk.Length);
                stream.Flush();
            }
        }
        catch (Exception ex)
        {
            if (!conn.Closing) Shutdown(conn, Describe(ex));
        }
    }

    static int Take(Conn conn, nint bufPtr, int max)
    {
        lock (conn.InLock)
        {
            if (conn.InAvailable == 0 || conn.InChunks.Count == 0) return 0;
            int copied = 0;
            while (copied < max && conn.InChunks.Count > 0)
            {
                byte[] head = conn.InChunks.Peek();
                int avail = head.Length - conn.InHeadOffset;
                int n = Math.Min(avail, max - copied);
                Marshal.Copy(head, conn.InHeadOffset, bufPtr + copied, n);
                copied += n;
                conn.InHeadOffset += n;
                conn.InAvailable -= n;
                if (conn.InHeadOffset >= head.Length)
                {
                    conn.InChunks.Dequeue();
                    conn.InHeadOffset = 0;
                }
            }
            return copied;
        }
    }

    static void Shutdown(Conn conn, string? why)
    {
        if (conn.Closing && why == null && conn.Status == StatusClosed) return;
        conn.Closing = true;
        if (why != null) conn.Error = why;
        conn.Status = StatusClosed;
        conn.OutPulse.Set();
        try { conn.Stream?.Dispose(); } catch { /* ignore */ }
        try { conn.Client?.Dispose(); } catch { /* ignore */ }
        conn.Stream = null;
        conn.Client = null;
    }

    static string Describe(Exception ex)
    {
        for (Exception? e = ex; e != null; e = e.InnerException)
        {
            if (e is AuthenticationException) return e.Message;
            if (e is SocketException se) return se.Message;
            if (e is TimeoutException) return e.Message;
            if (e is IOException) return e.Message;
        }
        return ex.GetBaseException().Message;
    }
}
