package com.kaisarcode.demo;

import android.content.res.AssetManager;

import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * JVM-level harness for the generated Provisioner logic. Runs the real
 * generated source (compiled by run.sh with APP_MANIFEST_URL pointed at a
 * local test server) against a fake android Context backed by real temp
 * directories. Exercises valid updates, manifest rejection, integrity
 * failures, download failures, transactional commit, and startup recovery.
 */
public class ProvisionTest {
    private static int passed = 0;
    private static int failed = 0;
    private static File workRoot;
    private static LocalServer server;
    private static int seq = 0;

    private static final class Capture implements Provisioner.ProgressListener {
        final List<String> warnings = new ArrayList<String>();

        public void onStage(String text) {}
        public void onProgress(long done, long total, String current, long currentDone, long currentTotal) {}
        public void onWarning(String text) { warnings.add(text); }

        boolean hasWarning(String needle) {
            for (String w : warnings) {
                if (w.contains(needle)) {
                    return true;
                }
            }
            return false;
        }
    }

    public static void main(String[] args) throws Exception {
        int port = Integer.parseInt(System.getProperty("test.port", "18081"));
        workRoot = Files.createTempDirectory("kcprovision").toFile();
        server = new LocalServer(port);

        try {
            scenario01CleanInstall();
            scenario02EqualTimestampSkips();
            scenario03ReuseUnchangedAsset();
            scenario04InvalidMissingTimestamp();
            scenario05PathTraversal();
            scenario06AbsolutePath();
            scenario07Duplicate();
            scenario08BadStart();
            scenario09StartNotDeclared();
            scenario10NegativeSize();
            scenario11ShortSha();
            scenario12NonHexSha();
            scenario13SizeMismatch();
            scenario14ShaMismatch();
            scenario15Http404();
            scenario16FailedUpdateKeepsPrevious();
            scenario17RecoveryFromBackup();
            scenario18StaleStagingCleanup();
            scenario19StaleBackupCleanup();
            scenario20EmbeddedFallback();
            scenario21UppercaseSha();
            scenario22NotModifiedReuse();
        } finally {
            server.stop();
            workRoot.delete();
        }

        System.out.println();
        System.out.println("ProvisionTest: " + passed + " passed, " + failed + " failed");
        if (failed > 0) {
            System.exit(1);
        }
    }

    private static void scenario01CleanInstall() throws Exception {
        servo(T2).provisional();
        File dir = freshDir("clean");
        Provisioner.provision(new TestContext(dir, noAssets()), new Capture());
        check("01 www/index.html present", new File(dir, "www/index.html").isFile());
        check("01 www/css/style.css present", new File(dir, "www/css/style.css").isFile());
        check("01 installed.manifest.json present", new File(dir, "installed.manifest.json").isFile());
        check("01 manifest cache present", !manifestCacheFiles(dir).isEmpty());
        check("01 no staging left", !new File(dir, "www.update").exists());
        check("01 no backup left", !new File(dir, "www.old").exists());
        startUriValid(dir);
    }

    private static void scenario02EqualTimestampSkips() throws Exception {
        ServerState state = servo(T2);
        File dir = freshDir("equal");
        state.provisional();
        Provisioner.provision(new TestContext(dir, noAssets()), new Capture());
        int getsAfterFirst = server.manifestGets();
        int indexGetsAfterFirst = server.assetGets("www/index.html");
        Capture cap = new Capture();
        Provisioner.provision(new TestContext(dir, noAssets()), cap);
        check("02 no warnings", cap.warnings.isEmpty());
        check("02 asset not re-downloaded", server.assetGets("www/index.html") == indexGetsAfterFirst);
        check("02 manifest revalidated", server.manifestGets() > getsAfterFirst);
        check("02 metadata timestamp", readInstalledTimestamp(dir) == T2);
    }

