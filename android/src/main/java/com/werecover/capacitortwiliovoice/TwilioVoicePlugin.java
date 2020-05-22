package com.werecover.capacitortwiliovoice;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.os.Build;
import android.util.Log;

import androidx.annotation.NonNull;

import android.view.View;
import android.webkit.WebView;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import com.getcapacitor.JSObject;
import com.getcapacitor.NativePlugin;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.twilio.voice.Call;
import com.twilio.voice.CallException;
import com.twilio.voice.ConnectOptions;
import com.twilio.voice.Voice;
import com.google.android.material.snackbar.Snackbar;

import java.util.HashMap;
import java.util.Locale;

@NativePlugin()
public class TwilioVoicePlugin extends Plugin {

    private static final String TAG = "TwilioVoicePlugin";

    private WebView  view;
    private Call activeCall;

    private AudioManager audioManager;
    private int savedAudioMode = AudioManager.MODE_INVALID;

    Call.Listener callListener = callListener();

    private static final int MIC_PERMISSION_REQUEST_CODE = 1;

    @PluginMethod()
    public void initPlugin(PluginCall call) {
        Log.d("initPlugin", call.toString());

        view = getActivity().findViewById(R.id.webview);

        /*
         * Needed for setting/abandoning audio focus during a call
         */
        audioManager = (AudioManager) getContext().getSystemService(Context.AUDIO_SERVICE);
        audioManager.setSpeakerphoneOn(false);

        /*
         * Enable changing the volume using the up/down keys during a conversation
         */
        getActivity().setVolumeControlStream(AudioManager.STREAM_VOICE_CALL);

        if (!checkPermissionForMicrophone()) {
            requestPermissionForMicrophone();
        }

        call.success();
    }

    @PluginMethod()
    public void call(PluginCall call) {
        Log.d("call", call.toString());

        if (!checkPermissionForMicrophone()) {
            requestPermissionForMicrophone();
            call.reject("permissions");
            return;
        }

        HashMap<String, String> params = new HashMap<>();
        params.put("To", call.getString("To"));
        params.put("providerId", call.getInt("providerId").toString());
        ConnectOptions connectOptions = new ConnectOptions.Builder(call.getString("token"))
                .params(params)
                .build();
        Voice.connect(getContext(), connectOptions, callListener);
        call.success();
    }

    @PluginMethod()
    public void updateCall(PluginCall call) {
        Log.d("updateCall", call.toString());
//        TBD
        call.success();
    }

    @PluginMethod()
    public void endCall(PluginCall call) {
        Log.d("endCall", call.toString());
        if (activeCall != null) {
            activeCall.disconnect();
            activeCall = null;
            notifyListeners("disconnect", null);
            call.success();
        } else {
            call.reject("No active call");
        }
    }

    @PluginMethod()
    public void toggleMute(PluginCall call) {
        Log.d("toggleMute", call.toString());
        if (activeCall != null) {
            boolean mute = !activeCall.isMuted();
            activeCall.mute(mute);
            call.success();
        } else {
            call.reject("No active call");
        }
    }

    @PluginMethod()
    public void toggleSpeaker(PluginCall call) {
        Log.d("toggleSpeaker", call.toString());
        if (audioManager.isSpeakerphoneOn()) {
            audioManager.setSpeakerphoneOn(false);
        } else {
            audioManager.setSpeakerphoneOn(true);
        }
        call.success();
    }

