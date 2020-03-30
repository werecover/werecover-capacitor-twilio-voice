import Foundation
import Capacitor
import PushKit
import CallKit
import TwilioVoice

@objc(TwilioVoicePlugin)
public class TwilioVoicePlugin: CAPPlugin, PKPushRegistryDelegate, TVONotificationDelegate, TVOCallDelegate, CXProviderDelegate, AVAudioPlayerDelegate {

    var accessToken: String = ""
    var deviceTokenString: String?
    
    var voipRegistry: PKPushRegistry? = nil
    var incomingPushCompletionCallback: (()->Swift.Void?)? = nil

    var callKitCompletionCallback: ((Bool)->Swift.Void?)? = nil
    var audioDevice: TVODefaultAudioDevice = TVODefaultAudioDevice()
    var activeCallInvites: [String: TVOCallInvite]! = [:]
    var activeCalls: [String: TVOCall]! = [:]
    
    var callParams: [String: String] = [:]
    var activeCall: TVOCall? = nil

    var callKitProvider: CXProvider
    var callKitCallController: CXCallController
    var userInitiatedDisconnect: Bool = false
    
    var playCustomRingback: Bool = false
    var ringtonePlayer: AVAudioPlayer? = nil
    
    public override init!(bridge: CAPBridge!, pluginId: String!, pluginName: String!) {
        NSLog("Initing...");
    
        let configuration = CXProviderConfiguration(localizedName: "Werecover")
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        if let callKitIcon = UIImage(named: "iconMask80") {
            configuration.iconTemplateImageData = callKitIcon.pngData()
        }

        callKitProvider = CXProvider(configuration: configuration)
        callKitCallController = CXCallController()

        super.init(bridge: bridge, pluginId: pluginId, pluginName: pluginName)
        
        callKitProvider.setDelegate(self, queue: nil)
        
        NSLog("Inited");
    }
        
    deinit {
        // CallKit has an odd API contract where the developer must call invalidate or the CXProvider is leaked.
        callKitProvider.invalidate()
    }
            
    @objc func initPlugin(_ call: CAPPluginCall) {
        NSLog("initPlugin:");
        guard let token = call.getString("token") else {
            call.reject("No token")
            return
        }
        
        NSLog("accessToken: \(token)");
        self.accessToken = token
        
        voipRegistry = PKPushRegistry.init(queue: DispatchQueue.main)
        voipRegistry!.delegate = self
        voipRegistry!.desiredPushTypes = Set([PKPushType.voIP])
        
        /*
         * The important thing to remember when providing a TVOAudioDevice is that the device must be set
         * before performing any other actions with the SDK (such as connecting a Call, or accepting an incoming Call).
         * In this case we've already initialized our own `TVODefaultAudioDevice` instance which we will now set.
         */
        TwilioVoice.audioDevice = audioDevice
    
        call.success()
    }