    private static void scenario03ReuseUnchangedAsset() throws Exception {
        ServerState first = servo(T1);
        File dir = freshDir("reuse");
        first.provisional();
        Provisioner.provision(new TestContext(dir, noAssets()), new Capture());
        int getsIndexBefore = server.assetGets("www/index.html");
        ServerState second = new ServerState(content(T1, "index"), content(T2, "css-new"), T2);
        second.provisional();
        Capture cap = new Capture();
        Provisioner.provision(new TestContext(dir, noAssets()), cap);
        check("03 unchanged asset reused (no download)", server.assetGets("www/index.html") == getsIndexBefore);
        check("03 updated asset downloaded", server.assetGets("www/css/style.css") > 1);
        check("03 css updated in place",
                fileContentEquals(new File(dir, "www/css/style.css"), content(T2, "css-new")));
        check("03 no warnings", cap.warnings.isEmpty());
        check("03 metadata updated", readInstalledTimestamp(dir) == T2);
    }

    private static void scenario04InvalidMissingTimestamp() throws Exception {
        assertRejected("04_missing_timestamp", "missing timestamp",
                manifestBody(new String[]{"timestamp"}, T2, "www/index.html", assetIndex(T1)));
    }

    private static void scenario05PathTraversal() throws Exception {
        assertRejected("05_path_traversal", "traversal",
                manifestBody(null, T2, "www/index.html", assetIndex(T1).concat(","+asset("www/../../evil", "x"))));
    }

    private static void scenario06AbsolutePath() throws Exception {
        assertRejected("06_absolute_path", "absolute",
                manifestBody(null, T2, "www/index.html", assetIndex(T1).concat(","+asset("/etc/passwd", "x"))));
    }

    private static void scenario07Duplicate() throws Exception {
        assertRejected("07_duplicate_path", "duplicate",
                manifestBody(null, T2, "www/index.html", assetIndex(T1).concat(","+asset("www/index.html", "dup"))));
    }

    private static void scenario08BadStart() throws Exception {
        assertRejected("08_bad_start", "start",
                manifestBody(null, T2, "www/../evil.html", assetIndex(T1)));
    }

    private static void scenario09StartNotDeclared() throws Exception {
        assertRejected("09_start_not_declared", "start",
                manifestBody(null, T2, "www/other.html", assetIndex(T1)));
    }

    private static void scenario10NegativeSize() throws Exception {
        byte[] index = content(T1, "index");
        assertRejected("10_negative_size", "size",
                manifestBody(null, T2, "www/index.html",
                        assetWith(index, -5, sha256(index))));
    }

    private static void scenario11ShortSha() throws Exception {
        byte[] index = content(T1, "index");
        assertRejected("11_short_sha", "sha",
                manifestBody(null, T2, "www/index.html",
                        assetWith(index, index.length, "abcd")));
    }

    private static void scenario12NonHexSha() throws Exception {
        byte[] index = content(T1, "index");
        String bad = "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz";
        assertRejected("12_nonhex_sha", "sha",
                manifestBody(null, T2, "www/index.html",
                        assetWith(index, index.length, bad)));
    }

    private static void scenario13SizeMismatch() throws Exception {
        ServerState state = servo(T2);
        state.provisional();
        server.setTruncated(singleton("www/index.html"));
        File dir = freshDir("size_mismatch");
        Capture cap = new Capture();
        Provisioner.provision(new TestContext(dir, noAssets()), cap);
        check("13 warning size mismatch", cap.hasWarning("size mismatch"));
        check("13 no metadata commit", !new File(dir, "installed.manifest.json").exists());
        check("13 www not activated", !new File(dir, "www").isDirectory());
    }

    private static void scenario14ShaMismatch() throws Exception {
        ServerState state = servo(T2);
        state.provisional();
        byte[] index = content(T2, "index");
        byte[] tampered = index.clone();
        tampered[0] ^= 0x01;
        server.setAsset("www/index.html", tampered);
        File dir = freshDir("sha_mismatch");
        Capture cap = new Capture();
        Provisioner.provision(new TestContext(dir, noAssets()), cap);
        check("14 warning checksum mismatch", cap.hasWarning("checksum mismatch"));
        check("14 no metadata commit", !new File(dir, "installed.manifest.json").exists());
        check("14 www not activated", !new File(dir, "www").isDirectory());
    }

