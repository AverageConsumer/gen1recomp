package org.love2d.android;

import android.app.Presentation;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.hardware.display.DisplayManager;
import android.os.Bundle;
import android.util.Log;
import android.view.Display;
import android.view.MotionEvent;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;

import java.util.ArrayDeque;

/** Generic, opt-in secondary display surface for mods. */
final class SecondaryDisplayHost implements DisplayManager.DisplayListener {
    private static final String TAG = "SecondaryDisplay";
    private static final int MAX_FRAME_BYTES = 4 * 1024 * 1024;
    private static final int MAX_DIMENSION = 1024;
    private static final int MAX_TOUCH_EVENTS = 32;

    private final GameActivity activity;
    private final DisplayManager displayManager;
    private final ArrayDeque<String> pendingTouches = new ArrayDeque<>();
    private final Object frameLock = new Object();
    private FramePresentation presentation;
    private Bitmap latestFrame;
    private byte[] pendingFrame;
    private int pendingWidth;
    private int pendingHeight;
    private int pendingBackgroundColor = Color.BLACK;
    private int latestBackgroundColor = Color.BLACK;
    private boolean framePosted;
    private volatile boolean requested;
    private boolean listening;
    private boolean resumed;

    SecondaryDisplayHost(GameActivity activity) {
        this.activity = activity;
        displayManager = (DisplayManager) activity.getSystemService(Context.DISPLAY_SERVICE);
    }

    boolean isAvailable() {
        return targetDisplay() != null;
    }

    boolean present(int width, int height, byte[] rgba, int backgroundColor) {
        Display display = targetDisplay();
        if (display == null || width <= 0 || height <= 0
                || width > MAX_DIMENSION || height > MAX_DIMENSION
                || rgba == null || rgba.length == 0 || rgba.length > MAX_FRAME_BYTES
                || rgba.length != width * height * 4) {
            return false;
        }

        requested = true;
        synchronized (frameLock) {
            pendingFrame = rgba;
            pendingWidth = width;
            pendingHeight = height;
            pendingBackgroundColor = backgroundColor;
            if (framePosted) {
                return true;
            }
            framePosted = true;
        }
        activity.runOnUiThread(this::drainFrame);
        return true;
    }

    private void drainFrame() {
        final byte[] bytes;
        final int width;
        final int height;
        final int backgroundColor;
        synchronized (frameLock) {
            bytes = pendingFrame;
            width = pendingWidth;
            height = pendingHeight;
            backgroundColor = pendingBackgroundColor;
            pendingFrame = null;
        }

        if (requested && bytes != null) {
            int[] pixels = new int[width * height];
            for (int i = 0; i < pixels.length; i++) {
                int offset = i * 4;
                pixels[i] = Color.argb(bytes[offset + 3] & 0xff, bytes[offset] & 0xff,
                        bytes[offset + 1] & 0xff, bytes[offset + 2] & 0xff);
            }
            Bitmap frame = Bitmap.createBitmap(
                    pixels, width, height, Bitmap.Config.ARGB_8888);
            latestFrame = frame;
            latestBackgroundColor = backgroundColor;
            Display display = targetDisplay();
            if (presentation == null && resumed && display != null) {
                open(display);
            }
            if (presentation != null) {
                presentation.setFrame(frame, backgroundColor);
            }
        }

        boolean again;
        synchronized (frameLock) {
            again = requested && pendingFrame != null;
            if (!again) {
                framePosted = false;
            }
        }
        if (again) {
            activity.runOnUiThread(this::drainFrame);
        }
    }

    String pollTouch() {
        synchronized (pendingTouches) {
            return pendingTouches.pollFirst();
        }
    }

    void close() {
        requested = false;
        synchronized (frameLock) {
            pendingFrame = null;
        }
        synchronized (pendingTouches) {
            pendingTouches.clear();
        }
        activity.runOnUiThread(() -> {
            dismiss();
            stopListening();
            latestFrame = null;
        });
    }

    void resume() {
        resumed = true;
        if (requested && latestFrame != null) {
            Display display = targetDisplay();
            if (display != null) {
                open(display);
            }
        }
    }

    void pause() {
        resumed = false;
        synchronized (pendingTouches) {
            pendingTouches.clear();
        }
        dismiss();
        stopListening();
    }

    private Display targetDisplay() {
        for (Display display : displayManager.getDisplays(
                DisplayManager.DISPLAY_CATEGORY_PRESENTATION)) {
            if (display.getDisplayId() != Display.DEFAULT_DISPLAY
                    && display.getState() != Display.STATE_OFF) {
                return display;
            }
        }
        return null;
    }

    private void open(Display display) {
        if (!requested || !resumed || presentation != null) {
            return;
        }
        try {
            FramePresentation candidate = new FramePresentation(
                    activity, display, latestFrame, latestBackgroundColor, pendingTouches);
            candidate.setOnDismissListener(dialog -> {
                if (presentation == candidate) {
                    presentation = null;
                }
            });
            candidate.show();
            presentation = candidate;
            if (!listening) {
                displayManager.registerDisplayListener(this, null);
                listening = true;
            }
            Log.i(TAG, "OPEN display=" + display.getDisplayId());
        } catch (WindowManager.InvalidDisplayException error) {
            Log.w(TAG, "Display vanished before Presentation.show()", error);
        }
    }

