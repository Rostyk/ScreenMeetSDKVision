//
//  SMTrackBuilder.swift
//  ScreenMeet
//
//  Created by Ross on 22.02.2021.
//

import UIKit
import WebRTC

class SMTracksManager: NSObject {
    private var lastImageHandler: SMImageHandler? = nil
    var videoSourceDevice: AVCaptureDevice?
    var shouldUseCustomImageSessionForVideoSharing = false
    private var mediaStream: RTCMediaStream!
    private var videoSource: RTCVideoSource!
    private var videoTrack: RTCVideoTrack!
    private var audioTrack: RTCAudioTrack!
    
    private var videoCapturer: SMVideoCapturer!
    
    private var factory: RTCPeerConnectionFactory = RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
    
    func makeVideoTrack() -> RTCVideoTrack {
        if mediaStream == nil {
            self.mediaStream = self.factory.mediaStream(withStreamId: "0")
        }
                
        videoSource = factory.videoSource()
        
        videoTrack = factory.videoTrack(with: videoSource, trackId: "ARDAMSv0")
        self.mediaStream.addVideoTrack(videoTrack)
        return videoTrack
    }
    
    func makeAudioTrack() -> RTCAudioTrack {
        audioTrack = factory.audioTrack(withTrackId: "ARDAMSa0")
        audioTrack.isEnabled = true
        
        if mediaStream == nil {
            self.mediaStream = self.factory.mediaStream(withStreamId: "0")
        }
        
        self.mediaStream.addAudioTrack(audioTrack)
        return audioTrack
    }
    
    /// Captureres
    
    func startCapturer(_ videoSourceDevice: AVCaptureDevice?, _ completionHandler: SMCapturerOperationCompletion? = nil) {
        if (videoCapturer != nil) {
            //Video capturer already started
            completionHandler?(nil)
            return
        }
        
        if shouldUseCustomImageSessionForVideoSharing {
            self.videoSourceDevice = nil
            videoCapturer = VideoCapturerFactory.fakeCapturer(delegate: self)
            completionHandler?(nil)
        }
        else {
            videoCapturer = VideoCapturerFactory.videoCapturer(videoSourceDevice, delegate: self)
            videoCapturer.delegate = nil
            videoCapturer.startCapture() { [weak self] error in
                if let error = error {
                    completionHandler?(error)
                }
                else {
                    if #available(iOS 13.0, *) {
                        let captureSessionConnections = self?.videoCapturer.getCaptureSession().connections
                        captureSessionConnections?.first?.videoOrientation = .portrait
                        
                        completionHandler?(nil)
                        self?.videoCapturer.delegate = self
                        
                    }
                    else {
                        completionHandler?(SMError(code: .capturerInternalError, message: "Unsupported iOS version"))
                    }
                }
            }
        }
    }

    func stopCapturer(completionHandler: SMCapturerOperationCompletion? = nil) {
        if (videoCapturer == nil) {
            // Video capturer already stopped
            completionHandler?(nil)
            return
        }
        
        videoCapturer.stopCapture(completionHandler)
    }
    
    func cleanupVideo() {
        if (self.videoCapturer != nil) {
            self.videoCapturer.stopCapture { error in
                
            }
        }
       
        self.videoCapturer = nil
        if (self.videoTrack != nil) {
            if (self.mediaStream != nil)  {
                self.mediaStream.removeVideoTrack(videoTrack)
            }
        }
        self.mediaStream = nil
        self.videoTrack = nil
        self.videoSource = nil
    }
    
    func cleanupAudio() {
        if (self.audioTrack != nil) {
            if (self.mediaStream != nil)  {
                self.mediaStream.removeAudioTrack(audioTrack)
            }
            
            self.audioTrack.isEnabled = false
            self.audioTrack = nil
        }
    }

    func changeCapturer(_ videoSourceDevice: AVCaptureDevice!, _ isImageTransfer: Bool, _ completionHandler: SMCapturerOperationCompletion? = nil) {
        if (videoCapturer != nil) {
            videoCapturer.delegate = nil
            videoCapturer.stopCapture({ [weak self] error in
                guard error == nil else {
                    completionHandler?(error)
                    return
                }
                var newCapturer: SMVideoCapturer!
                
                if isImageTransfer {
                    newCapturer = VideoCapturerFactory.fakeCapturer(delegate: self!)
                }
                else {
                    newCapturer = VideoCapturerFactory.videoCapturer(videoSourceDevice, delegate: self!)
                }
               
                newCapturer.delegate = nil
                newCapturer.startCapture({error in
                    guard error == nil else {
                        completionHandler?(error)
                        return
                    }
                    if #available(iOS 13.0, *) {
                        let captureSessionConnections = newCapturer.getCaptureSession().connections
                        captureSessionConnections.first?.videoOrientation = .portrait
                    }
                    
                    newCapturer.delegate = self
                    completionHandler?(error)
                })
                
                
                self?.videoCapturer = newCapturer
            })
        } else {
            let newCapturer = VideoCapturerFactory.videoCapturer(videoSourceDevice, delegate: self)
            newCapturer.startCapture({error in
                guard error == nil else {
                    completionHandler?(error)
                    return
                }
                newCapturer.startCapture(nil)
                self.videoCapturer = newCapturer
            })
        }
    }
    
    func getVideoSourceDevice() -> AVCaptureDevice? {
        if let cameraCapturer = self.videoCapturer as? CameraVideoCapturer {
            return cameraCapturer.device
        }
        return nil
    }
    
    func createImageTransferHandler() -> SMImageHandler {
        lastImageHandler?.release()
        lastImageHandler = nil
        shouldUseCustomImageSessionForVideoSharing = true
                                      
        lastImageHandler = SMImageHandler()
        lastImageHandler?.imageHandler = { image in
            (self.videoCapturer as? FakeCapturer)?.sendImage(image)
        }
        
        return lastImageHandler!
    }
}

extension SMTracksManager: RTCVideoCapturerDelegate {
    func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
        DispatchQueue.main.async {
            //UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        }
        self.videoSource?.capturer(capturer, didCapture: frame)
    }
}
