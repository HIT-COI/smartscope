package com.smart_scope;

import android.content.Context;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.util.Map;

import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;

public class Camera2ViewFactory extends PlatformViewFactory {
    private final Camera2Plugin camera2Plugin;

    public Camera2ViewFactory(Camera2Plugin camera2Plugin) {
        super(StandardMessageCodec.INSTANCE);
        this.camera2Plugin = camera2Plugin;
    }

    @NonNull
    @Override
    public PlatformView create(Context context, int viewId, @Nullable Object args) {
        @SuppressWarnings("unchecked")
        final Map<String, Object> creationParams = (args == null) ? null : (Map<String, Object>) args;
        
        boolean useRearCamera = true;
        if (creationParams != null && creationParams.containsKey("useRearCamera")) {
            useRearCamera = (boolean) creationParams.get("useRearCamera");
        }
        
        String pageId = "default";
        if (creationParams != null && creationParams.containsKey("pageId")) {
            pageId = (String) creationParams.get("pageId");
        }
        
        return new Camera2View(context, viewId, useRearCamera, pageId, camera2Plugin);
    }
} 