    private void dismiss() {
        if (presentation != null) {
            presentation.dismiss();
            presentation = null;
            Log.i(TAG, "CLOSE");
        }
    }

    private void stopListening() {
        if (listening) {
            displayManager.unregisterDisplayListener(this);
            listening = false;
        }
    }

    @Override
    public void onDisplayAdded(int displayId) {
        if (requested && resumed && presentation == null) {
            Display display = targetDisplay();
            if (display != null) {
                open(display);
            }
        }
    }

    @Override
    public void onDisplayRemoved(int displayId) {
        if (presentation != null && presentation.getDisplay().getDisplayId() == displayId) {
            dismiss();
        }
    }

    @Override
    public void onDisplayChanged(int displayId) {
        // Presentation and FrameView adapt to metric/rotation changes themselves.
    }

    private static final class FramePresentation extends Presentation {
        private final Bitmap initialFrame;
        private final int initialBackgroundColor;
        private final ArrayDeque<String> pendingTouches;
        private FrameView view;

        FramePresentation(Context context, Display display, Bitmap frame,
                int backgroundColor,
                ArrayDeque<String> pendingTouches) {
            super(context, display);
            initialFrame = frame;
            initialBackgroundColor = backgroundColor;
            this.pendingTouches = pendingTouches;
        }

        @Override
        protected void onCreate(Bundle state) {
            super.onCreate(state);
            Window window = getWindow();
            if (window != null) {
                window.setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,
                        WindowManager.LayoutParams.FLAG_FULLSCREEN);
                window.getDecorView().setSystemUiVisibility(
                        View.SYSTEM_UI_FLAG_FULLSCREEN
                                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                                | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
            }
            view = new FrameView(getContext(), initialFrame,
                    initialBackgroundColor, pendingTouches);
            setContentView(view);
        }

        void setFrame(Bitmap frame, int backgroundColor) {
            if (view != null) {
                view.setFrame(frame, backgroundColor);
            }
        }
    }

    private static final class FrameView extends View {
        private final Paint paint = new Paint();
        private final ArrayDeque<String> pendingTouches;
        private Bitmap frame;
        private final RectF destination = new RectF();
        private int activePointer = -1;

        FrameView(Context context, Bitmap frame, int backgroundColor,
                ArrayDeque<String> pendingTouches) {
            super(context);
            this.frame = frame;
            this.pendingTouches = pendingTouches;
            paint.setFilterBitmap(false);
            setBackgroundColor(backgroundColor);
        }

        private void enqueue(String event) {
            synchronized (pendingTouches) {
                if (pendingTouches.size() >= MAX_TOUCH_EVENTS) {
                    pendingTouches.clear();
                    pendingTouches.addLast("cancel,0,0");
                } else {
                    pendingTouches.addLast(event);
                }
            }
        }

        private int logicalX(float x) {
            return Math.min(frame.getWidth() - 1, Math.max(0,
                    (int) ((x - destination.left)
                            * frame.getWidth() / destination.width())));
        }

        private int logicalY(float y) {
            return Math.min(frame.getHeight() - 1, Math.max(0,
                    (int) ((y - destination.top)
                            * frame.getHeight() / destination.height())));
        }

        void setFrame(Bitmap frame, int backgroundColor) {
            this.frame = frame;
            setBackgroundColor(backgroundColor);
            invalidate();
        }

        @Override
        protected void onDraw(Canvas canvas) {
            if (frame == null) {
                return;
            }
            float scale = Math.min(getWidth() / (float) frame.getWidth(),
                    getHeight() / (float) frame.getHeight());
            if (scale >= 1f) {
                scale = (float) Math.floor(scale);
            }
            float width = frame.getWidth() * scale;
            float height = frame.getHeight() * scale;
            float left = (getWidth() - width) / 2f;
            float top = (getHeight() - height) / 2f;
            destination.set(left, top, left + width, top + height);
            canvas.drawBitmap(frame, null, destination, paint);
        }

        @Override
        public boolean onTouchEvent(MotionEvent event) {
            int action = event.getActionMasked();
            if (action == MotionEvent.ACTION_DOWN && frame != null
                    && destination.contains(event.getX(), event.getY())) {
                activePointer = event.getPointerId(0);
                int x = logicalX(event.getX());
                int y = logicalY(event.getY());
                enqueue("down," + x + "," + y);
                Log.i(TAG, "TOUCH display=" + getDisplay().getDisplayId()
                        + " action=down x=" + x + " y=" + y);
            } else if (action == MotionEvent.ACTION_UP && activePointer >= 0
                    && frame != null) {
                int index = event.findPointerIndex(activePointer);
                if (index >= 0) {
                    int x = logicalX(event.getX(index));
                    int y = logicalY(event.getY(index));
                    enqueue("up," + x + "," + y);
                    Log.i(TAG, "TOUCH display=" + getDisplay().getDisplayId()
                            + " action=up x=" + x + " y=" + y);
                }
                activePointer = -1;
            } else if (action == MotionEvent.ACTION_CANCEL) {
                activePointer = -1;
                enqueue("cancel,0,0");
            }
            return true;
        }
    }
}
