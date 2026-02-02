package com.smart_scope;

import androidx.annotation.*;
import android.os.Bundle;
import android.content.ComponentCallbacks2;
import android.content.res.Configuration;
import android.util.Log;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugins.GeneratedPluginRegistrant;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity implements ComponentCallbacks2 {
    private static final String TAG = "MainActivity";
    private Camera2Plugin camera2Plugin;
    private MethodChannel memoryChannel;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        GeneratedPluginRegistrant.registerWith(flutterEngine);
        camera2Plugin = new Camera2Plugin();
        camera2Plugin.onAttachedToEngine(flutterEngine.getDartExecutor().getBinaryMessenger(), this);
        camera2Plugin.onAttachedToActivity(this);

        flutterEngine.getPlatformViewsController().getRegistry()
                .registerViewFactory("smart_scope/camera2_preview", new Camera2ViewFactory(camera2Plugin));

        memoryChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), "smart_scope/memory");
        memoryChannel.setMethodCallHandler((call, result) -> {
            if (call.method.equals("releaseMemory")) {
                System.gc();
                result.success(true);
            } else {
                result.notImplemented();
            }
        });
    }
    
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        registerComponentCallbacks(this);
    }

    @Override
    public void onTrimMemory(int level) {
        Log.d(TAG, "onTrimMemory: " + level);
        
        if (level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL || 
            level >= ComponentCallbacks2.TRIM_MEMORY_COMPLETE) {
            if (camera2Plugin != null) {
                try {
                    camera2Plugin.onMethodCall(
                        new io.flutter.plugin.common.MethodCall("disposeCamera", null),
                        new io.flutter.plugin.common.MethodChannel.Result() {
                            @Override
                            public void success(Object result) {
                                Log.d(TAG, "Camera resource released successfully");
                            }
                            
                            @Override
                            public void error(String errorCode, String errorMessage, Object errorDetails) {
                                Log.e(TAG, "Camera resource release failed: " + errorMessage);
                            }
                            
                            @Override
                            public void notImplemented() {
                                Log.e(TAG, "Method not implemented");
                            }
                        }
                    );
                } catch (Exception e) {
                    Log.e(TAG, "Error releasing camera resources: " + e.getMessage());
                }
            }
            
            if (memoryChannel != null) {
                memoryChannel.invokeMethod("onLowMemory", null);
            }
            
            System.gc();
        }
    }
    
    @Override
    public void onLowMemory() {
        super.onLowMemory();
        Log.d(TAG, "onLowMemory");
        
        if (camera2Plugin != null) {
            try {
                camera2Plugin.onMethodCall(
                    new io.flutter.plugin.common.MethodCall("disposeCamera", null),
                    new io.flutter.plugin.common.MethodChannel.Result() {
                        @Override
                        public void success(Object result) {
                            Log.d(TAG, "Camera resource released successfully");
                        }
                        
                        @Override
                        public void error(String errorCode, String errorMessage, Object errorDetails) {
                            Log.e(TAG, "Camera resource release failed: " + errorMessage);
                        }
                        
                        @Override
                        public void notImplemented() {
                            Log.e(TAG, "Method not implemented");
                        }
                    }
                );
            } catch (Exception e) {
                Log.e(TAG, "Error releasing camera resources: " + e.getMessage());
            }
        }
        
        if (memoryChannel != null) {
            memoryChannel.invokeMethod("onLowMemory", null);
        }
        
        System.gc();
    }
    
    @Override
    public void onConfigurationChanged(@NonNull Configuration newConfig) {
        super.onConfigurationChanged(newConfig);
    }

    @Override
    protected void onStop() {
        super.onStop();
        if (camera2Plugin != null) {
            try {
                camera2Plugin.onMethodCall(
                    new io.flutter.plugin.common.MethodCall("disposeCamera", null),
                    new io.flutter.plugin.common.MethodChannel.Result() {
                        @Override
                        public void success(Object result) {
                            Log.d(TAG, "Camera resource released successfully");
                        }
                        
                        @Override
                        public void error(String errorCode, String errorMessage, Object errorDetails) {
                            Log.e(TAG, "Camera resource release failed: " + errorMessage);
                        }
                        
                        @Override
                        public void notImplemented() {
                            Log.e(TAG, "Method not implemented");
                        }
                    }
                );
            } catch (Exception e) {
                Log.e(TAG, "Error releasing camera resources: " + e.getMessage());
            }
        }
    }

    @Override
    public void onDestroy() {
        unregisterComponentCallbacks(this);
        
        if (camera2Plugin != null) {
            camera2Plugin.onDetachedFromActivity();
            BinaryMessenger messenger = getFlutterEngine().getDartExecutor().getBinaryMessenger();
            camera2Plugin.onDetachedFromEngine(messenger);
            camera2Plugin = null;
        }
        
        if (memoryChannel != null) {
            memoryChannel.setMethodCallHandler(null);
            memoryChannel = null;
        }
        
        System.gc();
        
        super.onDestroy();
    }
}