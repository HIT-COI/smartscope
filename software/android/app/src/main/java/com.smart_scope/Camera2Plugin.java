package com.smart_scope;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.graphics.ImageFormat;
import android.graphics.Rect;
import android.graphics.SurfaceTexture;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;

import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureFailure;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.CaptureResult;
import android.hardware.camera2.TotalCaptureResult;
import android.hardware.camera2.params.MeteringRectangle;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.media.Image;
import android.media.ImageReader;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.HandlerThread;
import android.provider.MediaStore;
import android.util.Log;
import android.util.Size;
import android.util.SparseArray;
import android.view.Surface;
import android.view.TextureView;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import androidx.annotation.*;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.text.SimpleDateFormat;
import java.util.Arrays;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

public class Camera2Plugin implements FlutterPlugin, MethodCallHandler, ActivityAware {
    private static final String TAG = "Camera2Plugin";
    private static final String CHANNEL_NAME = "smart_scope/camera2";
    private static final String VIEW_TYPE = "smart_scope/camera2_preview";

    private MethodChannel channel;
    private Activity activity;
    private Context context;

    private final SparseArray<CameraViewInfo> textureViews = new SparseArray<>();
    private int activeViewId = -1;

    private CameraDevice cameraDevice;
    private CameraCaptureSession cameraCaptureSession;
    private CaptureRequest.Builder captureRequestBuilder;
    private String cameraId;
    private Size imageDimension;
    private ImageReader imageReader;

    private Map<String, Object> currentIlluminationParams = null;

    private HandlerThread backgroundThread;
    private Handler backgroundHandler;

    private Semaphore cameraOpenCloseLock = new Semaphore(1);

    private Map<String, CameraParams> pageParamsMap = new HashMap<>();

    private CameraParams getPageParams(String pageId) {
        if (pageId == null || pageId.isEmpty()) {
            pageId = "default";
        }

        if (!pageParamsMap.containsKey(pageId)) {
            pageParamsMap.put(pageId, new CameraParams());
        }

        return pageParamsMap.get(pageId);
    }

    private String activePageId = "default";

    private static class CameraParams {
        boolean useRearCamera = true;
        float zoomLevel = 1.0f;
        boolean autoExposure = true;
        long exposureTime = 0;
        boolean highResolutionMode = true;
        boolean hdrMode = false;
        int isoValue = 0;

        CameraParams copy() {
            CameraParams params = new CameraParams();
            params.useRearCamera = this.useRearCamera;
            params.zoomLevel = this.zoomLevel;
            params.autoExposure = this.autoExposure;
            params.exposureTime = this.exposureTime;
            params.highResolutionMode = this.highResolutionMode;
            params.hdrMode = this.hdrMode;
            params.isoValue = this.isoValue;
            return params;
        }
    }

    private Result pendingTakePictureResult;

    private boolean useRearCamera = true;
    private float currentZoom = 1.0f;
    private boolean autoExposure = true;
    private long exposureTime = 0;
    private boolean highResolutionMode = true;
    private boolean hdrMode = false;

    private static class CameraViewInfo {
        final TextureView textureView;
        final FrameLayout container;
        final boolean useRearCamera;
        final String pageId;

        CameraViewInfo(TextureView textureView, FrameLayout container, boolean useRearCamera) {
            this(textureView, container, useRearCamera, "default");
        }

        CameraViewInfo(TextureView textureView, FrameLayout container, boolean useRearCamera, String pageId) {
            this.textureView = textureView;
            this.container = container;
            this.useRearCamera = useRearCamera;
            this.pageId = pageId;
        }
    }

