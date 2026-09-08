package com.kaisarcode.demo;

import java.io.BufferedOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

public class LocalServer implements Runnable {
    private final ServerSocket server;
    private final Thread thread;
    private volatile String manifest = "";
    private volatile boolean notModified = false;
    private final Map<String, byte[]> assets = new LinkedHashMap<String, byte[]>();
    private volatile Set<String> omitted = new java.util.HashSet<String>();
    private volatile Set<String> truncated = new java.util.HashSet<String>();
    private volatile int manifestGets = 0;
    private volatile String lastIfModifiedSince = null;

    public LocalServer(int port) throws IOException {
        server = new ServerSocket(port);
        thread = new Thread(this, "LocalServer");
        thread.setDaemon(true);
        thread.start();
    }

    public int port() {
        return server.getLocalPort();
    }

    public void stop() throws IOException {
        server.close();
    }

    public void setManifest(String json) {
        this.manifest = json;
    }

    public void setNotModified(boolean v) {
        this.notModified = v;
    }

    public void setAsset(String path, byte[] content) {
        assets.put(path, content);
    }

    public void setOmitted(Set<String> paths) {
        this.omitted = paths;
    }

    public void setTruncated(Set<String> paths) {
        this.truncated = paths;
    }

    public int manifestGets() {
        return manifestGets;
    }

    public String lastIfModifiedSince() {
        return lastIfModifiedSince;
    }

    public int assetGets(String path) {
        return requestCounts.containsKey(path) ? requestCounts.get(path) : 0;
    }

    private final Map<String, Integer> requestCounts = new LinkedHashMap<String, Integer>();

    @Override
    public void run() {
        while (true) {
            try {
                Socket sock = server.accept();
                handle(sock);
            } catch (IOException e) {
                return;
            }
        }
    }

    private void handle(Socket sock) throws IOException {
        InputStream in = null;
        BufferedOutputStream out = null;
        try {
            sock.setSoTimeout(5000);
            in = sock.getInputStream();
            out = new BufferedOutputStream(sock.getOutputStream());
            String requestLine = readLine(in);
            if (requestLine == null || requestLine.isEmpty()) {
                return;
            }
            String[] parts = requestLine.split(" ");
            String method = parts[0];
            String path = parts.length > 1 ? parts[1] : "/";

            boolean isHead = method.equalsIgnoreCase("HEAD");
            if (!isHead && !method.equalsIgnoreCase("GET")) {
                respond(out, isHead, 405, "", new byte[0]);
                return;
            }

            String ims = null;
            String line;
            while ((line = readLine(in)) != null && !line.isEmpty()) {
                if (line.regionMatches(true, 0, "If-Modified-Since: ", 0, "If-Modified-Since: ".length())) {
                    ims = line.substring("If-Modified-Since: ".length()).trim();
                }
            }
            if (ims != null) {
                lastIfModifiedSince = ims;
            }

            if (path.equals("/update/provision/manifest.json")) {
                manifestGets++;
                if (System.getProperty("debug") != null && manifestGets <= 2) {
                    System.err.println("SERVER manifest=[" + manifest + "]");
                }
                if (isHead && notModified && ims != null && !ims.isEmpty()) {
                    respond(out, true, 304, "", new byte[0]);
                    return;
                }
                byte[] body = manifest.getBytes(StandardCharsets.UTF_8);
                respond(out, isHead, body.length == 0 ? 500 : 200, "application/json", body);
                return;
            }

            String prefix = "/update/provision/";
            String assetPath = "/";
            if (path.startsWith(prefix)) {
                assetPath = path.substring(prefix.length());
            }
            if (assetPath.equals("/")) {
                byte[] empty = new byte[0];
                respond(out, isHead, 200, "application/octet-stream", empty);
                return;
            }

            requestCounts.put(assetPath, requestCounts.containsKey(assetPath) ? requestCounts.get(assetPath) + 1 : 1);

            if (omitted.contains(assetPath)) {
                respond(out, isHead, 404, "text/plain", new byte[0]);
                return;
            }
            byte[] content = assets.get(assetPath);
            if (content == null) {
                respond(out, isHead, 404, "text/plain", new byte[0]);
                return;
            }
            byte[] body = content;
            if (truncated.contains(assetPath)) {
                byte[] t = new byte[content.length > 0 ? content.length - 1 : 0];
                System.arraycopy(content, 0, t, 0, t.length);
                body = t;
            }
            respond(out, isHead, 200, "application/octet-stream", body);
        } finally {
            try {
                if (out != null) out.close();
            } catch (IOException ignored) {}
            try {
                if (in != null) in.close();
            } catch (IOException ignored) {}
            try {
                sock.close();
            } catch (IOException ignored) {}
        }
    }

    private static String readLine(InputStream in) throws IOException {
        StringBuilder sb = new StringBuilder();
        int c;
        while ((c = in.read()) != -1) {
            if (c == '\r') {
                int next = in.read();
                if (next == '\n') {
                    return sb.toString();
                }
                sb.append('\n');
                if (next != -1) {
                    sb.append((char) next);
                }
                continue;
            }
            if (c == '\n') {
                return sb.toString();
            }
            sb.append((char) c);
        }
        return sb.length() == 0 ? null : sb.toString();
    }

    private static void respond(BufferedOutputStream out, boolean isHead, int code, String contentType, byte[] body)
            throws IOException {
        String reason = code == 200 ? "OK" : code == 304 ? "Not Modified" : code == 404 ? "Not Found" : "Error";
        String headers = "HTTP/1.0 " + code + " " + reason + "\r\n"
                + "Content-Type: " + contentType + "\r\n"
                + "Content-Length: " + body.length + "\r\n"
                + "Last-Modified: Thu, 01 Jan 1970 00:00:00 GMT\r\n"
                + "Date: Thu, 01 Jan 1970 00:00:00 GMT\r\n"
                + "Connection: close\r\n\r\n";
        out.write(headers.getBytes(StandardCharsets.UTF_8));
        if (!isHead) {
            out.write(body);
        }
        out.flush();
    }
}