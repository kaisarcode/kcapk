package android.content;

import android.content.res.AssetManager;

import java.io.File;

public abstract class Context {
    public abstract File getFilesDir();
    public abstract AssetManager getAssets();
}