    void createNewTextureView(Context context, FrameLayout container, boolean useRearCamera, int viewId, String pageId) {
        if (pageId == null || pageId.isEmpty()) {
            pageId = "default";
        }

        Log.d(TAG, "Creating new TextureView, ID: " + viewId + ", pageId: " + pageId);

        this.activePageId = pageId;

        CameraViewInfo existingView = textureViews.get(viewId);
        if (existingView != null) {
            Log.d(TAG, "View with same ID exists, destroying it: " + viewId);
            CameraViewInfo viewInfo = textureViews.get(viewId);
            if (viewInfo != null && viewInfo.textureView != null) {
                textureViews.remove(viewId);
                Log.d(TAG, "Removed view from mapping: " + viewId);
            }
        }

        try {
            container.removeAllViews();
        } catch (Exception e) {
            Log.e(TAG, "Error clearing container views: " + e.getMessage());
        }

        try {
            System.gc();

            TextureView textureView = new TextureView(context);
            textureView.setLayoutParams(new ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT));

            final String finalPageId = pageId;

            textureView.setSurfaceTextureListener(new TextureView.SurfaceTextureListener() {
                @Override
                public void onSurfaceTextureAvailable(SurfaceTexture surfaceTexture, int width, int height) {
                    Log.d(TAG, "Texture available, ID: " + viewId + ", size: " + width + "x" + height);

                    try {
                        surfaceTexture.setDefaultBufferSize(width, height);
                    } catch (Exception e) {
                        Log.e(TAG, "Error setting SurfaceTexture default buffer size: " + e.getMessage());
                    }

                    CameraViewInfo viewInfo = new CameraViewInfo(textureView, container, useRearCamera, finalPageId);
                    textureViews.put(viewId, viewInfo);

                    activePageId = finalPageId;

                    Log.d(TAG, "View info added, ID: " + viewId + ", pageId: " + finalPageId +
                            ", activePageId: " + activePageId);

                    if (activeViewId == viewId || activeViewId == -1) {
                        activeViewId = viewId;
                        startBackgroundThread();
                        openCamera(viewId);
                    }
                }

                @Override
                public void onSurfaceTextureSizeChanged(SurfaceTexture surfaceTexture, int width, int height) {
                    Log.d(TAG, "Texture size changed, ID: " + viewId + ", size: " + width + "x" + height);
                    if (activeViewId == viewId && cameraDevice != null && cameraCaptureSession != null) {
                        updateCameraPreview();
                    }
                }

                @Override
                public boolean onSurfaceTextureDestroyed(SurfaceTexture surfaceTexture) {
                    Log.d(TAG, "Texture destroyed, ID: " + viewId);
                    if (activeViewId == viewId) {
                        closeCamera();
                        stopBackgroundThread();
                        activeViewId = -1;
                    }

                    return false;
                }

                @Override
                public void onSurfaceTextureUpdated(SurfaceTexture surfaceTexture) {
                }
            });

            textureView.setOnTouchListener((view, event) -> {
                if (event.getAction() == android.view.MotionEvent.ACTION_DOWN) {
                    if (activeViewId == viewId && cameraDevice != null && cameraCaptureSession != null) {
                        performTouchFocus(viewId, event.getX(), event.getY());
                    }
                }
                return true;
            });

            container.addView(textureView);

            if (textureView.isAvailable()) {
                Log.d(TAG, "Texture already available, ID: " + viewId + ", initializing camera directly");
                activeViewId = viewId;
                startBackgroundThread();
                openCamera(viewId);
            }
        } catch (Exception e) {
            Log.e(TAG, "Error creating TextureView: " + e.getMessage(), e);
        }
    }

    void createNewTextureView(Context context, FrameLayout container, boolean useRearCamera, int viewId) {
        createNewTextureView(context, container, useRearCamera, viewId, "default");
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPlugin.FlutterPluginBinding flutterPluginBinding) {
        Log.d(TAG, "Attaching to engine");

        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), CHANNEL_NAME);
        channel.setMethodCallHandler(this);

        context = flutterPluginBinding.getApplicationContext();

        flutterPluginBinding.getPlatformViewRegistry()
                .registerViewFactory(VIEW_TYPE, new Camera2ViewFactory(this));
    }
    
    public void onAttachedToEngine(io.flutter.plugin.common.BinaryMessenger messenger, Context ctx) {
        channel = new MethodChannel(messenger, CHANNEL_NAME);
        channel.setMethodCallHandler(this);

        context = ctx;
    }

    private void cleanupResources() {
        closeCamera();
        stopBackgroundThread();
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
        context = null;

        textureViews.clear();

        Log.d(TAG, "Plugin detached from engine");
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPlugin.FlutterPluginBinding binding) {
        cleanupResources();
    }
    
    public void onDetachedFromEngine(io.flutter.plugin.common.BinaryMessenger messenger) {
        cleanupResources();
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
        Log.d(TAG, "Plugin attached to activity");
    }

    public void onAttachedToActivity(Activity act) {
        activity = act;
        Log.d(TAG, "Plugin attached to activity");
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        Log.d(TAG, "Plugin detached from activity for config changes");
        closeCamera();
        stopBackgroundThread();
        activity = null;
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        Log.d(TAG, "Plugin reattached to activity for config changes");
        activity = binding.getActivity();

        if (activeViewId != -1) {
            CameraViewInfo viewInfo = textureViews.get(activeViewId);
            if (viewInfo != null && viewInfo.textureView.isAvailable()) {
                startBackgroundThread();
                openCamera(activeViewId);
            }
        }
    }

    @Override
    public void onDetachedFromActivity() {
        Log.d(TAG, "Plugin detached from activity");
        closeCamera();
        stopBackgroundThread();
        activity = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        if (!call.method.equals("initCamera") && !call.method.equals("hasRequiredPermissions") &&
                context == null) {
            result.error("CAMERA_UNINITIALIZED", "Camera not initialized", null);
            return;
        }

        try {
            String pageId = call.argument("pageId");
            if (pageId == null || pageId.isEmpty()) {
                pageId = "default";
            }

            CameraParams params = getPageParams(pageId);

            switch (call.method) {
                case "initCamera":
                    try {
                        Boolean useRearCamera = call.argument("useRearCamera");
                        Boolean highResolutionMode = call.argument("highResolutionMode");
                        Boolean hdrMode = call.argument("hdrMode");
                        
                        Boolean useFixedCameraParams = call.argument("useFixedCameraParams");
                        Integer isoValue = call.argument("isoValue");
                        Integer exposureTimeUs = call.argument("exposureTimeUs");

                        if (useRearCamera != null) params.useRearCamera = useRearCamera;
                        if (highResolutionMode != null) params.highResolutionMode = highResolutionMode;
                        if (hdrMode != null) params.hdrMode = hdrMode;
                        
                        if (useFixedCameraParams != null && useFixedCameraParams) {
                            if (exposureTimeUs != null && exposureTimeUs > 0) {
                                params.exposureTime = exposureTimeUs * 1000L;
                                params.autoExposure = false;
                                Log.d(TAG, "Set fixed exposure time: " + params.exposureTime + " ns");
                            }
                            
                            if (isoValue != null && isoValue > 0) {
                                params.isoValue = isoValue;
                                Log.d(TAG, "Set fixed ISO value: " + params.isoValue);
                            }
                        }

                        activePageId = pageId;

                        if (activeViewId != -1) {
                            CameraViewInfo viewInfo = textureViews.get(activeViewId);
                            if (viewInfo != null) {
                                viewInfo = new CameraViewInfo(
                                        viewInfo.textureView,
                                        viewInfo.container,
                                        params.useRearCamera,
                                        pageId
                                );
                                textureViews.put(activeViewId, viewInfo);

                                applyActivePageParams();
                                openCamera(activeViewId);
                                result.success(true);
                                return;
                            }
                        }

                        result.success(true);
                    } catch (Exception e) {
                        Log.e(TAG, "Init camera failed: " + e.getMessage());
                        result.error("INIT_CAMERA_FAILED", e.getMessage(), null);
                    }
                    break;

                case "disposeCamera":
                    try {
                        if (activePageId.equals(pageId)) {
                            closeCamera();
                            stopBackgroundThread();
                        }

                        pageParamsMap.remove(pageId);

                        Log.d(TAG, "Cleaning views related to pageId=" + pageId);
                        for (int i = 0; i < textureViews.size(); i++) {
                            int viewId = textureViews.keyAt(i);
                            CameraViewInfo viewInfo = textureViews.valueAt(i);

                            if (viewInfo != null && pageId.equals(viewInfo.pageId)) {
                                Log.d(TAG, "Found related view, ID: " + viewId + ", pageId: " + viewInfo.pageId);
                                disposeTextureView(viewId);
                                i--;
                            }
                        }

                        result.success(true);
                    } catch (Exception e) {
                        Log.e(TAG, "Dispose camera failed: " + e.getMessage());
                        result.error("DISPOSE_CAMERA_FAILED", e.getMessage(), null);
                    }
                    break;

                case "switchCamera":
                    Boolean useRearCamera = call.argument("useRearCamera");
                    if (useRearCamera != null) {
                        params.useRearCamera = useRearCamera;
                    }

                    if (pageId.equals(activePageId) && activeViewId != -1) {
                        CameraViewInfo viewInfo = textureViews.get(activeViewId);
                        if (viewInfo != null) {
                            viewInfo = new CameraViewInfo(
                                    viewInfo.textureView,
                                    viewInfo.container,
                                    params.useRearCamera,
                                    pageId
                            );
                            textureViews.put(activeViewId, viewInfo);

                            applyActivePageParams();
                            restartCamera();
                        }
                    }

                    result.success(true);
                    break;

                case "getCameraInfo":
                    Map<String, Object> cameraInfo = getCameraInfo();
                    result.success(cameraInfo);
                    break;

                case "setZoomLevel":
                    Object zoomLevelObj = call.argument("zoomLevel");
                    if (zoomLevelObj != null) {
                        float zoomLevel;
                        if (zoomLevelObj instanceof Float) {
                            zoomLevel = (Float) zoomLevelObj;
                        } else if (zoomLevelObj instanceof Double) {
                            zoomLevel = ((Double) zoomLevelObj).floatValue();
                        } else if (zoomLevelObj instanceof Integer) {
                            zoomLevel = ((Integer) zoomLevelObj).floatValue();
                        } else {
                            try {
                                zoomLevel = Float.parseFloat(zoomLevelObj.toString());
                            } catch (NumberFormatException e) {
                                Log.e(TAG, "Cannot convert value to float: " + zoomLevelObj);
                                result.error("INVALID_ZOOM", "Invalid zoom value", null);
                                return;
                            }
                        }

                        params.zoomLevel = zoomLevel;

                        if (pageId.equals(activePageId)) {
                            applyActivePageParams();
                            updateCameraPreview();
                        }

                        result.success(true);
                    } else {
                        result.success(false);
                    }
                    break;

                case "setExposureTime":
                    Integer exposureTimeInt = call.argument("exposureTime");
                    if (exposureTimeInt != null) {
                        params.exposureTime = exposureTimeInt.longValue();
                        params.autoExposure = false;

                        if (pageId.equals(activePageId)) {
                            applyActivePageParams();
                            updateCameraPreview();
                        }

                        result.success(true);
                    } else {
                        result.success(false);
                    }
                    break;

                case "setAutoExposure":
                    Boolean autoExposure = call.argument("enabled");
                    if (autoExposure != null) {
                        params.autoExposure = autoExposure;
                        if (autoExposure) {
                            params.exposureTime = 0;
                        }

                        if (pageId.equals(activePageId)) {
                            applyActivePageParams();
                            updateCameraPreview();
                        }

                        result.success(true);
                    } else {
                        result.success(false);
                    }
                    break;

                case "setHighResolutionMode":
                    Boolean highResMode = call.argument("enabled");
                    if (highResMode != null) {
                        params.highResolutionMode = highResMode;

                        if (pageId.equals(activePageId)) {
                            applyActivePageParams();
                            restartCamera();
                        }

                        result.success(true);
                    } else {
                        result.success(false);
                    }
                    break;

                case "setHDRMode":
                    Boolean hdrEnabled = call.argument("enabled");
                    if (hdrEnabled != null) {
                        params.hdrMode = hdrEnabled;

                        if (pageId.equals(activePageId)) {
                            applyActivePageParams();
                            updateCameraPreview();
                        }

                        result.success(true);
                    } else {
                        result.success(false);
                    }
                    break;

                case "takePicture":
                    Boolean hdrForPhoto = call.argument("hdrMode");
                    if (hdrForPhoto != null) {
                        params.hdrMode = hdrForPhoto;
                    }

                    Boolean highResForPhoto = call.argument("highResolutionMode");
                    if (highResForPhoto != null) {
                        params.highResolutionMode = highResForPhoto;
                    }
                    
                    Boolean useFixedCameraParams = call.argument("useFixedCameraParams");
                    Integer isoValue = call.argument("isoValue");
                    Integer exposureTimeUs = call.argument("exposureTimeUs");
                    
                    if (useFixedCameraParams != null && useFixedCameraParams) {
                        if (exposureTimeUs != null && exposureTimeUs > 0) {
                            params.exposureTime = exposureTimeUs * 1000L;
                            params.autoExposure = false;
                            Log.d(TAG, "Set fixed exposure time for capture: " + params.exposureTime + " ns");
                        }
                        
                        if (isoValue != null && isoValue > 0) {
                            params.isoValue = isoValue;
                            Log.d(TAG, "Set fixed ISO value for capture: " + params.isoValue);
                        }
                    } else {
                        params.autoExposure = true;
                        params.exposureTime = 0;
                        params.isoValue = 0;
                        Log.d(TAG, "Using auto exposure mode for capture");
                    }

                    Map<String, Object> illuminationParams = call.argument("illuminationParams");
                    if (illuminationParams != null) {
                        Log.d(TAG, "onMethodCall.takePicture: Received illumination params: " + illuminationParams);
                        if (illuminationParams.containsKey("type")) {
                            Log.d(TAG, "Illumination type: " + illuminationParams.get("type"));
                        }
                        if (illuminationParams.containsKey("radius")) {
                            Log.d(TAG, "Radius: " + illuminationParams.get("radius"));
                        }
                        if (illuminationParams.containsKey("spacing")) {
                            Log.d(TAG, "Spacing: " + illuminationParams.get("spacing"));
                        }
                    } else {
                        Log.d(TAG, "onMethodCall.takePicture: No illumination params received");
                    }

                    if (pageId.equals(activePageId)) {
                        applyActivePageParams();
                        Log.d(TAG, "Using current active page params: " + pageId);
                    } else {
                        Log.d(TAG, "Temporarily switching page: from " + activePageId + " to " + pageId);
                        String oldPageId = activePageId;
                        activePageId = pageId;
                        applyActivePageParams();

                        takePicture(result, illuminationParams);
                        activePageId = oldPageId;
                        applyActivePageParams();
                        return;
                    }

                    takePicture(result, illuminationParams);
                    break;

                case "performManualFocus":
                    Integer viewId = call.argument("viewId");
                    Double x = call.argument("x");
                    Double y = call.argument("y");

                    if (viewId != null && x != null && y != null) {
                        performTouchFocus(viewId, x.floatValue(), y.floatValue());
                        result.success(true);
                    } else {
                        result.error("INVALID_ARGS", "Valid view ID and coordinates required", null);
                    }
                    break;

                case "loadImageFromContentUri":
                    String uri = call.argument("uri");
                    if (uri != null) {
                        try {
                            byte[] bytes = loadImageBytesFromContentUri(Uri.parse(uri));
                            if (bytes != null) {
                                result.success(bytes);
                            } else {
                                result.error("LOAD_FAILED", "Cannot load image data", null);
                            }
                        } catch (Exception e) {
                            result.error("LOAD_ERROR", "Error loading image data: " + e.getMessage(), null);
                        }
                    } else {
                        result.error("INVALID_URI", "Invalid URI", null);
                    }
                    break;

                case "startIntensityMonitoring":
                    startIntensityMonitoring(result);
                    break;

                case "stopIntensityMonitoring":
                    stopIntensityMonitoring(result);
                    break;

                case "getCurrentLightIntensity":
                    getCurrentLightIntensity(result);
                    break;

                case "setCameraParams":
                    Boolean fixedParams = call.argument("useFixedCameraParams");
                    Integer iso = call.argument("isoValue");
                    Integer expTime = call.argument("exposureTimeUs");
                    
                    if (fixedParams != null && fixedParams && pageId != null) {
                        CameraParams cParams = getPageParams(pageId);
                        
                        if (iso != null && iso > 0) {
                            cParams.isoValue = iso;
                            Log.d(TAG, "Set ISO value separately: " + iso);
                        }
                        
                        if (expTime != null && expTime > 0) {
                            cParams.exposureTime = expTime * 1000L;
                            cParams.autoExposure = false;
                            Log.d(TAG, "Set exposure time separately: " + cParams.exposureTime + " ns");
                        } else {
                            cParams.autoExposure = true;
                        }
                        
                        if (pageId.equals(activePageId)) {
                            applyActivePageParams();
                            updateCameraPreview();
                        }
                        
                        result.success(true);
                    } else {
                        result.success(false);
                    }
                    break;

                default:
                    result.notImplemented();
                    break;
            }
        } catch (Exception e) {
            Log.e(TAG, "Plugin method call exception: " + e.getMessage());
            result.error("PLUGIN_ERROR", "Plugin method call exception: " + e.getMessage(), null);
        }
    }

    private void startBackgroundThread() {
        if (backgroundThread == null) {
            backgroundThread = new HandlerThread("Camera Background");
            backgroundThread.start();
            backgroundHandler = new Handler(backgroundThread.getLooper());
        }
    }

    private void stopBackgroundThread() {
        if (backgroundThread != null) {
            backgroundThread.quitSafely();
            try {
                backgroundThread.join();
                backgroundThread = null;
                backgroundHandler = null;
            } catch (InterruptedException e) {
                Log.e(TAG, "Error stopping background thread: " + e.getMessage());
            }
        }
    }

    private final CameraDevice.StateCallback stateCallback = new CameraDevice.StateCallback() {
        @Override
        public void onOpened(CameraDevice camera) {
            cameraOpenCloseLock.release();
            cameraDevice = camera;
            createCameraPreviewSession();
        }

        @Override
        public void onDisconnected(CameraDevice camera) {
            cameraOpenCloseLock.release();
            camera.close();
            cameraDevice = null;
        }

        @Override
        public void onError(CameraDevice camera, int error) {
            cameraOpenCloseLock.release();
            camera.close();
            cameraDevice = null;
            Log.e(TAG, "Camera device error: " + error);
        }
    };

    @SuppressLint("MissingPermission")
    private void openCamera(int viewId) {
        if (context == null) {
            Log.e(TAG, "Context is null");
            return;
        }

        CameraViewInfo viewInfo = textureViews.get(viewId);
        if (viewInfo == null || viewInfo.textureView == null) {
            Log.e(TAG, "Cannot find view info, ID: " + viewId);
            return;
        }

        TextureView textureView = viewInfo.textureView;
        useRearCamera = viewInfo.useRearCamera;

        if (!textureView.isAvailable()) {
            Log.e(TAG, "Texture view not available, ID: " + viewId);
            return;
        }

        try {
            if (cameraDevice != null) {
                closeCamera();
            }

            CameraManager manager = (CameraManager) context.getSystemService(Context.CAMERA_SERVICE);

            cameraId = getCameraId(manager, useRearCamera);
            if (cameraId == null) {
                Log.e(TAG, "Cannot get camera ID");
                return;
            }

            CameraCharacteristics characteristics = manager.getCameraCharacteristics(cameraId);

            StreamConfigurationMap map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);

            Size[] supportedResolutions = map.getOutputSizes(ImageFormat.JPEG);
            Size optimalSize = chooseOptimalSize(supportedResolutions, 8192, 6144);

            imageDimension = optimalSize != null ? optimalSize : new Size(4096, 3072);
            Log.d(TAG, "Final photo resolution: " + imageDimension.getWidth() + "x" + imageDimension.getHeight());
            if (map == null) {
                Log.e(TAG, "Cannot get camera configuration info");
                return;
            }

            imageDimension = getOptimalSize(map.getOutputSizes(SurfaceTexture.class));
            if (imageDimension == null) {
                Log.e(TAG, "Cannot get suitable camera preview size, operation cancelled");
                cameraOpenCloseLock.release();
                return;
            }
            Log.d(TAG, "Using resolution: " + imageDimension.getWidth() + "x" + imageDimension.getHeight());

            if (imageReader != null) {
                imageReader.close();
                imageReader = null;
            }

            Size captureSize = highResolutionMode ?
                    getBestCaptureSize(map.getOutputSizes(ImageFormat.JPEG)) :
                    imageDimension;

            if (captureSize == null) {
                Log.e(TAG, "Cannot get suitable photo size, operation cancelled");
                cameraOpenCloseLock.release();
                return;
            }

            Log.d(TAG, "Photo resolution: " + captureSize.getWidth() + "x" + captureSize.getHeight() +
                    " (High resolution mode: " + (highResolutionMode ? "ON" : "OFF") + ")");

            imageReader = ImageReader.newInstance(
                    captureSize.getWidth(),
                    captureSize.getHeight(),
                    ImageFormat.JPEG,
                    2,
                    2
            );

            imageReader.setOnImageAvailableListener(new ImageReader.OnImageAvailableListener() {
                @Override
                public void onImageAvailable(ImageReader reader) {
                    Image image = null;
                    try {
                        image = reader.acquireLatestImage();
                        if (image != null) {
                            Log.d(TAG, "ImageReader callback: global illumination params=" + (currentIlluminationParams != null ?
                                    currentIlluminationParams.toString() : "null"));

                            processImageCapture(image);
                        }
                    } catch (Exception e) {
                        Log.e(TAG, "Image processing error: " + e.getMessage(), e);
                    } finally {
                        if (image != null) {
                            image.close();
                        }
                    }
                }
            }, backgroundHandler);

            try {
                if (!cameraOpenCloseLock.tryAcquire(2500, TimeUnit.MILLISECONDS)) {
                    throw new RuntimeException("Camera lock timeout");
                }

                Log.d(TAG, "Opening camera: " + cameraId);
                manager.openCamera(cameraId, stateCallback, backgroundHandler);
            } catch (InterruptedException e) {
                Log.e(TAG, "Interrupted while opening camera: " + e.getMessage());
                cameraOpenCloseLock.release();
            }
        } catch (CameraAccessException e) {
            Log.e(TAG, "Cannot access camera: " + e.getMessage());
            cameraOpenCloseLock.release();
        } catch (Exception e) {
            Log.e(TAG, "Unexpected error while opening camera: " + e.getMessage());
            cameraOpenCloseLock.release();
        }
    }

    private String getCameraId(CameraManager manager, boolean useRearCamera) {
        try {
            for (String cameraId : manager.getCameraIdList()) {
                CameraCharacteristics characteristics = manager.getCameraCharacteristics(cameraId);
                Integer facing = characteristics.get(CameraCharacteristics.LENS_FACING);

                if (useRearCamera) {
                    if (facing != null && facing == CameraCharacteristics.LENS_FACING_BACK) {
                        return cameraId;
                    }
                } else {
                    if (facing != null && facing == CameraCharacteristics.LENS_FACING_FRONT) {
                        return cameraId;
                    }
                }
            }

            if (manager.getCameraIdList().length > 0) {
                return manager.getCameraIdList()[0];
            }
        } catch (CameraAccessException e) {
            Log.e(TAG, "Error getting camera ID: " + e.getMessage());
        }

        return null;
    }

    private void closeCamera() {
        try {
            cameraOpenCloseLock.acquire();

            if (cameraCaptureSession != null) {
                try {
                    cameraCaptureSession.stopRepeating();
                } catch (CameraAccessException | IllegalStateException e) {
                    Log.e(TAG, "Error stopping camera preview: " + e.getMessage());
                } finally {
                    try {
                        cameraCaptureSession.close();
                    } catch (Exception e) {
                        Log.e(TAG, "Error closing camera session: " + e.getMessage());
                    }
                    cameraCaptureSession = null;
                }
            }

            if (cameraDevice != null) {
                try {
                    cameraDevice.close();
                } catch (Exception e) {
                    Log.e(TAG, "Error closing camera device: " + e.getMessage());
                }
                cameraDevice = null;
            }

            if (imageReader != null) {
                try {
                    imageReader.close();
                } catch (Exception e) {
                    Log.e(TAG, "Error closing image reader: " + e.getMessage());
                }
                imageReader = null;
            }

            captureRequestBuilder = null;

            System.gc();

        } catch (InterruptedException e) {
            Log.e(TAG, "Interrupted while closing camera: " + e.getMessage());
        } finally {
            cameraOpenCloseLock.release();
        }
    }

    private void restartCamera() {
        closeCamera();
        openCamera(activeViewId);
    }

    private void createCameraPreviewSession() {
        if (activeViewId == -1) {
            Log.e(TAG, "No active view");
            return;
        }

        CameraViewInfo viewInfo = textureViews.get(activeViewId);
        if (viewInfo == null || viewInfo.textureView == null) {
            Log.e(TAG, "Cannot find active view info");
            return;
        }

        TextureView textureView = viewInfo.textureView;

        try {
            SurfaceTexture texture = textureView.getSurfaceTexture();
            if (texture == null) {
                Log.e(TAG, "Texture is null");
                return;
            }

            texture.setDefaultBufferSize(imageDimension.getWidth(), imageDimension.getHeight());

            Surface surface = null;
            try {
                surface = new Surface(texture);
            } catch (Exception e) {
                Log.e(TAG, "Failed to create Surface: " + e.getMessage());
                return;
            }

            final Surface previewSurface = surface;

            captureRequestBuilder = cameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
            captureRequestBuilder.addTarget(previewSurface);

            Surface imageReaderSurface = imageReader.getSurface();

            List<Surface> surfaces = Arrays.asList(previewSurface, imageReaderSurface);

            cameraDevice.createCaptureSession(
                    surfaces,
                    new CameraCaptureSession.StateCallback() {
                        @Override
                        public void onConfigured(@NonNull CameraCaptureSession session) {
                            if (cameraDevice == null) {
                                if (previewSurface != null) {
                                    try {
                                        previewSurface.release();
                                    } catch (Exception e) {
                                        Log.e(TAG, "Failed to release preview Surface: " + e.getMessage());
                                    }
                                }
                                return;
                            }

                            cameraCaptureSession = session;

                            try {
                                captureRequestBuilder.set(CaptureRequest.CONTROL_AF_MODE,
                                        CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
                                captureRequestBuilder.set(CaptureRequest.CONTROL_AE_MODE,
                                        autoExposure ? CaptureRequest.CONTROL_AE_MODE_ON : CaptureRequest.CONTROL_AE_MODE_OFF);

                                updateCameraPreview();
                            } catch (Exception e) {
                                Log.e(TAG, "Failed to configure camera params: " + e.getMessage());
                            }
                        }

                        @Override
                        public void onConfigureFailed(@NonNull CameraCaptureSession session) {
                            Log.e(TAG, "Failed to configure camera session");
                            if (previewSurface != null) {
                                try {
                                    previewSurface.release();
                                } catch (Exception e) {
                                    Log.e(TAG, "Failed to release preview Surface: " + e.getMessage());
                                }
                            }
                        }

                        @Override
                        public void onClosed(@NonNull CameraCaptureSession session) {
                            super.onClosed(session);
                            Log.d(TAG, "Camera session closed");
                            if (previewSurface != null && previewSurface.isValid()) {
                                try {
                                    previewSurface.release();
                                } catch (Exception e) {
                                    Log.e(TAG, "Failed to release Surface when closing camera session: " + e.getMessage());
                                }
                            }
                        }
                    },
                    backgroundHandler
            );
        } catch (CameraAccessException e) {
            Log.e(TAG, "Error creating camera preview session: " + e.getMessage());
        } catch (Exception e) {
            Log.e(TAG, "Unknown error creating camera preview session: " + e.getMessage());
        }
    }

    private void updateCameraPreview() {
        if (cameraDevice == null || cameraCaptureSession == null) {
            Log.e(TAG, "Camera or session is null");
            return;
        }

        try {
            if (!autoExposure && exposureTime > 0) {
                captureRequestBuilder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_OFF);
                captureRequestBuilder.set(CaptureRequest.SENSOR_EXPOSURE_TIME, exposureTime);
                
                if (getPageParams(activePageId).isoValue > 0) {
                    captureRequestBuilder.set(CaptureRequest.SENSOR_SENSITIVITY, getPageParams(activePageId).isoValue);
                    Log.d(TAG, "Applied ISO value: " + getPageParams(activePageId).isoValue);
                }
            } else {
                captureRequestBuilder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON);
            }

            if (hdrMode) {
                captureRequestBuilder.set(CaptureRequest.CONTROL_SCENE_MODE, CaptureRequest.CONTROL_SCENE_MODE_HDR);
                captureRequestBuilder.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_USE_SCENE_MODE);
            } else {
                captureRequestBuilder.set(CaptureRequest.CONTROL_SCENE_MODE, CaptureRequest.CONTROL_SCENE_MODE_DISABLED);
                captureRequestBuilder.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO);
            }

            setZoom(currentZoom);

            captureRequestBuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
            captureRequestBuilder.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_IDLE);

            CaptureRequest request = captureRequestBuilder.build();

            cameraCaptureSession.setRepeatingRequest(request, null, backgroundHandler);

        } catch (CameraAccessException e) {
            Log.e(TAG, "Failed to configure camera preview params: " + e.getMessage());
        } catch (IllegalStateException e) {
            Log.e(TAG, "Failed to update camera preview - session may be closed: " + e.getMessage());
            try {
                createCameraPreviewSession();
            } catch (Exception e2) {
                Log.e(TAG, "Failed to recreate preview session: " + e2.getMessage());
            }
        } catch (Exception e) {
            Log.e(TAG, "Unknown error updating camera preview: " + e.getMessage());
        }
    }

    private void setZoom(float zoomLevel) {
        if (cameraDevice == null) {
            return;
        }

        try {
            CameraManager manager = (CameraManager) context.getSystemService(Context.CAMERA_SERVICE);
            CameraCharacteristics characteristics = manager.getCameraCharacteristics(cameraId);

            Rect rect = characteristics.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE);
            if (rect == null) {
                return;
            }

            float maxZoom = 5.0f;
            if (zoomLevel < 1.0f) zoomLevel = 1.0f;
            if (zoomLevel > maxZoom) zoomLevel = maxZoom;

            int centerX = rect.width() / 2;
            int centerY = rect.height() / 2;
            int deltaX = (int) (0.5f * rect.width() / zoomLevel);
            int deltaY = (int) (0.5f * rect.height() / zoomLevel);

            Rect zoomRect = new Rect(
                    centerX - deltaX,
                    centerY - deltaY,
                    centerX + deltaX,
                    centerY + deltaY
            );

            captureRequestBuilder.set(CaptureRequest.SCALER_CROP_REGION, zoomRect);
        } catch (CameraAccessException e) {
            Log.e(TAG, "Error setting zoom: " + e.getMessage());
        }
    }

    private void processImageCapture(Image image) {
        if (pendingTakePictureResult == null || image == null) {
            return;
        }

        ByteBuffer buffer = image.getPlanes()[0].getBuffer();
        byte[] bytes = new byte[buffer.capacity()];
        buffer.get(bytes);

        try {
            int imageSize = bytes.length / 1024;
            Log.d(TAG, "Captured image size: " + imageSize + " KB (" + (imageSize / 1024.0) + " MB)");

            Log.d(TAG, "Global illumination params before processing: " + (currentIlluminationParams != null ?
                    currentIlluminationParams.toString() : "null"));

            String imagePath = saveImageToStorage(bytes);

            if (pendingTakePictureResult != null) {
                Map<String, Object> resultMap = new HashMap<>();
                resultMap.put("path", imagePath);
                resultMap.put("width", image.getWidth());
                resultMap.put("height", image.getHeight());
                resultMap.put("size", imageSize);
                resultMap.put("format", "JPEG");

                pendingTakePictureResult.success(imagePath);

                pendingTakePictureResult = null;

                Log.d(TAG, "Photo processing complete, clearing global illumination params");
                currentIlluminationParams = null;
            }
        } catch (Exception e) {
            Log.e(TAG, "Error processing image: " + e.getMessage());
            if (pendingTakePictureResult != null) {
                pendingTakePictureResult.error("SAVE_ERROR", "Error saving image: " + e.getMessage(), null);
                pendingTakePictureResult = null;

                currentIlluminationParams = null;
            }
        }
    }

    private String saveImageToStorage(byte[] bytes) throws IOException {
        String timeStamp = new SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(new Date());

        CameraParams params = getPageParams(activePageId);

        String fileName = "SCOPE_" + timeStamp + ".jpg";

        Map<String, Object> illuminationParams = currentIlluminationParams;
        Log.d(TAG, "Global illumination params in saveImageToStorage: " + (illuminationParams != null ?
                illuminationParams.toString() : "null"));

        if (illuminationParams == null && pendingTakePictureResult instanceof MethodResultWrapper) {
            MethodResultWrapper wrapper = (MethodResultWrapper) pendingTakePictureResult;
            Map<String, Object> arguments = wrapper.getArguments();
            if (arguments != null && arguments.containsKey("illuminationParams")) {
                illuminationParams = (Map<String, Object>) arguments.get("illuminationParams");
            }
        }

        if (illuminationParams != null && !illuminationParams.isEmpty()) {
            try {
                Object radius = illuminationParams.get("radius");
                Object spacing = illuminationParams.get("spacing");
                Object illuminationType = illuminationParams.get("type");

                StringBuilder nameBuilder = new StringBuilder();
                nameBuilder.append("SCOPE_").append(timeStamp);

                if (illuminationType != null) {
                    nameBuilder.append("_").append(illuminationType.toString());
                    Log.d(TAG, "Adding illumination type: " + illuminationType.toString());
                }

                if (radius != null) {
                    int radiusValue;
                    if (radius instanceof Number) {
                        radiusValue = ((Number) radius).intValue();
                    } else if (radius instanceof String) {
                        radiusValue = Integer.parseInt((String) radius);
                    } else {
                        radiusValue = 0;
                    }
                    nameBuilder.append("_R").append(radiusValue);
                    Log.d(TAG, "Adding radius: R" + radiusValue);
                }

                if (spacing != null) {
                    int spacingValue;
                    if (spacing instanceof Number) {
                        spacingValue = ((Number) spacing).intValue();
                    } else if (spacing instanceof String) {
                        spacingValue = Integer.parseInt((String) spacing);
                    } else {
                        spacingValue = 0;
                    }
                    nameBuilder.append("_S").append(spacingValue);
                    Log.d(TAG, "Adding spacing: S" + spacingValue);
                }

                if (params.hdrMode) {
                    nameBuilder.append("_HDR");
                    Log.d(TAG, "Adding HDR tag");
                }

                if (params.highResolutionMode) {
                    nameBuilder.append("_HR");
                    Log.d(TAG, "Adding high resolution tag");
                }

                nameBuilder.append(".jpg");

                fileName = nameBuilder.toString();
                Log.d(TAG, "Final filename: " + fileName);
            } catch (Exception e) {
                Log.e(TAG, "Error building filename: " + e.getMessage());
                fileName = "SCOPE_" + timeStamp + ".jpg";
            }
        } else {
            Log.d(TAG, "No valid illumination params found, using default filename: " + fileName);
        }

        String imagePath;

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContentResolver resolver = context.getContentResolver();
            ContentValues contentValues = new ContentValues();
            contentValues.put(MediaStore.MediaColumns.DISPLAY_NAME, fileName);
            contentValues.put(MediaStore.MediaColumns.MIME_TYPE, "image/jpeg");
            contentValues.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/SmartScope");

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                contentValues.put(MediaStore.MediaColumns.IS_PENDING, 1);
            }

            Uri imageUri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues);
            if (imageUri == null) {
                throw new IOException("Cannot create image URI");
            }

            try (OutputStream out = resolver.openOutputStream(imageUri)) {
                if (out == null) {
                    throw new IOException("Cannot open output stream");
                }
                out.write(bytes);
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                contentValues.clear();
                contentValues.put(MediaStore.MediaColumns.IS_PENDING, 0);
                resolver.update(imageUri, contentValues, null, null);
            }

            imagePath = imageUri.toString();
        } else {
            String storageDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES).getAbsolutePath();
            String dirPath = storageDir + "/SmartScope";

            File dir = new File(dirPath);
            if (!dir.exists()) {
                if (!dir.mkdirs()) {
                    throw new IOException("Cannot create directory");
                }
            }

            File file = new File(dirPath, fileName);
            try (FileOutputStream out = new FileOutputStream(file)) {
                out.write(bytes);
                out.flush();
            }

            if (context != null) {
                Intent mediaScanIntent = new Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE);
                mediaScanIntent.setData(Uri.fromFile(file));
                context.sendBroadcast(mediaScanIntent);
            }

            imagePath = file.getAbsolutePath();
        }

        Log.d(TAG, "Photo saved to: " + imagePath);
        return imagePath;
    }

    private void takePicture(Result result, Map<String, Object> illuminationParams) {
        pendingTakePictureResult = null;
        currentIlluminationParams = null;

        if (illuminationParams != null) {
            currentIlluminationParams = new HashMap<>(illuminationParams);
        }

        pendingTakePictureResult = illuminationParams != null ? wrapResult(result, illuminationParams) : result;

        if (cameraDevice == null) {
            pendingTakePictureResult.error("NO_CAMERA", "Camera not initialized", null);
            pendingTakePictureResult = null;
            currentIlluminationParams = null;
            return;
        }

        try {
            CaptureRequest.Builder captureBuilder = cameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE);
            captureBuilder.addTarget(imageReader.getSurface());

            captureBuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);

            captureBuilder.set(
                    CaptureRequest.CONTROL_AE_MODE,
                    autoExposure ? CaptureRequest.CONTROL_AE_MODE_ON : CaptureRequest.CONTROL_AE_MODE_OFF
            );

            if (hdrMode) {
                captureBuilder.set(CaptureRequest.CONTROL_SCENE_MODE, CaptureRequest.CONTROL_SCENE_MODE_HDR);
                captureBuilder.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_USE_SCENE_MODE);

                Log.d(TAG, "Using HDR mode for capture");
            } else {
                captureBuilder.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO);
            }

            if (!autoExposure && exposureTime > 0) {
                captureBuilder.set(CaptureRequest.SENSOR_EXPOSURE_TIME, exposureTime);
                Log.d(TAG, "Using fixed exposure time for capture: " + exposureTime + " ns");
                
                if (getPageParams(activePageId).isoValue > 0) {
                    captureBuilder.set(CaptureRequest.SENSOR_SENSITIVITY, getPageParams(activePageId).isoValue);
                    Log.d(TAG, "Applied ISO value for capture: " + getPageParams(activePageId).isoValue);
                }
            }

            if (currentZoom > 1.0f) {
                setZoomForCaptureRequest(captureBuilder);
            }

            if (activeViewId != -1) {
                CameraViewInfo viewInfo = textureViews.get(activeViewId);
                if (viewInfo != null && viewInfo.textureView != null && viewInfo.textureView.isAvailable()) {
                    try {
                        SurfaceTexture texture = viewInfo.textureView.getSurfaceTexture();
                        if (texture != null) {
                            Surface previewSurface = new Surface(texture);
                            captureBuilder.addTarget(previewSurface);

                            final Surface capturePreviewSurface = previewSurface;

                            CameraCaptureSession.CaptureCallback captureCallback = new CameraCaptureSession.CaptureCallback() {
                                @Override
                                public void onCaptureStarted(@NonNull CameraCaptureSession session,
                                                             @NonNull CaptureRequest request,
                                                             long timestamp,
                                                             long frameNumber) {
                                    super.onCaptureStarted(session, request, timestamp, frameNumber);
                                    Log.d(TAG, "Capture started");
                                }

                                @Override
                                public void onCaptureCompleted(@NonNull CameraCaptureSession session,
                                                               @NonNull CaptureRequest request,
                                                               @NonNull TotalCaptureResult result) {
                                    super.onCaptureCompleted(session, request, result);

                                    if (capturePreviewSurface != null) {
                                        try {
                                            capturePreviewSurface.release();
                                        } catch (Exception e) {
                                            Log.e(TAG, "Error releasing preview Surface: " + e.getMessage());
                                        }
                                    }

                                    try {
                                        createCameraPreviewSession();
                                    } catch (Exception e) {
                                        Log.e(TAG, "Error resuming preview: " + e.getMessage());
                                    }
                                }
                            };

                            cameraCaptureSession.stopRepeating();
                            cameraCaptureSession.capture(captureBuilder.build(), captureCallback, backgroundHandler);
                            return;
                        }
                    } catch (Exception e) {
                        Log.e(TAG, "Failed to prepare Surface for capture: " + e.getMessage());
                    }
                }
            }

            CameraCaptureSession.CaptureCallback captureCallback = new CameraCaptureSession.CaptureCallback() {
                @Override
                public void onCaptureStarted(@NonNull CameraCaptureSession session,
                                             @NonNull CaptureRequest request,
                                             long timestamp,
                                             long frameNumber) {
                    super.onCaptureStarted(session, request, timestamp, frameNumber);
                    Log.d(TAG, "Capture started");
                }

                @Override
                public void onCaptureCompleted(@NonNull CameraCaptureSession session,
                                               @NonNull CaptureRequest request,
                                               @NonNull TotalCaptureResult result) {
                    super.onCaptureCompleted(session, request, result);
                    Log.d(TAG, "Capture completed");

                    Integer iso = result.get(CaptureResult.SENSOR_SENSITIVITY);
                    Long exposureTime = result.get(CaptureResult.SENSOR_EXPOSURE_TIME);

                    if (iso != null && exposureTime != null) {
                        Log.d(TAG, "Photo params - ISO: " + iso + ", Exposure time: " +
                                (exposureTime / 1000000.0) + "ms");
                    }

                    try {
                        createCameraPreviewSession();
                    } catch (Exception e) {
                        Log.e(TAG, "Error resuming preview: " + e.getMessage());
                    }
                }
            };

            cameraCaptureSession.stopRepeating();
            cameraCaptureSession.capture(captureBuilder.build(), captureCallback, backgroundHandler);

        } catch (CameraAccessException e) {
            Log.e(TAG, "Error during capture: " + e.getMessage());
            if (pendingTakePictureResult != null) {
                pendingTakePictureResult.error("CAMERA_ERROR", "Error during capture: " + e.getMessage(), null);
                pendingTakePictureResult = null;
            }
        }
    }

    private void setZoomForCaptureRequest(CaptureRequest.Builder requestBuilder) {
        try {
            CameraManager manager = (CameraManager) context.getSystemService(Context.CAMERA_SERVICE);
            CameraCharacteristics characteristics = manager.getCameraCharacteristics(cameraId);

            Rect sensorRect = characteristics.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE);
            if (sensorRect == null) {
                return;
            }

            int centerX = sensorRect.width() / 2;
            int centerY = sensorRect.height() / 2;
            int deltaX = (int) (0.5f * sensorRect.width() / currentZoom);
            int deltaY = (int) (0.5f * sensorRect.height() / currentZoom);

            Rect zoomRect = new Rect(
                    centerX - deltaX,
                    centerY - deltaY,
                    centerX + deltaX,
                    centerY + deltaY
            );

            requestBuilder.set(CaptureRequest.SCALER_CROP_REGION, zoomRect);
        } catch (CameraAccessException e) {
            Log.e(TAG, "Error setting zoom for capture: " + e.getMessage());
        }
    }

    private Size getOptimalSize(Size[] sizes) {
        if (sizes == null || sizes.length == 0) {
            Log.e(TAG, "Cannot get camera supported size list");
            return null;
        }

        Arrays.sort(sizes, (s1, s2) -> Integer.compare(
                s1.getWidth() * s1.getHeight(),
                s2.getWidth() * s2.getHeight()));

        return sizes[sizes.length / 2];
    }

    private Size getBestCaptureSize(Size[] sizes) {
        if (sizes == null || sizes.length == 0) {
            Log.e(TAG, "Cannot get camera supported capture size list");
            return null;
        }

        Log.d(TAG, "Available photo resolutions:");
        for (Size size : sizes) {
            Log.d(TAG, "  - " + size.getWidth() + "x" + size.getHeight() +
                    " (" + (size.getWidth() * size.getHeight() / 1000000.0) + " MP)");
        }

        Size highestResolution = sizes[0];

        for (Size size : sizes) {
            if (size.getWidth() * size.getHeight() >
                    highestResolution.getWidth() * highestResolution.getHeight()) {
                highestResolution = size;
            }
        }

        long highestPixels = highestResolution.getWidth() * highestResolution.getHeight();
        Log.d(TAG, "Using highest resolution: " + highestResolution.getWidth() + "x" + highestResolution.getHeight() +
                " (" + (highestPixels / 1000000.0) + " MP)");

        return highestResolution;
    }

    @Keep
    @NonNull
    private Size chooseOptimalSize(@NonNull Size[] options, int width, int height) {
        final double ASPECT_TOLERANCE = 0.1;
        double targetRatio = (double) width / height;
        
        Size optimal = null;
        double minDiff = Double.MAX_VALUE;
        
        for (Size option : options) {
            double ratio = (double) option.getWidth() / option.getHeight();
            if (Math.abs(ratio - targetRatio) > ASPECT_TOLERANCE) continue;
            
            double diff = Math.abs(option.getWidth() - width) + Math.abs(option.getHeight() - height);
            if (diff < minDiff) {
                optimal = option;
                minDiff = diff;
            }
        }
        
        if (optimal == null) {
            minDiff = Double.MAX_VALUE;
            for (Size option : options) {
                double diff = Math.abs(option.getWidth() - width) + Math.abs(option.getHeight() - height);
                if (diff < minDiff) {
                    optimal = option;
                    minDiff = diff;
                }
            }
        }
        return optimal;
    }

    private Map<String, Object> getCameraInfo() {
        Map<String, Object> info = new HashMap<>();

        if (imageDimension != null) {
            info.put("previewWidth", imageDimension.getWidth());
            info.put("previewHeight", imageDimension.getHeight());
        } else {
            info.put("previewWidth", 0);
            info.put("previewHeight", 0);
        }

        if (imageReader != null) {
            info.put("photoWidth", imageReader.getWidth());
            info.put("photoHeight", imageReader.getHeight());
            info.put("photoFormat", imageReader.getImageFormat() == ImageFormat.JPEG ? "JPEG" : "Other format");
        } else {
            info.put("photoWidth", 0);
            info.put("photoHeight", 0);
            info.put("photoFormat", "Unknown");
        }

        info.put("highResolutionMode", highResolutionMode);
        info.put("isRearCamera", useRearCamera);
        info.put("hdrMode", hdrMode);

        return info;
    }

    private void performTouchFocus(int viewId, float x, float y) {
        try {
            Log.d(TAG, "Touch focus triggered, position: (" + x + ", " + y + ")");

            CameraViewInfo viewInfo = textureViews.get(viewId);
            if (viewInfo == null || viewInfo.textureView == null) {
                return;
            }

            TextureView textureView = viewInfo.textureView;

            if (cameraDevice == null || cameraCaptureSession == null || captureRequestBuilder == null) {
                Log.e(TAG, "Camera or session invalid, cannot perform focus");
                return;
            }

            CameraManager manager = (CameraManager) context.getSystemService(Context.CAMERA_SERVICE);
            CameraCharacteristics characteristics = manager.getCameraCharacteristics(cameraId);

            Rect sensorRect = characteristics.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE);
            if (sensorRect == null) {
                Log.e(TAG, "Cannot get sensor area");
                return;
            }

            int touchX = (int) ((x / textureView.getWidth()) * sensorRect.width());
            int touchY = (int) ((y / textureView.getHeight()) * sensorRect.height());

            int focusSize = Math.min(sensorRect.width(), sensorRect.height()) / 10;

            Rect focusRect = new Rect(
                    Math.max(touchX - focusSize, 0),
                    Math.max(touchY - focusSize, 0),
                    Math.min(touchX + focusSize, sensorRect.width()),
                    Math.min(touchY + focusSize, sensorRect.height())
            );

            MeteringRectangle focusArea = new MeteringRectangle(
                    focusRect,
                    MeteringRectangle.METERING_WEIGHT_MAX
            );

            CaptureRequest.Builder focusBuilder = cameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);

            if (viewInfo.textureView != null && viewInfo.textureView.getSurfaceTexture() != null) {
                Surface surface = new Surface(viewInfo.textureView.getSurfaceTexture());
                focusBuilder.addTarget(surface);
            }

            if (imageReader != null) {
                focusBuilder.addTarget(imageReader.getSurface());
            }

            focusBuilder.set(CaptureRequest.CONTROL_AE_MODE,
                    autoExposure ? CaptureRequest.CONTROL_AE_MODE_ON : CaptureRequest.CONTROL_AE_MODE_OFF);

            if (hdrMode) {
                focusBuilder.set(CaptureRequest.CONTROL_SCENE_MODE, CaptureRequest.CONTROL_SCENE_MODE_HDR);
                focusBuilder.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_USE_SCENE_MODE);
            } else {
                focusBuilder.set(CaptureRequest.CONTROL_SCENE_MODE, CaptureRequest.CONTROL_SCENE_MODE_DISABLED);
                focusBuilder.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO);
            }

            setZoomForCaptureRequest(focusBuilder);

            focusBuilder.set(CaptureRequest.CONTROL_AF_REGIONS, new MeteringRectangle[]{focusArea});
            focusBuilder.set(CaptureRequest.CONTROL_AE_REGIONS, new MeteringRectangle[]{focusArea});
            focusBuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_AUTO);
            focusBuilder.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_START);

            CameraCaptureSession.CaptureCallback focusCallback = new CameraCaptureSession.CaptureCallback() {
                private boolean hasCompletedFocus = false;

                @Override
                public void onCaptureCompleted(@NonNull CameraCaptureSession session,
                                               @NonNull CaptureRequest request,
                                               @NonNull TotalCaptureResult result) {
                    super.onCaptureCompleted(session, request, result);

                    Integer afState = result.get(CaptureResult.CONTROL_AF_STATE);
                    if (afState == null) {
                        return;
                    }

                    Log.d(TAG, "Focus state: " + getAfStateString(afState));

                    boolean focusComplete = (afState == CaptureResult.CONTROL_AF_STATE_FOCUSED_LOCKED ||
                            afState == CaptureResult.CONTROL_AF_STATE_NOT_FOCUSED_LOCKED ||
                            afState == CaptureResult.CONTROL_AF_STATE_PASSIVE_FOCUSED ||
                            afState == CaptureResult.CONTROL_AF_STATE_PASSIVE_UNFOCUSED);

                    if (focusComplete && !hasCompletedFocus) {
                        hasCompletedFocus = true;

                        try {
                            captureRequestBuilder.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_IDLE);

                            captureRequestBuilder.set(CaptureRequest.CONTROL_AF_REGIONS, new MeteringRectangle[]{focusArea});
                            captureRequestBuilder.set(CaptureRequest.CONTROL_AE_REGIONS, new MeteringRectangle[]{focusArea});

                            session.setRepeatingRequest(captureRequestBuilder.build(), null, backgroundHandler);
                        } catch (Exception e) {
                            Log.e(TAG, "Error resuming preview after focus: " + e.getMessage());
                        }
                    }
                }
            };

            try {
                cameraCaptureSession.capture(focusBuilder.build(), focusCallback, backgroundHandler);

                if (activity != null) {
                    activity.runOnUiThread(() -> showFocusAnimation(textureView, (int)x, (int)y));
                }
            } catch (CameraAccessException e) {
                Log.e(TAG, "Error sending focus request: " + e.getMessage());
            }

        } catch (CameraAccessException e) {
            Log.e(TAG, "Camera access error during focus: " + e.getMessage());
        } catch (Exception e) {
            Log.e(TAG, "Unknown error during focus: " + e.getMessage());
        }
    }

    private String getAfStateString(Integer afState) {
        switch (afState) {
            case CaptureResult.CONTROL_AF_STATE_INACTIVE:
                return "Inactive";
            case CaptureResult.CONTROL_AF_STATE_PASSIVE_SCAN:
                return "Passive scan";
            case CaptureResult.CONTROL_AF_STATE_PASSIVE_FOCUSED:
                return "Passive focused";
            case CaptureResult.CONTROL_AF_STATE_ACTIVE_SCAN:
                return "Active scan";
            case CaptureResult.CONTROL_AF_STATE_FOCUSED_LOCKED:
                return "Focused locked";
            case CaptureResult.CONTROL_AF_STATE_NOT_FOCUSED_LOCKED:
                return "Not focused locked";
            case CaptureResult.CONTROL_AF_STATE_PASSIVE_UNFOCUSED:
                return "Passive unfocused";
            default:
                return "Unknown state: " + afState;
        }
    }

    private void showFocusAnimation(TextureView textureView, int x, int y) {
        View focusIndicator = new View(context);

        focusIndicator.setBackgroundResource(createFocusCircleDrawable());

        int size = 100;
        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(size, size);
        params.leftMargin = x - size / 2;
        params.topMargin = y - size / 2;
        focusIndicator.setLayoutParams(params);

        ViewGroup parent = (ViewGroup) textureView.getParent();
        parent.addView(focusIndicator);

        focusIndicator.animate()
                .scaleX(1.5f)
                .scaleY(1.5f)
                .setDuration(300)
                .withEndAction(() ->
                        focusIndicator.animate()
                                .scaleX(1.0f)
                                .scaleY(1.0f)
                                .setDuration(300)
                                .withEndAction(() -> {
                                    parent.removeView(focusIndicator);
                                })
                                .start()
                )
                .start();
    }

    private int createFocusCircleDrawable() {
        int resourceId = context.getResources().getIdentifier(
                "focus_circle", "drawable", context.getPackageName());
        if (resourceId == 0) {
            return android.R.drawable.ic_menu_compass;
        }
        return resourceId;
    }

    private byte[] loadImageBytesFromContentUri(Uri uri) {
        try {
            ContentResolver contentResolver = context.getContentResolver();

            java.io.InputStream inputStream = contentResolver.openInputStream(uri);
            if (inputStream == null) {
                Log.e(TAG, "Cannot open input stream for content URI: " + uri);
                return null;
            }

            byte[] buffer = new byte[8192];
            java.io.ByteArrayOutputStream outputStream = new java.io.ByteArrayOutputStream();
            int bytesRead;
            while ((bytesRead = inputStream.read(buffer)) != -1) {
                outputStream.write(buffer, 0, bytesRead);
            }

            inputStream.close();
            outputStream.close();

            return outputStream.toByteArray();
        } catch (Exception e) {
            Log.e(TAG, "Error loading image data from content URI: " + e.getMessage(), e);
            return null;
        }
    }

    private void startIntensityMonitoring(final Result result) {
        Log.d(TAG, "startIntensityMonitoring: This feature has been removed");
        result.error("NOT_IMPLEMENTED", "Light intensity monitoring feature removed", null);
    }

    private void stopIntensityMonitoring(final Result result) {
        Log.d(TAG, "stopIntensityMonitoring: This feature has been removed");

        if (result != null) {
            result.success(true);
        }
    }

    private void getCurrentLightIntensity(final Result result) {
        if (activeViewId == -1) {
            result.error("NO_ACTIVE_VIEW", "No active view", null);
            return;
        }

        CameraViewInfo viewInfo = textureViews.get(activeViewId);
        if (viewInfo == null) {
            result.error("VIEW_NOT_FOUND", "Cannot find active view info", null);
            return;
        }

        String viewPageId = viewInfo.pageId;

        if (!viewPageId.equals("center_align_page")) {
            Log.d(TAG, "Light intensity measurement only available in center_align_page, current pageId=" + viewPageId);
            result.error("INVALID_PAGE", "Light intensity measurement only available in center_align_page", null);
            return;
        }

        if (viewInfo.textureView == null || !viewInfo.textureView.isAvailable()) {
            result.error("TEXTURE_UNAVAILABLE", "Camera preview not available", null);
            return;
        }

        try {
            android.graphics.Bitmap bitmap = viewInfo.textureView.getBitmap();
            if (bitmap != null) {
                double intensity = calculateSimpleIntensity(bitmap);

                result.success(intensity);

                bitmap.recycle();
            } else {
                result.error("BITMAP_NULL", "Cannot get image data", null);
            }
        } catch (Exception e) {
            Log.e(TAG, "Error getting light intensity: " + e.getMessage(), e);
            result.error("INTENSITY_ERROR", "Failed to get light intensity: " + e.getMessage(), null);
        }
    }

    private void applyActivePageParams() {
        CameraParams params = getPageParams(activePageId);

        this.useRearCamera = params.useRearCamera;
        this.currentZoom = params.zoomLevel;
        this.autoExposure = params.autoExposure;
        this.exposureTime = params.exposureTime;
        this.highResolutionMode = params.highResolutionMode;
        this.hdrMode = params.hdrMode;
    }

    private MethodResultWrapper wrapResult(Result result, Map<String, Object> illuminationParams) {
        if (illuminationParams != null) {
            try {
                Log.d(TAG, "wrapResult received illumination params: " + illuminationParams.toString());

                Map<String, Object> copyParams = new HashMap<>(illuminationParams);

                if (copyParams.containsKey("type")) {
                    Object type = copyParams.get("type");
                    Log.d(TAG, "Illumination type: " + type + " (class: " + type.getClass().getName() + ")");
                }
                if (copyParams.containsKey("radius")) {
                    Object radius = copyParams.get("radius");
                    Log.d(TAG, "Radius: " + radius + " (class: " + radius.getClass().getName() + ")");
                }
                if (copyParams.containsKey("spacing")) {
                    Object spacing = copyParams.get("spacing");
                    Log.d(TAG, "Spacing: " + spacing + " (class: " + spacing.getClass().getName() + ")");
                }

                return new MethodResultWrapper(result, copyParams);
            } catch (Exception e) {
                Log.e(TAG, "Error processing illumination params: " + e.getMessage());
            }
        } else {
            Log.d(TAG, "wrapResult received null illumination params");
        }

        return new MethodResultWrapper(result, illuminationParams != null ?
                new HashMap<>(illuminationParams) :
                new HashMap<>());
    }

    private static class MethodResultWrapper implements Result {
        private final Result delegate;
        private final Map<String, Object> arguments;

        MethodResultWrapper(Result delegate, Map<String, Object> arguments) {
            this.delegate = delegate;
            this.arguments = arguments;
        }

        @Override
        public void success(Object result) {
            delegate.success(result);
        }

        @Override
        public void error(String errorCode, String errorMessage, Object errorDetails) {
            delegate.error(errorCode, errorMessage, errorDetails);
        }

        @Override
        public void notImplemented() {
            delegate.notImplemented();
        }

        public Map<String, Object> getArguments() {
            return arguments;
        }
    }

    private double calculateSimpleIntensity(android.graphics.Bitmap bitmap) {
        int width = bitmap.getWidth();
        int height = bitmap.getHeight();

        int startX = width / 5;
        int startY = height / 5;
        int endX = width - startX;
        int endY = height - startY;

        int regionWidth = endX - startX;
        int regionHeight = endY - startY;

        int[] pixels = new int[regionWidth * regionHeight];
        bitmap.getPixels(pixels, 0, regionWidth, startX, startY, regionWidth, regionHeight);

        long totalBrightness = 0;

        for (int pixel : pixels) {
            int r = (pixel >> 16) & 0xff;
            int g = (pixel >> 8) & 0xff;
            int b = pixel & 0xff;

            totalBrightness += r + g + b;
        }

        double averageBrightness = pixels.length > 0 ? (double)totalBrightness / pixels.length : 0;

        double normalizedIntensity = (averageBrightness / 765.0) * 255.0;

        Log.d(TAG, "Calculated average brightness: " + normalizedIntensity
                + ", center 60% area: " + regionWidth * regionHeight + " pixels"
                + ", processed pixels: " + pixels.length);

        return normalizedIntensity;
    }

    @Keep
    public void disposeTextureView(int viewId) {
        Log.d(TAG, "disposeTextureView: Starting to release view resources, ID: " + viewId);

        CameraViewInfo viewInfo = textureViews.get(viewId);
        if (viewInfo == null) {
            Log.d(TAG, "View info is null, no need to release: " + viewId);
            return;
        }

        if (activeViewId == viewId) {
            Log.d(TAG, "Releasing active view: " + viewId);
            closeCamera();
            stopBackgroundThread();
            activeViewId = -1;
        }

        textureViews.remove(viewId);
        Log.d(TAG, "View removed from mapping: " + viewId);
    }
}