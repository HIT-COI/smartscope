package com.smart_scope;

import android.content.Context;
import android.view.View;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;

import io.flutter.plugin.platform.PlatformView;

public class Camera2View implements PlatformView {
    private final FrameLayout layout;
    private final Camera2Plugin camera2Plugin;
    private final int viewId;

    Camera2View(@NonNull Context context, int id, boolean useRearCamera, Camera2Plugin camera2Plugin) {
        this(context, id, useRearCamera, "default", camera2Plugin);
    }
    
    Camera2View(@NonNull Context context, int id, boolean useRearCamera, String pageId, Camera2Plugin camera2Plugin) {
        this.camera2Plugin = camera2Plugin;
        this.viewId = id;

        layout = new FrameLayout(context);
        layout.setLayoutParams(new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT));

        layout.post(() -> {
            if (layout.getWindowToken() != null) {
                camera2Plugin.createNewTextureView(context, layout, useRearCamera, viewId, pageId);
            }
        });
    }

    @NonNull
    @Override
    public View getView() {
        return layout;
    }

    @Override
    public void dispose() {
        camera2Plugin.disposeTextureView(viewId);
        android.util.Log.d("Camera2View", "dispose: View released, ID: " + viewId);
    }
}