    private static void scenario15Http404() throws Exception {
        ServerState state = servo(T2);
        state.provisional();
        server.setOmitted(singleton("www/index.html"));
        File dir = freshDir("http404");
        Capture cap = new Capture();
        Provisioner.provision(new TestContext(dir, noAssets()), cap);
        check("15 warning download failed", cap.hasWarning("Download failed"));
        check("15 no metadata commit", !new File(dir, "installed.manifest.json").exists());
    }

    private static void scenario16FailedUpdateKeepsPrevious() throws Exception {
        ServerState old = servo(T1);
        File dir = freshDir("keep_previous");
        old.provisional();
        Provisioner.provision(new TestContext(dir, noAssets()), new Capture());
        check("16 pre-state installed", readInstalledTimestamp(dir) == T1);
        ServerState newer = servo(T2);
        newer.provisional();
        server.setTruncated(singleton("www/css/style.css"));
        Capture cap = new Capture();
        Provisioner.provision(new TestContext(dir, noAssets()), cap);
        check("16 warning mismatch", cap.hasWarning("size mismatch"));
        check("16 metadata preserved", readInstalledTimestamp(dir) == T1);
        check("16 previous www preserved", new File(dir, "www/index.html").isFile());
    }

    private static void scenario17RecoveryFromBackup() throws Exception {
        ServerState old = servo(T0);
        File dir = freshDir("recover");
        old.provisional();
        Provisioner.provision(new TestContext(dir, noAssets()), new Capture());
        boolean moved = new File(dir, "www").renameTo(new File(dir, "www.old"));
        check("17 setup moved www to backup", moved);
        ServerState newer = servo(T1);
        newer.provisional();
        Capture cap = new Capture();
        Provisioner.provision(new TestContext(dir, noAssets()), cap);
        check("17 recovery warning", cap.hasWarning("Recovered previous version"));
        check("17 backup cleaned after restore", !new File(dir, "www.old").exists());
        check("17 www restored", new File(dir, "www/index.html").isFile());
    }

    private static void scenario18StaleStagingCleanup() throws Exception {
        ServerState state = servo(T2);
        state.provisional();
        File dir = freshDir("stale");
        new File(dir, "www.update").mkdirs();
        new File(dir, "www").mkdirs();
        Capture cap = new Capture();
        Provisioner.provision(new TestContext(dir, noAssets()), cap);
        check("18 stale staging cleaned", !new File(dir, "www.update").exists());
        check("18 unusable www replaced", new File(dir, "www/index.html").isFile());
        check("18 no warnings", cap.warnings.isEmpty());
    }

    private static void scenario19StaleBackupCleanup() throws Exception {
        ServerState old = servo(T1);
        File dir = freshDir("stale_backup");
        old.provisional();
        Provisioner.provision(new TestContext(dir, noAssets()), new Capture());
        new File(dir, "www.old").mkdirs();
        ServerState newer = servo(T2);
        newer.provisional();
        Capture cap = new Capture();
        Provisioner.provision(new TestContext(dir, noAssets()), cap);
        check("19 stale backup cleaned", !new File(dir, "www.old").exists());
        check("19 no warnings", cap.warnings.isEmpty());
    }

    private static void scenario20EmbeddedFallback() throws Exception {
        server.setManifest("{\"nope\":true}");
        server.setOmitted(new HashSet<String>());
        File dir = freshDir("embedded_fallback");
        File embed = new File(workRoot, "embed-src-" + (++seq));
        writeFile(new File(embed, "www/index.html"), "embedded-index".getBytes(StandardCharsets.UTF_8));
        writeFile(new File(embed, "www/css/app.css"), "embedded-css".getBytes(StandardCharsets.UTF_8));
        writeFile(new File(embed, "www.version"), "embed-1".getBytes(StandardCharsets.UTF_8));
        writeFile(new File(embed, "www.build_timestamp"), String.valueOf(T0).getBytes(StandardCharsets.UTF_8));
        Capture cap = new Capture();
        String start = Provisioner.provision(new TestContext(dir, new AssetManager(embed)), cap);
        check("20 embedded copied", new File(dir, "www/index.html").isFile());
        check("20 embedded content", fileEquals(new File(dir, "www/index.html"), "embedded-index"));
        check("20 invalid remote warned", cap.hasWarning("Invalid remote manifest"));
        check("20 fallback start uri", start.contains("/www/index.html"));
    }

