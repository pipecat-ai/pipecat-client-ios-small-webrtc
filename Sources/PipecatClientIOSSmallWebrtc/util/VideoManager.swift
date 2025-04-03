import Foundation
@_implementationOnly import WebRTC

internal class VideoManager {

    internal var availableDevices: [Device] {
        let captureDevices = RTCCameraVideoCapturer.captureDevices()
        let devices: [Device] = captureDevices.compactMap { device in
            guard device.hasMediaType(AVMediaType.video) else {
                return nil
            }
            return Device(
                deviceID: device.uniqueID,

                groupID: "",
                kind: DeviceKind.videoInput,
                label: device.localizedName
            )
        }
        return devices
    }

}
