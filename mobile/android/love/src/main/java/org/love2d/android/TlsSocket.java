package org.love2d.android;

import android.util.Log;

import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SNIHostName;
import javax.net.ssl.SNIServerName;
import javax.net.ssl.SSLParameters;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;

/**
 * A TLS client socket that Lua can drive without ever blocking a frame.
 *
 * WHY THIS EXISTS. LuaSocket, which is what LOVE ships, speaks TCP and nothing
 * else, so wss:// was simply unreachable from the game -- and every room hosted
 * on archipelago.gg is TLS-only, accepting a plain connection just long enough
 * to drop it. The alternative was vendoring mbedTLS into the NDK build and
 * carrying a CA bundle in the APK; the platform already has both a TLS stack
 * and the system trust store, so this asks Android instead.
 *
 * THE CONTRACT. Callers get an int handle and poll it. open() returns
 * immediately and the connect and handshake happen on their own thread, so a
 * slow or unreachable host costs nothing on the game thread -- which matters
 * more here than it did for httpDownload, since that runs on a worker and this
 * is serviced from the frame loop. Bytes handed to send() before the handshake
 * finishes are queued, not refused, so a caller can write its request the
 * moment it has a handle and never think about readiness again.
 *
 * Reads are drained by a thread into a chunk queue and handed over a copy at a
 * time; a caller that stops polling stops the connection rather than growing
 * the heap without limit.
 */
final class TlsSocket {
    static final int STATUS_CONNECTING = 0;
    static final int STATUS_OPEN = 1;
    static final int STATUS_CLOSED = 2;

    private static final int CONNECT_TIMEOUT_MS = 15000;
    private static final int READ_CHUNK = 16384;
    /** Roughly a second of a very chatty room; past this the reader is gone. */
    private static final int MAX_BUFFERED = 4 * 1024 * 1024;

    private static final ConcurrentHashMap<Integer, TlsSocket> LIVE =
        new ConcurrentHashMap<Integer, TlsSocket>();
    private static final AtomicInteger NEXT_HANDLE = new AtomicInteger(1);

    private final String host;
    private final int port;
    private final int handle;

    private volatile int status = STATUS_CONNECTING;
    private volatile String error = null;
    private volatile boolean closing = false;
    private volatile SSLSocket socket = null;

    private final Object inLock = new Object();
    private final ArrayDeque<byte[]> inChunks = new ArrayDeque<byte[]>();
    private int inHeadOffset = 0;
    private int inAvailable = 0;

    private final Object outLock = new Object();
    private final ArrayDeque<byte[]> outChunks = new ArrayDeque<byte[]>();

    private TlsSocket(String host, int port, int handle) {
        this.host = host;
        this.port = port;
        this.handle = handle;
    }

    // ---------------------------------------------------------------- API

    static int open(String host, int port) {
        if (host == null || host.length() == 0 || port <= 0 || port > 65535) return -1;
        final int handle = NEXT_HANDLE.getAndIncrement();
        final TlsSocket self = new TlsSocket(host, port, handle);
        LIVE.put(Integer.valueOf(handle), self);
        Thread dialer = new Thread(new Runnable() {
            @Override public void run() { self.dial(); }
        }, "tls-dial-" + handle);
        dialer.setDaemon(true);
        dialer.start();
        return handle;
    }

    static int status(int handle) {
        TlsSocket self = LIVE.get(Integer.valueOf(handle));
        return self == null ? -1 : self.status;
    }

    static String error(int handle) {
        TlsSocket self = LIVE.get(Integer.valueOf(handle));
        return self == null ? null : self.error;
    }

    static int send(int handle, byte[] data) {
        TlsSocket self = LIVE.get(Integer.valueOf(handle));
        if (self == null || data == null) return -1;
        if (self.status == STATUS_CLOSED) return -1;
        if (data.length == 0) return 0;
        synchronized (self.outLock) {
            self.outChunks.add(data);
            self.outLock.notifyAll();
        }
        return data.length;
    }

    static byte[] receive(int handle, int max) {
        TlsSocket self = LIVE.get(Integer.valueOf(handle));
        if (self == null || max <= 0) return null;
        return self.take(max);
    }

    static void close(int handle) {
        TlsSocket self = LIVE.remove(Integer.valueOf(handle));
        if (self != null) self.shutdown(null);
    }

    // ------------------------------------------------------------ internals