    private static void scenario21UppercaseSha() throws Exception {
        byte[] index = content(T1, "index");
        byte[] css = content(T1, "css");
        server.setAsset("www/index.html", index);
        server.setAsset("www/css/style.css", css);
        server.setOmitted(new HashSet<String>());
        server.setTruncated(new HashSet<String>());
        server.setNotModified(false);
        String upperIndex = sha256(index).toUpperCase();
        String upperCss = sha256(css).toUpperCase();
        server.setManifest(manifestBody(null, T1, "www/index.html",
                assetWith(index, index.length, upperIndex)
                        .concat(","+assetWith(css, css.length, upperCss, "www/css/style.css"))));
        File dir = freshDir("uppercase_sha");
        Capture cap = new Capture();
        Provisioner.provision(new TestContext(dir, noAssets()), cap);
        check("21 uppercase sha accepted", cap.warnings.isEmpty());
        check("21 committed", new File(dir, "www/index.html").isFile());
    }

    private static void scenario22NotModifiedReuse() throws Exception {
        ServerState state = servo(T1);
        File dir = freshDir("not_modified");
        state.provisional();
        Provisioner.provision(new TestContext(dir, noAssets()), new Capture());
        int getsAfterFirst = server.manifestGets();
        server.setNotModified(true);
        Capture cap = new Capture();
        Provisioner.provision(new TestContext(dir, noAssets()), cap);
        check("22 IMS header sent", server.lastIfModifiedSince() != null);
        check("22 304 avoided full GET", server.manifestGets() == getsAfterFirst + 1);
        check("22 no warnings", cap.warnings.isEmpty());
        check("22 metadata still written", readInstalledTimestamp(dir) == T1);
    }

    private static void assertRejected(String name, String detail, String json) throws Exception {
        server.setManifest(json);
        server.setOmitted(new HashSet<String>());
        server.setTruncated(new HashSet<String>());
        server.setNotModified(false);
        File dir = freshDir(name);
        Capture cap = new Capture();
        Provisioner.provision(new TestContext(dir, noAssets()), cap);
        check(name + " rejected (" + detail + ")", cap.hasWarning("Invalid remote manifest"));
        check(name + " no metadata commit", !new File(dir, "installed.manifest.json").exists());
        check(name + " no www activation", !new File(dir, "www").isDirectory());
    }

    // ------------------------------------------------------------------
    // Manifest / server state helpers. A ServerState encodes the asset
    // contents; call provisional() to publish them to the shared server.
    // ------------------------------------------------------------------

    private static final long T0 = 1000L;
    private static final long T1 = 2000L;
    private static final long T2 = 3000L;

    private static final class ServerState {
        byte[] index = content(T1, "index");
        byte[] css = content(T1, "css");
        long ts = T1;

        ServerState(byte[] index, byte[] css, long ts) {
            this.index = index;
            this.css = css;
            this.ts = ts;
        }

        void provisional() {
            server.setAsset("www/index.html", index);
            server.setAsset("www/css/style.css", css);
            server.setOmitted(new HashSet<String>());
            server.setTruncated(new HashSet<String>());
            server.setNotModified(false);
            server.setManifest(manifestBody(null, ts, "www/index.html",
                    assetWith(index, index.length, sha256(index))
                            .concat(","+assetWith(css, css.length, sha256(css), "www/css/style.css"))));
        }
    }

    private static ServerState servo(long ts) {
        return new ServerState(content(ts, "index"), content(ts, "css"), ts);
    }

    private static byte[] content(long ts, String name) {
        return ("body-" + name + "-" + ts).getBytes(StandardCharsets.UTF_8);
    }

