package android.content.res;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;

public class AssetManager {
    private final File root;

    public AssetManager(File root) {
        this.root = root;
    }

    public InputStream open(String fileName) throws IOException {
        if (root == null) {
            throw new IOException("no embedded assets");
        }
        File f = new File(root, fileName);
        if (!f.isFile()) {
            throw new IOException("missing asset: " + fileName);
        }
        return new FileInputStream(f);
    }

    public String[] list(String path) throws IOException {
        if (root == null) {
            throw new IOException("no embedded assets");
        }
        File d = new File(root, path);
        if (!d.exists()) {
            throw new IOException("missing asset directory: " + path);
        }
        if (!d.isDirectory()) {
            return new String[0];
        }
        String[] names = d.list();
        return names == null ? new String[0] : names;
    }
}