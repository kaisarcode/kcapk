package com.kaisarcode.demo;

import android.content.Context;
import android.content.res.AssetManager;

import java.io.File;

public class TestContext extends Context {
    private final File filesDir;
    private final AssetManager assets;

    public TestContext(File filesDir, AssetManager assets) {
        this.filesDir = filesDir;
        this.assets = assets;
    }

    @Override
    public File getFilesDir() {
        return filesDir;
    }

    @Override
    public AssetManager getAssets() {
        return assets;
    }
}