    // Builds a JSON manifest from an already-JSON asset fragment (concat of
    // asset entries, or "" to force a missing/invalid asset array).
    private static String manifestBody(String[] dropFields, long ts, String start, String assetsFragment) {
        try {
            JSONObject m = new JSONObject();
            m.put("timestamp", ts);
            m.put("start", start);
            m.put("assets", new org.json.JSONArray(assetsFragment.isEmpty() ? "[]" : "[" + assetsFragment + "]"));
            if (dropFields != null) {
                for (String field : dropFields) {
                    m.remove(field);
                }
            }
            return m.toString();
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    private static String assetIndex(long ts) {
        byte[] index = content(ts, "index");
        return assetWith(index, index.length, sha256(index));
    }

    private static String asset(String path, String body) {
        byte[] data = body.getBytes(StandardCharsets.UTF_8);
        return assetWith(data, data.length, sha256(data), path);
    }

    private static String assetWith(byte[] data, long size, String sha) {
        return assetWith(data, size, sha, "www/index.html");
    }

    private static String assetWith(byte[] data, long size, String sha, String path) {
        return "{\"path\":\"" + path + "\",\"size_bytes\":" + size + ",\"sha256\":\"" + sha + "\"}";
    }

    private static long readInstalledTimestamp(File dir) throws Exception {
        File f = new File(dir, "installed.manifest.json");
        if (!f.isFile()) {
            return -1;
        }
        return new JSONObject(new String(fileBytes(f), StandardCharsets.UTF_8)).optLong("timestamp", -1);
    }

    private static List<File> manifestCacheFiles(File dir) {
        List<File> out = new ArrayList<File>();
        File[] files = dir.listFiles();
        if (files != null) {
            for (File f : files) {
                if (f.getName().startsWith("manifest.") && f.getName().endsWith(".json")) {
                    out.add(f);
                }
            }
        }
        return out;
    }

    private static void startUriValid(File dir) throws Exception {
        Capture cap = new Capture();
        String start = Provisioner.provision(new TestContext(dir, noAssets()), cap);
        check("01 start uri resolves to committed start", start.contains("/www/index.html"));
    }

    private static android.content.res.AssetManager noAssets() {
        return new AssetManager(null);
    }

    private static Set<String> singleton(String s) {
        Set<String> set = new HashSet<String>();
        set.add(s);
        return set;
    }

    private static File freshDir(String name) throws IOException {
        File dir = new File(workRoot, "case-" + name + "-" + (++seq));
        if (!dir.mkdirs() && !dir.isDirectory()) {
            throw new IOException("cannot create " + dir);
        }
        return dir;
    }

    private static void writeFile(File f, byte[] content) throws IOException {
        f.getParentFile().mkdirs();
        FileOutputStream out = new FileOutputStream(f);
        try {
            out.write(content);
        } finally {
            out.close();
        }
    }

    private static byte[] fileBytes(File f) throws IOException {
        if (!f.isFile()) {
            return new byte[0];
        }
        InputStream in = new FileInputStream(f);
        try {
            java.io.ByteArrayOutputStream buf = new java.io.ByteArrayOutputStream();
            byte[] tmp = new byte[4096];
            int n;
            while ((n = in.read(tmp)) > 0) {
                buf.write(tmp, 0, n);
            }
            return buf.toByteArray();
        } finally {
            in.close();
        }
    }

    private static boolean fileEquals(File f, String expected) throws IOException {
        return new String(fileBytes(f), StandardCharsets.UTF_8).equals(expected);
    }

    private static boolean fileContentEquals(File f, byte[] expected) throws IOException {
        byte[] got = fileBytes(f);
        if (got.length != expected.length) {
            return false;
        }
        for (int i = 0; i < got.length; i++) {
            if (got[i] != expected[i]) {
                return false;
            }
        }
        return true;
    }

    private static String sha256(byte[] data) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] digest = md.digest(data);
            StringBuilder sb = new StringBuilder();
            for (byte b : digest) {
                sb.append(String.format("%02x", b));
            }
            return sb.toString();
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    private static void check(String name, boolean cond) {
        if (cond) {
            passed++;
            System.out.println("PASS " + name);
        } else {
            failed++;
            System.out.println("FAIL " + name);
        }
    }

    private ProvisionTest() {}
}