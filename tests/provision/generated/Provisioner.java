package com.kaisarcode.demo;

import android.content.Context;
import android.content.res.AssetManager;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public class Provisioner {
    private static final String TAG = "Provisioner";

    private static final String APP_MANIFEST_URL = "http://127.0.0.1:50845/update/provision/manifest.json";
    private static final String DEFAULT_START = "www/index.html";
    private static final String INSTALLED_MANIFEST_FILE = "installed.manifest.json";
    private static final int CONNECT_TIMEOUT_MS = 15000;
    private static final int READ_TIMEOUT_MS = 30000;

    public interface ProgressListener {
        void onStage(String text);
        void onProgress(long bytesDone, long bytesTotal, String current, long currentDone, long currentTotal);
        void onWarning(String text);
    }

    private static class Pending {
        final String label;
        final String url;
        final long size;
        final String sha;
        final File target;

        Pending(String label, String url, long size, String sha, File target) {
            this.label = label;
            this.url = url;
            this.size = size;
            this.sha = sha;
            this.target = target;
        }
    }

    private static class Progress {
        private final ProgressListener listener;
        private final long total;
        private long committed;

        Progress(ProgressListener listener, long total) {
            this.listener = listener;
            this.total = Math.max(0, total);
        }

        void stage(String text) { listener.onStage(text); }

        void report(String label, long currentTotal, long currentDone) {
            long done = committed + currentDone;
            if (currentTotal > 0 && done > committed + currentTotal) {
                done = committed + currentTotal;
            }
            listener.onProgress(done, total, label, currentDone, currentTotal);
        }

        void commit(long n) { committed += n; }
    }

    private static class ManifestData {
        final long timestamp;
        final String start;
        final JSONObject raw;
        ManifestData(long timestamp, String start, JSONObject raw) {
            this.timestamp = timestamp;
            this.start = start;
            this.raw = raw;
        }
    }

    // Categorized provisioning failures so callers can distinguish network
    // problems from exact integrity or activation failures.
    private static class ProvisionException extends IOException {
        ProvisionException(String message) { super(message); }
    }

    private static class DownloadException extends ProvisionException {
        DownloadException(String message) { super(message); }
    }

    private static class SizeMismatchException extends ProvisionException {
        SizeMismatchException(String message) { super(message); }
    }

    private static class ShaMismatchException extends ProvisionException {
        ShaMismatchException(String message) { super(message); }
    }

    private static class IncompleteReleaseException extends ProvisionException {
        IncompleteReleaseException(String message) { super(message); }
    }

    private static class CommitException extends ProvisionException {
        CommitException(String message) { super(message); }
    }

    public static String provision(Context context, ProgressListener listener) {
        File filesDir = context.getFilesDir();
        File wwwDir = new File(filesDir, "www");

        recoverOnStartup(context, filesDir, wwwDir, listener);
        copyEmbeddedWww(context, filesDir, wwwDir);

        String start = installedStart(filesDir);
        if (start.isEmpty()) {
            start = DEFAULT_START;
        }

        try {
            listener.onStage("Reading app manifest...");
            boolean[] appChanged = {false};
            JSONObject appManifest = fetchJsonCached(context, APP_MANIFEST_URL, appChanged);
            ManifestData manifest = validateManifest(appManifest, filesDir);
            if (manifest == null) {
                listener.onWarning("Invalid remote manifest (using local cache)");
                Log.e(TAG, "remote manifest rejected; keeping local release");
                return startUri(filesDir, start);
            }
            start = manifest.start;

            if (manifest.timestamp <= installedTimestamp(filesDir)) {
                writeInstalledMetadata(context, appManifest);
                listener.onStage("Done");
                Log.i(TAG, "remote manifest is not newer than installed release");
                return startUri(filesDir, start);
            }

            stageRelease(context, manifest, filesDir, listener);
            commitRelease(filesDir, listener);
            writeInstalledMetadata(context, appManifest);
            listener.onStage("Done");
            Log.i(TAG, "provisioning complete");
        } catch (SizeMismatchException e) {
            Log.w(TAG, "asset size mismatch; local release unchanged", e);
            listener.onWarning("Asset size mismatch (using local cache)");
        } catch (ShaMismatchException e) {
            Log.w(TAG, "asset sha256 mismatch; local release unchanged", e);
            listener.onWarning("Asset checksum mismatch (using local cache)");
        } catch (IncompleteReleaseException e) {
            Log.w(TAG, "remote release incomplete; local release unchanged", e);
            listener.onWarning("Incomplete remote release (using local cache)");
        } catch (CommitException e) {
            Log.w(TAG, "update activation failed; recovery will restore local release", e);
            listener.onWarning("Could not activate update (using local cache)");
        } catch (DownloadException e) {
            Log.w(TAG, "asset download failed; local release unchanged", e);
            listener.onWarning("Download failed: " + (e.getMessage() == null ? "connection error" : e.getMessage())
                    + " (using local cache)");
        } catch (IOException e) {
            Log.w(TAG, "network or provisioning failure; using local web assets", e);
            String msg = e.getMessage();
            listener.onWarning("Network unavailable: " + (msg == null ? "connection error" : msg)
                    + " (using local cache)");
        }

        return startUri(filesDir, start);
    }

    private static String startUri(File filesDir, String start) {
        String uri = new File(filesDir, start).toURI().toString();
        if (uri.startsWith("file:/") && !uri.startsWith("file:///")) {
            uri = "file:///" + uri.substring(6);
        }
        return uri;
    }

    private static void recoverOnStartup(Context context, File filesDir, File wwwDir, ProgressListener listener) {
        File wwwUpdate = new File(filesDir, "www.update");
        File wwwOld = new File(filesDir, "www.old");

        if (wwwUpdate.isDirectory()) {
            deleteRecursive(wwwUpdate);
            Log.i(TAG, "cleaned stale www.update staging");
        }

        if (wwwDir.isDirectory()) {
            if (isUsableWww(wwwDir, filesDir)) {
                if (wwwOld.isDirectory()) {
                    deleteRecursive(wwwOld);
                    Log.i(TAG, "cleaned stale www.old backup");
                }
                return;
            }
            deleteRecursive(wwwDir);
            Log.i(TAG, "removed unusable www");
        }

        if (wwwOld.isDirectory()) {
            if (renameOrCopy(wwwOld, wwwDir) && isUsableWww(wwwDir, filesDir)) {
                deleteRecursive(wwwOld);
                listener.onWarning("Recovered previous version");
                Log.i(TAG, "recovered www from www.old");
                return;
            }
            deleteRecursive(wwwOld);
            Log.i(TAG, "www.old was not usable; removed");
        }
    }

    private static boolean isUsableWww(File www, File filesDir) {
        if (!www.isDirectory() || www.list().length == 0) {
            return false;
        }
        File wwwVersion = new File(filesDir, "www.version");
        if (!wwwVersion.isFile()) {
            return true;
        }
        try {
            JSONObject installed = readInstalledManifest(filesDir);
            if (installed == null) {
                return true;
            }
            String start = installed.optString("start", "");
            if (start.isEmpty()) {
                return false;
            }
            File startFile = resolveUnderWww(www, stripWwwPrefix(start));
            return startFile != null && startFile.isFile();
        } catch (Exception e) {
            return false;
        }
    }

    private static JSONObject readInstalledManifest(File filesDir) {
        File f = new File(filesDir, INSTALLED_MANIFEST_FILE);
        if (!f.isFile()) {
            return null;
        }
        String body = readFileToString(f);
        if (body.isEmpty()) {
            return null;
        }
        try {
            return new JSONObject(body);
        } catch (Exception ignored) {
            return null;
        }
    }

    private static String installedStart(File filesDir) {
        JSONObject installed = readInstalledManifest(filesDir);
        if (installed != null) {
            String start = installed.optString("start", "");
            if (!start.isEmpty()) {
                return start;
            }
        }
        return "";
    }

    // Returns the timestamp of the currently active web release: the installed
    // manifest timestamp when one has been committed, otherwise the embedded
    // web build timestamp.
    private static long installedTimestamp(File filesDir) {
        JSONObject installed = readInstalledManifest(filesDir);
        if (installed != null && installed.has("timestamp")) {
            try {
                return installed.getLong("timestamp");
            } catch (Exception ignored) {}
        }
        long embeddedBuildTimestamp = 0;
        try {
            String ts = readFileToString(new File(filesDir, "www.build_timestamp"));
            if (!ts.isEmpty()) {
                embeddedBuildTimestamp = Long.parseLong(ts.trim());
            }
        } catch (Exception ignored) {}
        return Math.max(0, embeddedBuildTimestamp);
    }

    // Manifest paths are stored relative to filesDir and therefore carry the
    // "www/" prefix. Address files inside a www root (staging dir, active
    // www dir) by stripping that prefix: the root itself is the release.
    private static String stripWwwPrefix(String path) {
        return path.startsWith("www/") ? path.substring(4) : path;
    }

    private static File resolveUnderWww(File www, String path) {
        try {
            File candidate = new File(www, path);
            String canonical = candidate.getCanonicalPath();
            String wwwRoot = www.getCanonicalPath();
            if (canonical.startsWith(wwwRoot + File.separator) || canonical.equals(wwwRoot)) {
                return candidate;
            }
        } catch (IOException ignored) {}
        return null;
    }

    private static boolean renameOrCopy(File src, File dest) {
        if (src.renameTo(dest)) {
            return true;
        }
        try {
            if (dest.exists()) {
                deleteRecursive(dest);
            }
            copyDir(src, dest);
            deleteRecursive(src);
            return true;
        } catch (IOException e) {
            Log.e(TAG, "renameOrCopy failed: " + src + " -> " + dest, e);
            return false;
        }
    }

    private static void copyDir(File src, File dest) throws IOException {
        if (src.isDirectory()) {
            dest.mkdirs();
            File[] children = src.listFiles();
            if (children != null) {
                for (File child : children) {
                    copyDir(child, new File(dest, child.getName()));
                }
            }
        } else {
            InputStream in = null;
            FileOutputStream fos = null;
            try {
                in = new FileInputStream(src);
                fos = new FileOutputStream(dest);
                copyStream(in, fos);
            } finally {
                closeQuietly(in);
                closeQuietly(fos);
            }
        }
    }

    private static ManifestData validateManifest(JSONObject manifest, File filesDir) {
        try {
            if (!manifest.has("timestamp")) {
                Log.e(TAG, "manifest validation: missing required field timestamp");
                return null;
            }
            if (!manifest.has("start")) {
                Log.e(TAG, "manifest validation: missing required field start");
                return null;
            }
            if (!manifest.has("assets")) {
                Log.e(TAG, "manifest validation: missing required field assets");
                return null;
            }

            long timestamp = manifest.getLong("timestamp");
            String start = manifest.getString("start");

            if (!isValidRelativePath(start) || !start.startsWith("www/") || start.contains("..")) {
                Log.e(TAG, "manifest validation: invalid start path: " + start);
                return null;
            }
            if (!isPathContainedInWww(start, filesDir)) {
                Log.e(TAG, "manifest validation: start escapes filesDir/www: " + start);
                return null;
            }

            JSONArray assets = manifest.getJSONArray("assets");
            Set<String> declaredPaths = new HashSet<String>();

            for (int i = 0; i < assets.length(); i++) {
                JSONObject a = assets.getJSONObject(i);

                if (!a.has("path") || !a.has("size_bytes") || !a.has("sha256")) {
                    Log.e(TAG, "manifest validation: asset missing required fields at index " + i);
                    return null;
                }

                String path = a.getString("path");
                if (path.isEmpty() || !isValidRelativePath(path)
                        || !path.startsWith("www/") || path.contains("..")) {
                    Log.e(TAG, "manifest validation: invalid asset path: " + path);
                    return null;
                }
                if (!isPathContainedInWww(path, filesDir)) {
                    Log.e(TAG, "manifest validation: asset path escapes filesDir/www: " + path);
                    return null;
                }
                if (!declaredPaths.add(path)) {
                    Log.e(TAG, "manifest validation: duplicate asset path: " + path);
                    return null;
                }

                String sha = a.getString("sha256");
                if (!isValidSha256(sha)) {
                    Log.e(TAG, "manifest validation: invalid sha256 for " + path + ": " + sha);
                    return null;
                }

                long sizeBytes = a.getLong("size_bytes");
                if (sizeBytes < 0) {
                    Log.e(TAG, "manifest validation: negative size_bytes for " + path);
                    return null;
                }
            }

            if (!declaredPaths.contains(start)) {
                Log.e(TAG, "manifest validation: start does not reference a declared asset: " + start);
                return null;
            }

            return new ManifestData(timestamp, start, manifest);
        } catch (Exception e) {
            Log.e(TAG, "manifest validation failed", e);
            return null;
        }
    }

    private static boolean isValidRelativePath(String path) {
        if (path.isEmpty()) return false;
        if (path.startsWith("/")) return false;
        if (path.contains("\0")) return false;
        return true;
    }

    private static boolean isPathContainedInWww(String path, File filesDir) {
        try {
            File wwwDir = new File(filesDir, "www");
            File target = new File(filesDir, path);
            String canonicalTarget = target.getCanonicalPath();
            String canonicalWww = wwwDir.getCanonicalPath();
            return canonicalTarget.startsWith(canonicalWww + File.separator)
                    || canonicalTarget.equals(canonicalWww);
        } catch (IOException e) {
            return false;
        }
    }

    private static boolean isValidSha256(String sha) {
        if (sha == null || sha.length() != 64) return false;
        for (int i = 0; i < 64; i++) {
            char c = sha.charAt(i);
            if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) {
                return false;
            }
        }
        return true;
    }

    private static void stageRelease(Context context, ManifestData manifest, File filesDir, ProgressListener listener)
            throws IOException {
        File wwwDir = new File(filesDir, "www");
        File stagingDir = new File(filesDir, "www.update");

        if (stagingDir.exists()) {
            deleteRecursive(stagingDir);
        }
        if (!stagingDir.mkdirs() && !stagingDir.isDirectory()) {
            throw new IOException("cannot create staging directory: " + stagingDir);
        }

        List<Pending> pending = new ArrayList<Pending>();
        long total = 0;

        JSONArray assets = manifest.raw.optJSONArray("assets");
        if (assets != null) {
            for (int i = 0; i < assets.length(); i++) {
                JSONObject a = assets.optJSONObject(i);
                if (a == null) continue;

                String path = a.optString("path");
                if (path.isEmpty()) continue;

                String sha = a.optString("sha256", "");
                long size = a.optLong("size_bytes", -1);

                File activeFile = new File(filesDir, path);
                File stagingFile = new File(stagingDir, stripWwwPrefix(path));

                File parent = stagingFile.getParentFile();
                if (parent != null && !parent.isDirectory() && !parent.mkdirs()) {
                    throw new IOException("cannot create staging directory: " + parent);
                }

                if (activeFile.isFile() && !sha.isEmpty() && size >= 0
                        && activeFile.length() == size
                        && sha.equalsIgnoreCase(computeSha256(activeFile))) {
                    copyFile(activeFile, stagingFile);
                    Log.i(TAG, "reused from active: " + path);
                } else {
                    pending.add(new Pending(path, buildUrl(APP_MANIFEST_URL, path),
                            size, sha, stagingFile));
                    total += Math.max(0, size);
                }
            }
        }

        if (!pending.isEmpty()) {
            Progress progress = new Progress(listener, total);
            for (Pending p : pending) {
                progress.stage("Downloading " + p.label + "...");
                Log.i(TAG, "downloading asset: " + p.label);
                downloadFile(p.url, p.target, p.size, p.sha, p.label, progress);
            }
        }

        verifyCompleteRelease(manifest, stagingDir);
    }

    private static void verifyCompleteRelease(ManifestData manifest, File stagingDir) throws IOException {
        JSONArray assets = manifest.raw.optJSONArray("assets");
        if (assets == null) {
            throw new IncompleteReleaseException("no assets declared in manifest");
        }

        for (int i = 0; i < assets.length(); i++) {
            JSONObject a = assets.optJSONObject(i);
            if (a == null) continue;

            String path = a.optString("path");
            if (path.isEmpty()) continue;

            File f = new File(stagingDir, stripWwwPrefix(path));
            if (!f.isFile()) {
                throw new IncompleteReleaseException("staged asset missing: " + path);
            }

            long expectedSize = a.optLong("size_bytes", -1);
            if (expectedSize >= 0 && f.length() != expectedSize) {
                throw new SizeMismatchException("staged asset size mismatch: " + path
                        + " (expected " + expectedSize + ", got " + f.length() + ")");
            }

            String expectedSha = a.optString("sha256", "");
            if (!expectedSha.isEmpty() && !expectedSha.equalsIgnoreCase(computeSha256(f))) {
                throw new ShaMismatchException("staged asset sha256 mismatch: " + path);
            }
        }

        File startFile = new File(stagingDir, stripWwwPrefix(manifest.start));
        if (!startFile.isFile()) {
            throw new IncompleteReleaseException("manifest start file missing from staging: " + manifest.start);
        }
    }

    private static void commitRelease(File filesDir, ProgressListener listener) throws IOException {
        File wwwDir = new File(filesDir, "www");
        File stagingDir = new File(filesDir, "www.update");
        File backupDir = new File(filesDir, "www.old");

        if (backupDir.exists()) {
            deleteRecursive(backupDir);
        }

        if (wwwDir.exists()) {
            if (!wwwDir.renameTo(backupDir)) {
                throw new CommitException("failed to move active www to backup");
            }
        }

        if (!stagingDir.renameTo(wwwDir)) {
            if (backupDir.exists()) {
                renameOrCopy(backupDir, wwwDir);
                deleteRecursive(backupDir);
            }
            throw new CommitException("failed to activate staged release");
        }

        deleteRecursive(backupDir);
        Log.i(TAG, "release committed successfully");
    }

    private static void downloadFile(String urlStr, File out, long expectedSize, String expectedSha,
            String label, Progress progress) throws IOException {
        HttpURLConnection conn = (HttpURLConnection) new URL(urlStr).openConnection();
        conn.setConnectTimeout(CONNECT_TIMEOUT_MS);
        conn.setReadTimeout(READ_TIMEOUT_MS);
        conn.setInstanceFollowRedirects(true);
        try {
            int code = conn.getResponseCode();
            if (code != HttpURLConnection.HTTP_OK) {
                throw new DownloadException("HTTP " + code + " for " + label);
            }
            long contentLength = conn.getContentLength();
            long totalBytes = contentLength > 0 ? contentLength : expectedSize;
            InputStream in = null;
            FileOutputStream fos = null;
            try {
                in = conn.getInputStream();
                fos = new FileOutputStream(out);
                byte[] buf = new byte[8192];
                long done = 0;
                int n;
                while ((n = in.read(buf)) > 0) {
                    fos.write(buf, 0, n);
                    done += n;
                    progress.report(label, totalBytes, done);
                }
                progress.commit(done);
            } finally {
                closeQuietly(in);
                closeQuietly(fos);
            }

            if (expectedSize >= 0 && out.length() != expectedSize) {
                out.delete();
                throw new SizeMismatchException("asset size mismatch: " + label
                        + " (expected " + expectedSize + ", got " + out.length() + ")");
            }

            String sha = computeSha256(out);
            if (sha.isEmpty()) {
                out.delete();
                throw new IOException("SHA-256 computation failed for " + label);
            }
            if (!expectedSha.isEmpty() && !expectedSha.equalsIgnoreCase(sha)) {
                out.delete();
                throw new ShaMismatchException("asset sha256 mismatch: " + label);
            }
        } finally {
            conn.disconnect();
        }
    }

    private static JSONObject fetchJson(String urlStr) throws IOException {
        HttpURLConnection conn = (HttpURLConnection) new URL(urlStr).openConnection();
        conn.setConnectTimeout(CONNECT_TIMEOUT_MS);
        conn.setReadTimeout(READ_TIMEOUT_MS);
        conn.setInstanceFollowRedirects(true);
        try {
            int code = conn.getResponseCode();
            if (code != HttpURLConnection.HTTP_OK) {
                throw new IOException("HTTP " + code + " for " + urlStr);
            }
            StringBuilder sb = new StringBuilder();
            BufferedReader reader = null;
            try {
                reader = new BufferedReader(new InputStreamReader(conn.getInputStream(), StandardCharsets.UTF_8));
                String line;
                while ((line = reader.readLine()) != null) {
                    sb.append(line).append('\n');
                }
            } finally {
                closeQuietly(reader);
            }
            try {
                return new JSONObject(sb.toString());
            } catch (Exception e) {
                throw new IOException("invalid JSON from " + urlStr, e);
            }
        } finally {
            conn.disconnect();
        }
    }

    // Fetches the remote manifest using the committed manifest cache for
    // If-Modified-Since reuse. It never persists cache state itself; committed
    // metadata is written only after a successful commit so that a failure
    // before commit leaves installed-version metadata representing the
    // previous release.
    private static JSONObject fetchJsonCached(Context context, String urlStr, boolean[] changedOut) throws IOException {
        File cache = manifestCacheFile(context, urlStr);
        String cachedBody = readFileToString(cache);
        long cachedTimestamp = 0;
        if (cache.isFile() && !cachedBody.isEmpty()) {
            try {
                JSONObject cached = new JSONObject(cachedBody);
                cachedTimestamp = cached.optLong("timestamp", 0);
            } catch (Exception ignored) {}
        }

        HttpURLConnection conn = (HttpURLConnection) new URL(urlStr).openConnection();
        conn.setRequestMethod("HEAD");
        conn.setConnectTimeout(CONNECT_TIMEOUT_MS);
        conn.setReadTimeout(READ_TIMEOUT_MS);
        conn.setInstanceFollowRedirects(true);
        if (cachedTimestamp > 0) {
            java.text.SimpleDateFormat httpDateFormat =
                    new java.text.SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss zzz", java.util.Locale.US);
            httpDateFormat.setTimeZone(java.util.TimeZone.getTimeZone("GMT"));
            conn.setRequestProperty("If-Modified-Since",
                    httpDateFormat.format(new java.util.Date(cachedTimestamp * 1000L)));
        }
        try {
            int code = conn.getResponseCode();
            if (code == HttpURLConnection.HTTP_NOT_MODIFIED) {
                changedOut[0] = false;
                try {
                    return new JSONObject(cachedBody);
                } catch (Exception e) {
                    throw new IOException("invalid cached JSON", e);
                }
            }
            if (code != HttpURLConnection.HTTP_OK) {
                throw new IOException("HTTP " + code + " for " + urlStr);
            }
        } finally {
            conn.disconnect();
        }

        JSONObject fresh = fetchJson(urlStr);
        changedOut[0] = true;
        return fresh;
    }

    // Persists the accepted manifest as installed-version metadata alongside
    // the HTTP cache. Called only after a successful commit.
    private static void writeInstalledMetadata(Context context, JSONObject manifest) throws IOException {
        writeStringToFile(new File(context.getFilesDir(), INSTALLED_MANIFEST_FILE), manifest.toString());
        File cache = manifestCacheFile(context, APP_MANIFEST_URL);
        writeStringToFile(cache, manifest.toString());
    }

    private static File manifestCacheFile(Context context, String urlStr) {
        return new File(context.getFilesDir(), "manifest." + (urlStr.hashCode() & 0x7fffffff) + ".json");
    }

    private static String buildUrl(String manifestUrl, String path) {
        int idx = manifestUrl.lastIndexOf("/manifest.json");
        String base = idx >= 0 ? manifestUrl.substring(0, idx + 1) : manifestUrl;
        if (base.endsWith("/")) {
            return base + path;
        }
        return base + "/" + path;
    }

    private static void copyEmbeddedWww(Context context, File filesDir, File wwwDir) {
        try {
            AssetManager am = context.getAssets();
            String embeddedVersion = readStreamToString(am.open("www.version"));
            String localVersion = readFileToString(new File(filesDir, "www.version"));
            if (embeddedVersion.equals(localVersion)) {
                return;
            }
            deleteRecursive(wwwDir);
            if (wwwDir.mkdirs()) {
                copyAssetDir(am, "www", wwwDir);
                writeStringToFile(new File(filesDir, "www.version"), embeddedVersion);
                try {
                    String embeddedTimestamp = readStreamToString(am.open("www.build_timestamp"));
                    writeStringToFile(new File(filesDir, "www.build_timestamp"), embeddedTimestamp);
                } catch (IOException ignored) {}
                Log.i(TAG, "embedded www copied to " + wwwDir);
            }
        } catch (IOException e) {
            Log.e(TAG, "cannot copy embedded assets", e);
        }
    }

    private static void copyAssetDir(AssetManager am, String assetPath, File destDir) throws IOException {
        String[] entries = am.list(assetPath);
        if (entries == null) return;
        for (String entry : entries) {
            String child = assetPath + "/" + entry;
            File out = new File(destDir, entry);
            String[] sub = am.list(child);
            if (sub != null && sub.length > 0) {
                if (!out.mkdirs() && !out.isDirectory()) {
                    throw new IOException("mkdir failed: " + out);
                }
                copyAssetDir(am, child, out);
            } else {
                InputStream in = null;
                FileOutputStream fos = null;
                try {
                    in = am.open(child);
                    fos = new FileOutputStream(out);
                    copyStream(in, fos);
                } finally {
                    closeQuietly(in);
                    closeQuietly(fos);
                }
            }
        }
    }

    private static void deleteRecursive(File f) {
        if (!f.exists()) return;
        if (f.isDirectory()) {
            File[] children = f.listFiles();
            if (children != null) {
                for (File child : children) {
                    deleteRecursive(child);
                }
            }
        }
        f.delete();
    }

    private static String computeSha256(File f) {
        InputStream in = null;
        try {
            in = new FileInputStream(f);
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) {
                md.update(buf, 0, n);
            }
            StringBuilder sb = new StringBuilder();
            for (byte b : md.digest()) {
                sb.append(String.format("%02x", b & 0xff));
            }
            return sb.toString();
        } catch (Exception e) {
            return "";
        } finally {
            closeQuietly(in);
        }
    }

    private static void copyFile(File src, File dst) throws IOException {
        InputStream in = null;
        FileOutputStream fos = null;
        try {
            in = new FileInputStream(src);
            fos = new FileOutputStream(dst);
            copyStream(in, fos);
        } finally {
            closeQuietly(in);
            closeQuietly(fos);
        }
    }

    private static void copyStream(InputStream in, OutputStream out) throws IOException {
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) {
            out.write(buf, 0, n);
        }
    }

    private static String readFileToString(File f) {
        InputStream in = null;
        try {
            in = new FileInputStream(f);
            return readStreamToString(in);
        } catch (IOException e) {
            return "";
        } finally {
            closeQuietly(in);
        }
    }

    private static String readStreamToString(InputStream in) throws IOException {
        StringBuilder sb = new StringBuilder();
        byte[] buf = new byte[8192];
        int n;
        while ((n = in.read(buf)) > 0) {
            sb.append(new String(buf, 0, n, StandardCharsets.UTF_8));
        }
        return sb.toString();
    }

    private static void writeStringToFile(File f, String s) throws IOException {
        FileOutputStream fos = null;
        try {
            fos = new FileOutputStream(f);
            fos.write(s.getBytes(StandardCharsets.UTF_8));
        } finally {
            closeQuietly(fos);
        }
    }

    private static void closeQuietly(InputStream in) {
        if (in != null) { try { in.close(); } catch (IOException ignored) {} }
    }

    private static void closeQuietly(OutputStream out) {
        if (out != null) { try { out.close(); } catch (IOException ignored) {} }
    }

    private static void closeQuietly(BufferedReader reader) {
        if (reader != null) { try { reader.close(); } catch (IOException ignored) {} }
    }
}