    private Call.Listener callListener() {
        return new Call.Listener() {
            /*
             * This callback is emitted once before the Call.Listener.onConnected() callback when
             * the callee is being alerted of a Call. The behavior of this callback is determined by
             * the answerOnBridge flag provided in the Dial verb of your TwiML application
             * associated with this client. If the answerOnBridge flag is false, which is the
             * default, the Call.Listener.onConnected() callback will be emitted immediately after
             * Call.Listener.onRinging(). If the answerOnBridge flag is true, this will cause the
             * call to emit the onConnected callback only after the call is answered.
             * See answeronbridge for more details on how to use it with the Dial TwiML verb. If the
             * twiML response contains a Say verb, then the call will emit the
             * Call.Listener.onConnected callback immediately after Call.Listener.onRinging() is
             * raised, irrespective of the value of answerOnBridge being set to true or false
             */
            @Override
            public void onRinging(@NonNull Call call) {
                Log.d(TAG, "Ringing");
                /*
                 * When [answerOnBridge](https://www.twilio.com/docs/voice/twiml/dial#answeronbridge)
                 * is enabled in the <Dial> TwiML verb, the caller will not hear the ringback while
                 * the call is ringing and awaiting to be accepted on the callee's side. The application
                 * can use the `SoundPoolManager` to play custom audio files between the
                 * `Call.Listener.onRinging()` and the `Call.Listener.onConnected()` callbacks.
                 */
//                if (BuildConfig.playCustomRingback) {
//                    SoundPoolManager.getInstance(getContext()).playRinging();
//                }
            }

            @Override
            public void onConnectFailure(@NonNull Call call, @NonNull CallException error) {
                setAudioFocus(false);
//                if (BuildConfig.playCustomRingback) {
//                    SoundPoolManager.getInstance(VoiceActivity.this).stopRinging();
//                }
                Log.d(TAG, "Connect failure");
                String message = String.format(
                        Locale.US,
                        "Call Error: %d, %s",
                        error.getErrorCode(),
                        error.getMessage());
                Log.e(TAG, message);
                emitErrorToListeners(error);
                notifyListeners("disconnect", null);
            }

            @Override
            public void onConnected(@NonNull Call call) {
                setAudioFocus(true);
//                if (BuildConfig.playCustomRingback) {
//                    SoundPoolManager.getInstance(VoiceActivity.this).stopRinging();
//                }
                Log.d(TAG, "Connected :" + call.getState().toString());
                activeCall = call;
                notifyListeners("accept", null);
            }

            @Override
            public void onReconnecting(@NonNull Call call, @NonNull CallException callException) {
                Log.d(TAG, "onReconnecting");
                emitErrorToListeners(callException);
            }

            @Override
            public void onReconnected(@NonNull Call call) {
                Log.d(TAG, "onReconnected");
            }

            @Override
            public void onDisconnected(@NonNull Call call, CallException error) {
                setAudioFocus(false);
//                if (BuildConfig.playCustomRingback) {
//                    SoundPoolManager.getInstance(VoiceActivity.this).stopRinging();
//                }
                Log.d(TAG, "Disconnected");
                if (error != null) {
                    String message = String.format(
                            Locale.US,
                            "Call Error: %d, %s",
                            error.getErrorCode(),
                            error.getMessage());
                    Log.e(TAG, message);
                    emitErrorToListeners(error);
//                    Snackbar.make(coordinatorLayout, message, Snackbar.LENGTH_LONG).show();
                }
                notifyListeners("disconnect", null);
//                resetUI();
            }
        };
    }

    private void setAudioFocus(boolean setFocus) {
        if (audioManager != null) {
            if (setFocus) {
                savedAudioMode = audioManager.getMode();
                // Request audio focus before making any device switch.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    AudioAttributes playbackAttributes = new AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build();
                    AudioFocusRequest focusRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                            .setAudioAttributes(playbackAttributes)
                            .setAcceptsDelayedFocusGain(true)
                            .setOnAudioFocusChangeListener(i -> {
                            })
                            .build();
                    audioManager.requestAudioFocus(focusRequest);
                } else {
                    audioManager.requestAudioFocus(
                            focusChange -> { },
                            AudioManager.STREAM_VOICE_CALL,
                            AudioManager.AUDIOFOCUS_GAIN_TRANSIENT);
                }
                /*
                 * Start by setting MODE_IN_COMMUNICATION as default audio mode. It is
                 * required to be in this mode when playout and/or recording starts for
                 * best possible VoIP performance. Some devices have difficulties with speaker mode
                 * if this is not set.
                 */
                audioManager.setMode(AudioManager.MODE_IN_COMMUNICATION);
            } else {
                audioManager.setMode(savedAudioMode);
                audioManager.abandonAudioFocus(null);
            }
        }
    }

    private boolean checkPermissionForMicrophone() {
        int resultMic = ContextCompat.checkSelfPermission(getContext(), Manifest.permission.RECORD_AUDIO);
        return resultMic == PackageManager.PERMISSION_GRANTED;
    }

    private void requestPermissionForMicrophone() {
        if (ActivityCompat.shouldShowRequestPermissionRationale(getActivity(), Manifest.permission.RECORD_AUDIO)) {
            showPermissionsNeededSnackbar();
        } else {
            doRequestPermissionForMicrophone();
        }
    }

    @Override
    public void handleRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.handleRequestPermissionsResult(requestCode, permissions, grantResults);
        Log.d(TAG, "handleRequestPermissionsResult");
        PluginCall savedCall = getSavedCall();
        if (savedCall == null) {
            return;
        }
        Log.d(TAG, "Saved call:" + savedCall.toString());
        /*
         * Check if microphone permissions is granted
         */
        if (requestCode == MIC_PERMISSION_REQUEST_CODE && permissions.length > 0) {
            if (grantResults[0] != PackageManager.PERMISSION_GRANTED) {
                showPermissionsNeededSnackbar();
            }
        }
    }

    private void showPermissionsNeededSnackbar() {
        Snackbar.make(view,
                "Microphone permissions needed. Please allow in your application settings.",
                Snackbar.LENGTH_LONG)
                .setAction("Configure", new View.OnClickListener() {

                    @Override
                    public void onClick(View v) {
                        doRequestPermissionForMicrophone();
                    }
                })
                .show();
    }

    private void doRequestPermissionForMicrophone() {
        ActivityCompat.requestPermissions(
                getActivity(),
                new String[]{Manifest.permission.RECORD_AUDIO},
                MIC_PERMISSION_REQUEST_CODE);
    }

    private void emitErrorToListeners(@NonNull CallException error) {
        JSObject errorToReturn = new JSObject();
        errorToReturn.put("code", error.getErrorCode());
        errorToReturn.put("message", error.getMessage());
        notifyListeners("error", errorToReturn);
    }
}