    private void dial() {
        Socket plain = null;
        try {
            plain = new Socket();
            plain.connect(new InetSocketAddress(host, port), CONNECT_TIMEOUT_MS);
            plain.setTcpNoDelay(true);

            SSLSocketFactory factory = (SSLSocketFactory) SSLSocketFactory.getDefault();
            SSLSocket ssl = (SSLSocket) factory.createSocket(plain, host, port, true);

            // Wrapping an already-connected socket skips the SNI and hostname
            // checking that createSocket(host, port) would have done for us, and
            // a shared address like archipelago.gg answers with the wrong
            // certificate without the name in the hello. Both are set through
            // SSLParameters where the platform has it, with the verifier below
            // as the floor for anything older.
            boolean verifiedByPlatform = false;
            try {
                SSLParameters params = ssl.getSSLParameters();
                params.setEndpointIdentificationAlgorithm("HTTPS");
                List<SNIServerName> names = new ArrayList<SNIServerName>(1);
                names.add(new SNIHostName(host));
                params.setServerNames(names);
                ssl.setSSLParameters(params);
                verifiedByPlatform = true;
            } catch (Throwable ignored) {
                // Older platform: handled after the handshake instead.
            }

            enableModernProtocols(ssl);
            ssl.startHandshake();

            if (!verifiedByPlatform
                && !HttpsURLConnection.getDefaultHostnameVerifier()
                    .verify(host, ssl.getSession())) {
                throw new java.io.IOException(
                    "certificate does not match " + host);
            }

            socket = ssl;
            if (closing) { shutdown(null); return; }
            status = STATUS_OPEN;

            Thread writer = new Thread(new Runnable() {
                @Override public void run() { pumpOut(); }
            }, "tls-write-" + handle);
            writer.setDaemon(true);
            writer.start();

            pumpIn();
        } catch (Throwable t) {
            shutdown(describe(t));
            if (plain != null) {
                try { plain.close(); } catch (Throwable ignored) {}
            }
        }
    }

    /**
     * minSdk is 16, where TLS 1.1/1.2 exist but are off by default. Every
     * modern server refuses everything older, so switch on whatever the
     * platform has rather than leaving an old device negotiating TLS 1.0.
     */
    private static void enableModernProtocols(SSLSocket ssl) {
        try {
            List<String> wanted = new ArrayList<String>(3);
            for (String supported : ssl.getSupportedProtocols()) {
                if (supported.startsWith("TLSv1.1")
                    || supported.startsWith("TLSv1.2")
                    || supported.startsWith("TLSv1.3")) {
                    wanted.add(supported);
                }
            }
            if (!wanted.isEmpty()) {
                ssl.setEnabledProtocols(wanted.toArray(new String[wanted.size()]));
            }
        } catch (Throwable ignored) {
        }
    }

    private void pumpIn() {
        try {
            InputStream in = socket.getInputStream();
            byte[] buf = new byte[READ_CHUNK];
            while (!closing) {
                int n = in.read(buf);
                if (n < 0) break;
                if (n == 0) continue;
                byte[] chunk = new byte[n];
                System.arraycopy(buf, 0, chunk, 0, n);
                synchronized (inLock) {
                    if (inAvailable + n > MAX_BUFFERED) {
                        throw new java.io.IOException("read buffer overflow");
                    }
                    inChunks.add(chunk);
                    inAvailable += n;
                }
            }
            shutdown(null);
        } catch (Throwable t) {
            shutdown(describe(t));
        }
    }

    private void pumpOut() {
        try {
            OutputStream out = socket.getOutputStream();
            while (true) {
                byte[] chunk;
                synchronized (outLock) {
                    while (outChunks.isEmpty() && !closing && status != STATUS_CLOSED) {
                        outLock.wait();
                    }
                    if (closing || status == STATUS_CLOSED) return;
                    chunk = outChunks.poll();
                }
                if (chunk != null) {
                    out.write(chunk);
                    out.flush();
                }
            }
        } catch (Throwable t) {
            shutdown(describe(t));
        }
    }

    private byte[] take(int max) {
        synchronized (inLock) {
            if (inAvailable <= 0) return null;
            int want = Math.min(max, inAvailable);
            byte[] out = new byte[want];
            int filled = 0;
            while (filled < want) {
                byte[] head = inChunks.peek();
                if (head == null) break;
                int have = head.length - inHeadOffset;
                int take = Math.min(have, want - filled);
                System.arraycopy(head, inHeadOffset, out, filled, take);
                filled += take;
                inHeadOffset += take;
                if (inHeadOffset >= head.length) {
                    inChunks.poll();
                    inHeadOffset = 0;
                }
            }
            inAvailable -= filled;
            if (filled == want) return out;
            byte[] short_ = new byte[filled];
            System.arraycopy(out, 0, short_, 0, filled);
            return short_;
        }
    }

    /**
     * The handle stays registered until the caller closes it, so why the
     * connection ended and whatever arrived before it did are both still
     * readable. Dropping it here instead would turn a server that states its
     * refusal and hangs up into an unknown handle, which is the one failure a
     * player most needs the reason for.
     */
    private void shutdown(String why) {
        if (why != null && error == null) error = why;
        closing = true;
        status = STATUS_CLOSED;
        synchronized (outLock) { outLock.notifyAll(); }
        SSLSocket s = socket;
        socket = null;
        if (s != null) {
            try { s.close(); } catch (Throwable ignored) {}
        }
        if (why != null) Log.d("TlsSocket", host + ":" + port + " -- " + why);
    }

    private static String describe(Throwable t) {
        String msg = t.getMessage();
        String name = t.getClass().getSimpleName();
        if (msg == null || msg.length() == 0) return name;
        return name + ": " + msg;
    }
}