    @objc func call(_ pluginCall: CAPPluginCall) {
        NSLog("call:");
        if self.activeCall != nil {
            pluginCall.reject("Busy")
        } else {
            guard let token = pluginCall.getString("token") else {
                pluginCall.reject("No token")
                return
            }
            
            guard let to = pluginCall.getString("To") else {
                pluginCall.reject("`To` param missing")
                return
            }
            
            pluginCall.success()
            
            self.callParams = [
                "To": to,
                "From": pluginCall.getString("From") ?? "",
                "to_patient_id": String(pluginCall.getInt("to_patient_id") ?? 0),
                "to_name": pluginCall.getString("to_name") ?? "",
                "from_user_id": String(pluginCall.getInt("from_user_id") ?? 0),
                "from_user_name": pluginCall.getString("from_user_name") ?? ""
            ]
            
            self.accessToken = token
            
            let uuid = UUID()
            let handle = "Werecover"
            
            self.checkRecordPermission { (permissionGranted) in
                if (!permissionGranted) {
                    let alertController: UIAlertController = UIAlertController(title: "Werecover",
                                                                               message: "Microphone permission not granted",
                                                                               preferredStyle: .alert)
                    
                    let continueWithMic: UIAlertAction = UIAlertAction(title: "Continue without microphone",
                                                                       style: .default,
                                                                       handler: { (action) in
                        self.performStartCallAction(uuid: uuid, handle: handle)
                    })
                    alertController.addAction(continueWithMic)
                    
                    let goToSettings: UIAlertAction = UIAlertAction(title: "Settings",
                                                                    style: .default,
                                                                    handler: { (action) in
                                                                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                                                                  options: [UIApplication.OpenExternalURLOptionsKey.universalLinksOnly: false],
                                                  completionHandler: nil)
                    })
                    alertController.addAction(goToSettings)
                    
                    let cancel: UIAlertAction = UIAlertAction(title: "Cancel",
                                                              style: .cancel,
                                                              handler: { (action) in
                                                                self.notifyListeners("disconnect", data: [:])
                    })
                    alertController.addAction(cancel)
                    
                    DispatchQueue.main.async {
                        self.bridge.viewController.present(alertController, animated: true, completion: nil)
                    }
                } else {
                    self.performStartCallAction(uuid: uuid, handle: handle)
                }
            }
        }
    }
    
    @objc func endCall(_ pluginCall: CAPPluginCall) {
        NSLog("endCall:");
        if let call = self.activeCall {
            self.userInitiatedDisconnect = true
            performEndCallAction(uuid: call.uuid)
            pluginCall.success()
        } else {
            pluginCall.reject("No active call")
        }
    }
    
    @objc func toggleMute(_ pluginCall: CAPPluginCall) {
        NSLog("toggleMute:");
        // The sample app supports toggling mute from app UI only on the last connected call.
        if let call = self.activeCall {
            call.isMuted = pluginCall.getBool("status") ?? false
            pluginCall.success()
        } else {
            pluginCall.reject("No active call")
        }
    }
    
    @objc func toggleSpeaker(_ pluginCall: CAPPluginCall) {
        NSLog("toggleSpeaker:");
        toggleAudioRoute(toSpeaker: pluginCall.getBool("status") ?? true)
        pluginCall.success()
    }
    
    func checkRecordPermission(completion: @escaping (_ permissionGranted: Bool) -> Void) {
        let permissionStatus: AVAudioSession.RecordPermission = AVAudioSession.sharedInstance().recordPermission
        
        switch permissionStatus {
        case AVAudioSessionRecordPermission.granted:
            // Record permission already granted.
            completion(true)
            break
        case AVAudioSessionRecordPermission.denied:
            // Record permission denied.
            completion(false)
            break
        case AVAudioSessionRecordPermission.undetermined:
            // Requesting record permission.
            // Optional: pop up app dialog to let the users know if they want to request.
            AVAudioSession.sharedInstance().requestRecordPermission({ (granted) in
                completion(granted)
            })
            break
        default:
            completion(false)
            break
        }
    }

    // MARK: PKPushRegistryDelegate
    public func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        NSLog("pushRegistry:didUpdatePushCredentials:forType:")
        
        if (type != .voIP) {
            return
        }
        
        let deviceToken = credentials.token.map { String(format: "%02x", $0) }.joined()

        TwilioVoice.register(withAccessToken: self.accessToken, deviceToken: deviceToken) { (error) in
            if let error = error {
                NSLog("An error occurred while registering: \(error.localizedDescription)")
            }
            else {
                NSLog("Successfully registered for VoIP push notifications.")
            }
        }

        self.deviceTokenString = deviceToken
    }
    
    public func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        NSLog("pushRegistry:didInvalidatePushTokenForType:")
        
        if (type != .voIP) {
            return
        }
        
        guard let deviceToken = deviceTokenString else {
            return
        }
        
        TwilioVoice.unregister(withAccessToken: self.accessToken, deviceToken: deviceToken) { (error) in
            if let error = error {
                NSLog("An error occurred while unregistering: \(error.localizedDescription)")
            }
            else {
                NSLog("Successfully unregistered from VoIP push notifications.")
            }
        }
        
        self.deviceTokenString = nil
    }

    /**
     * Try using the `pushRegistry:didReceiveIncomingPushWithPayload:forType:withCompletionHandler:` method if
     * your application is targeting iOS 11. According to the docs, this delegate method is deprecated by Apple.
     */
    public func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType) {
        NSLog("pushRegistry:didReceiveIncomingPushWithPayload:forType:")

        if (type == PKPushType.voIP) {
            // The Voice SDK will use main queue to invoke `cancelledCallInviteReceived:error:` when delegate queue is not passed
            TwilioVoice.handleNotification(payload.dictionaryPayload, delegate: self, delegateQueue: nil)
        }
    }

    /**
     * This delegate method is available on iOS 11 and above. Call the completion handler once the
     * notification payload is passed to the `TwilioVoice.handleNotification()` method.
     */
    public func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        NSLog("pushRegistry:didReceiveIncomingPushWithPayload:forType:completion:")

        if (type == PKPushType.voIP) {
            // The Voice SDK will use main queue to invoke `cancelledCallInviteReceived:error:` when delegate queue is not passed
            TwilioVoice.handleNotification(payload.dictionaryPayload, delegate: self, delegateQueue: nil)
        }
        
        if let version = Float(UIDevice.current.systemVersion), version < 13.0 {
            // Save for later when the notification is properly handled.
            self.incomingPushCompletionCallback = completion
        } else {
            /**
            * The Voice SDK processes the call notification and returns the call invite synchronously. Report the incoming call to
            * CallKit and fulfill the completion before exiting this callback method.
            */
            completion()
        }
    }

    func incomingPushHandled() {
        if let completion = self.incomingPushCompletionCallback {
            completion()
            self.incomingPushCompletionCallback = nil
        }
    }

    // MARK: TVONotificaitonDelegate
    public func callInviteReceived(_ callInvite: TVOCallInvite) {
        NSLog("callInviteReceived:")
        
        var from:String = callInvite.from ?? "Werecover"
        from = from.replacingOccurrences(of: "client:", with: "")

        // Always report to CallKit
        reportIncomingCall(from: from, uuid: callInvite.uuid)
        self.activeCallInvites[callInvite.uuid.uuidString] = callInvite
    }
    
    public func cancelledCallInviteReceived(_ cancelledCallInvite: TVOCancelledCallInvite, error: Error) {
        NSLog("cancelledCallInviteCanceled:error:, error: \(error.localizedDescription)")
        
        if (self.activeCallInvites!.isEmpty) {
            NSLog("No pending call invite")
            return
        }
        
        var callInvite: TVOCallInvite?
        for (_, invite) in self.activeCallInvites {
            if (invite.callSid == cancelledCallInvite.callSid) {
                callInvite = invite
                break
            }
        }
        
        if let callInvite = callInvite {
            performEndCallAction(uuid: callInvite.uuid)
        }
    }

    // MARK: TVOCallDelegate
    public func callDidStartRinging(_ call: TVOCall) {
        NSLog("callDidStartRinging:")
        
        self.notifyListeners("ringing", data: [:])
        
        /*
         When [answerOnBridge](https://www.twilio.com/docs/voice/twiml/dial#answeronbridge) is enabled in the
         <Dial> TwiML verb, the caller will not hear the ringback while the call is ringing and awaiting to be
         accepted on the callee's side. The application can use the `AVAudioPlayer` to play custom audio files
         between the `[TVOCallDelegate callDidStartRinging:]` and the `[TVOCallDelegate callDidConnect:]` callbacks.
        */
        if (self.playCustomRingback) {
            self.playRingback()
        }
        
    }
    
    public func callDidConnect(_ call: TVOCall) {
        NSLog("callDidConnect:")
        
        if (self.playCustomRingback) {
            self.stopRingback()
        }
        
        self.callKitCompletionCallback!(true)
        
        toggleAudioRoute(toSpeaker: false)
        self.notifyListeners("accept", data: [:])
    }
    
    public func call(_ call: TVOCall, isReconnectingWithError error: Error) {
        NSLog("call:isReconnectingWithError:")
        self.notifyListeners("reconnecting", data: ["error": error.localizedDescription])
    }
    
    public func callDidReconnect(_ call: TVOCall) {
        NSLog("callDidReconnect:")
        self.notifyListeners("reconnected", data: [:])
    }
    
    public func call(_ call: TVOCall, didFailToConnectWithError error: Error) {
        NSLog("Call failed to connect: \(error.localizedDescription)")
        self.notifyListeners("error", data: ["error": error.localizedDescription ])

        if let completion = self.callKitCompletionCallback {
            completion(false)
        }

        performEndCallAction(uuid: call.uuid)
        callDisconnected(call)
    }
    
    public func call(_ call: TVOCall, didDisconnectWithError error: Error?) {
        NSLog("call: didDisconnectWithError:")
        if let error = error {
            NSLog("Call failed: \(error.localizedDescription)")
            self.notifyListeners("error", data: ["error": error.localizedDescription ])
        } else {
            NSLog("Call disconnected")
        }
        
        if !self.userInitiatedDisconnect {
            var reason = CXCallEndedReason.remoteEnded
            
            if error != nil {
                reason = .failed
            }
            
            self.callKitProvider.reportCall(with: call.uuid, endedAt: Date(), reason: reason)
        }

        callDisconnected(call)
    }
    
    func callDisconnected(_ call: TVOCall) {
        if (call == self.activeCall) {
            self.activeCall = nil
        }
        self.activeCalls.removeValue(forKey: call.uuid.uuidString)
        self.userInitiatedDisconnect = false
        if (self.playCustomRingback) {
            self.stopRingback()
        }
        
        self.notifyListeners("disconnect", data: [:])
    }
    
    
    // MARK: AVAudioSession
    func toggleAudioRoute(toSpeaker: Bool) {
        // The mode set by the Voice SDK is "VoiceChat" so the default audio route is the built-in receiver. Use port override to switch the route.
        audioDevice.block = {
            kTVODefaultAVAudioSessionConfigurationBlock()
            do {
                if (toSpeaker) {
                    try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
                } else {
                    try AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
                }
            } catch {
                NSLog(error.localizedDescription)
            }
        }
        audioDevice.block()
    }

    // MARK: CXProviderDelegate
    public func providerDidReset(_ provider: CXProvider) {
        NSLog("providerDidReset:")
        audioDevice.isEnabled = true
    }

    public func providerDidBegin(_ provider: CXProvider) {
        NSLog("providerDidBegin")
    }

    public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        NSLog("provider:didActivateAudioSession:")
        audioDevice.isEnabled = true
    }

    public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        NSLog("provider:didDeactivateAudioSession:")
    }

    public func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        NSLog("provider:timedOutPerformingAction:")
    }

    public func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        NSLog("provider:performStartCallAction:")
        
        audioDevice.isEnabled = false
        audioDevice.block();
        
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
        
        self.performVoiceCall(uuid: action.callUUID, client: "") { (success) in
            if (success) {
                provider.reportOutgoingCall(with: action.callUUID, connectedAt: Date())
                action.fulfill()
            } else {
                action.fail()
            }
        }
    }

    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        NSLog("provider:performAnswerCallAction:")
        
        audioDevice.isEnabled = false
        audioDevice.block();
        
        self.performAnswerVoiceCall(uuid: action.callUUID) { (success) in
            if (success) {
                action.fulfill()
            } else {
                action.fail()
            }
        }
        
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        NSLog("provider:performEndCallAction:")
        
        if let invite = self.activeCallInvites[action.callUUID.uuidString] {
            invite.reject()
            self.activeCallInvites.removeValue(forKey: action.callUUID.uuidString)
        } else if let call = self.activeCalls[action.callUUID.uuidString] {
            call.disconnect()
        } else {
            NSLog("Unknown UUID to perform end-call action with")
        }

        action.fulfill()
    }
    
    public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        NSLog("provider:performSetHeldAction:")
        
        if let call = self.activeCalls[action.callUUID.uuidString] {
            call.isOnHold = action.isOnHold
            action.fulfill()
        } else {
            action.fail()
        }
    }
    
    public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        NSLog("provider:performSetMutedAction:")

        if let call = self.activeCalls[action.callUUID.uuidString] {
            call.isMuted = action.isMuted
            action.fulfill()
        } else {
            action.fail()
        }
    }

    // MARK: Call Kit Actions
    func performStartCallAction(uuid: UUID, handle: String) {
        let callHandle = CXHandle(type: .generic, value: handle)
        let startCallAction = CXStartCallAction(call: uuid, handle: callHandle)
        let transaction = CXTransaction(action: startCallAction)

        callKitCallController.request(transaction)  { error in
            if let error = error {
                NSLog("StartCallAction transaction request failed: \(error.localizedDescription)")
                return
            }

            NSLog("StartCallAction transaction request successful")

            let callUpdate = CXCallUpdate()
            callUpdate.remoteHandle = callHandle
            callUpdate.supportsDTMF = true
            callUpdate.supportsHolding = true
            callUpdate.supportsGrouping = false
            callUpdate.supportsUngrouping = false
            callUpdate.hasVideo = false

            self.callKitProvider.reportCall(with: uuid, updated: callUpdate)
        }
    }

    func reportIncomingCall(from: String, uuid: UUID) {
        
        let callHandle = CXHandle(type: .generic, value: from)

        let callUpdate = CXCallUpdate()
        callUpdate.remoteHandle = callHandle
        callUpdate.supportsDTMF = true
        callUpdate.supportsHolding = true
        callUpdate.supportsGrouping = false
        callUpdate.supportsUngrouping = false
        callUpdate.hasVideo = false

        callKitProvider.reportNewIncomingCall(with: uuid, update: callUpdate) { error in
            if let error = error {
                NSLog("Failed to report incoming call successfully: \(error.localizedDescription).")
            } else {
                NSLog("Incoming call successfully reported.")
            }
        }
    }

    func performEndCallAction(uuid: UUID) {
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)

        callKitCallController.request(transaction) { error in
            if let error = error {
                NSLog("EndCallAction transaction request failed: \(error.localizedDescription).")
            } else {
                NSLog("EndCallAction transaction request successful")
            }
        }
    }
    
    func performVoiceCall(uuid: UUID, client: String?, completionHandler: @escaping (Bool) -> Swift.Void) {
        NSLog("performVoiceCall: \(uuid)")
        let connectOptions: TVOConnectOptions = TVOConnectOptions(accessToken: self.accessToken) { (builder) in
            builder.params = self.callParams
            builder.uuid = uuid
        }
        let call = TwilioVoice.connect(with: connectOptions, delegate: self)
        self.activeCall = call
        self.activeCalls[call.uuid.uuidString] = call
        self.callKitCompletionCallback = completionHandler
    }
    
    func performAnswerVoiceCall(uuid: UUID, completionHandler: @escaping (Bool) -> Swift.Void) {
        if let callInvite = self.activeCallInvites[uuid.uuidString] {
            let acceptOptions: TVOAcceptOptions = TVOAcceptOptions(callInvite: callInvite) { (builder) in
                builder.uuid = callInvite.uuid
            }
            let call = callInvite.accept(with: acceptOptions, delegate: self)
            self.activeCall = call
            self.activeCalls[call.uuid.uuidString] = call
            self.callKitCompletionCallback = completionHandler
            
            self.activeCallInvites.removeValue(forKey: uuid.uuidString)
            
            guard #available(iOS 13, *) else {
                self.incomingPushHandled()
                return
            }
        } else {
            NSLog("No CallInvite matches the UUID")
        }
    }
    
    // MARK: Ringtone
    func playRingback() {
        let ringtonePath = URL(fileURLWithPath: Bundle.main.path(forResource: "ringtone", ofType: "wav")!)
        do {
            self.ringtonePlayer = try AVAudioPlayer(contentsOf: ringtonePath)
            self.ringtonePlayer?.delegate = self
            self.ringtonePlayer?.numberOfLoops = -1
            
            self.ringtonePlayer?.volume = 1.0
            self.ringtonePlayer?.play()
        } catch {
            NSLog("Failed to initialize audio player")
        }
    }
    
    func stopRingback() {
        if (self.ringtonePlayer?.isPlaying == false) {
            return
        }
        self.ringtonePlayer?.stop()
    }
    
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if (flag) {
            NSLog("Audio player finished playing successfully");
        } else {
            NSLog("Audio player finished playing with some error");
        }
    }
    
    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        NSLog("Decode error occurred: \(error?.localizedDescription ?? "audioPlayerDecodeErrorDidOccur error")");
    }
}
