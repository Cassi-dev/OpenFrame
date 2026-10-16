package app.openframe.mobile;

import android.app.AlertDialog;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import org.qtproject.qt.android.bindings.QtActivity;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileWriter;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.io.StringWriter;

public class OpenFrameActivity extends QtActivity {
    private static final String TAG = "OpenFrame";

    @Override
    public void onCreate(Bundle savedInstanceState) {
        setupLogging();
        startLogcatCapture();
        Log.i(TAG, "OpenFrameActivity.onCreate starting");
        saveLog("OpenFrameActivity.onCreate starting");

        try {
            super.onCreate(savedInstanceState);
            Log.i(TAG, "QtActivity super.onCreate finished successfully");
            saveLog("QtActivity super.onCreate finished successfully");
        } catch (Throwable t) {
            Log.e(TAG, "CRASH during QtActivity.onCreate", t);
            String stackTrace = getStackTrace(t);
            saveLog("CRASH in onCreate:\n" + stackTrace);
            showErrorDialog("Erro ao iniciar o OpenFrame", stackTrace);
        }
    }

    private void setupLogging() {
        final Thread.UncaughtExceptionHandler defaultHandler = Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler((thread, ex) -> {
            Log.e(TAG, "FATAL UNCAUGHT EXCEPTION in thread " + thread.getName(), ex);
            String trace = getStackTrace(ex);
            saveLog("FATAL UNCAUGHT EXCEPTION in thread " + thread.getName() + ":\n" + trace);

            new Handler(Looper.getMainLooper()).post(() -> {
                showErrorDialog("Falha no OpenFrame (" + thread.getName() + ")", trace);
            });

            if (defaultHandler != null) {
                defaultHandler.uncaughtException(thread, ex);
            }
        });
    }

    private void startLogcatCapture() {
        new Thread(() -> {
            try {
                Process process = Runtime.getRuntime().exec("logcat -v time -s Qt:V QtLoader:V OpenFrame:V AndroidRuntime:E");
                BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
                File dir = getExternalFilesDir(null);
                if (dir == null) dir = getFilesDir();
                File file = new File(dir, "openframe_logcat.txt");
                FileWriter writer = new FileWriter(file, true);
                String line;
                while ((line = reader.readLine()) != null) {
                    writer.write(line + "\n");
                    writer.flush();
                }
                writer.close();
            } catch (Exception ignored) {}
        }, "OpenFrameLogcat").start();
    }

    public static String getStackTrace(Throwable t) {
        StringWriter sw = new StringWriter();
        PrintWriter pw = new PrintWriter(sw);
        t.printStackTrace(pw);
        return sw.toString();
    }

    private void saveLog(String message) {
        try {
            File dir = getExternalFilesDir(null);
            if (dir == null) dir = getFilesDir();
            if (dir != null) {
                File file = new File(dir, "openframe_boot.log");
                FileWriter writer = new FileWriter(file, true);
                writer.write("[" + System.currentTimeMillis() + "] " + message + "\n");
                writer.close();
            }
        } catch (Exception e) {
            Log.e(TAG, "Failed to write log", e);
        }
    }

    private void showErrorDialog(String title, String message) {
        try {
            AlertDialog.Builder builder = new AlertDialog.Builder(this);
            builder.setTitle(title);
            builder.setMessage(message);
            builder.setPositiveButton("Fechar", (dialog, which) -> finish());
            builder.setCancelable(false);
            builder.show();
        } catch (Throwable e) {
            Log.e(TAG, "Could not show AlertDialog", e);
        }
    }
}
