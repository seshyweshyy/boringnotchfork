//
//  AudioRouteManager.swift
//  Knotch
//

import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let transportType: UInt32

    var iconName: String {
        let n = name.lowercased()
        if n.contains("airpods") { return "airpodspro" }
        if n.contains("macbook") { return "laptopcomputer" }
        if n.contains("headphone") || n.contains("headset") { return "headphones" }
        if n.contains("beats") { return "headphones" }
        if n.contains("homepod") { return "hifispeaker.2" }
        switch transportType {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return n.contains("speaker") ? "speaker.wave.2" : "headphones"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI:
            return "tv"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeFireWire:
            return "hifispeaker.2"
        case kAudioDeviceTransportTypeBuiltIn:
            return n.contains("display") ? "tv" : "speaker.wave.2"
        default:
            return "speaker.wave.2"
        }
    }
}

final class AudioRouteManager: ObservableObject {
    static let shared = AudioRouteManager()

    @Published private(set) var devices: [AudioOutputDevice] = []
    @Published private(set) var activeDeviceID: AudioDeviceID = 0

    private let queue = DispatchQueue(label: "com.boringnotch.audio-route", qos: .userInitiated)

    private init() {
        refreshDevices()
        var propAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propAddr,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.refreshDevices()
        }
    }

    var activeDevice: AudioOutputDevice? {
        devices.first { $0.id == activeDeviceID }
    }

    func refreshDevices() {
        queue.async { [weak self] in
            guard let self else { return }
            let defaultID = self.fetchDefaultOutputDevice()
            let infos = self.fetchOutputDeviceIDs().compactMap(self.makeDeviceInfo)
            let sorted = infos.sorted {
                if $0.id == defaultID { return true }
                if $1.id == defaultID { return false }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            DispatchQueue.main.async {
                self.activeDeviceID = defaultID
                self.devices = sorted
            }
        }
    }

    func select(device: AudioOutputDevice) {
        queue.async { [weak self] in
            self?.setDefaultOutputDevice(device.id)
        }
    }

    // MARK: - Private

    private func fetchDefaultOutputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : 0
    }

    private func fetchOutputDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else { return [] }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids) == noErr else { return [] }
        return ids
    }

    private func makeDeviceInfo(for deviceID: AudioDeviceID) -> AudioOutputDevice? {
        guard deviceHasOutputChannels(deviceID) else { return nil }
        guard let name = deviceName(for: deviceID) else { return nil }
        let transport = transportType(for: deviceID)
        return AudioOutputDevice(id: deviceID, name: name, transportType: transport)
    }

    private func deviceHasOutputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr else { return false }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, buffer) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name as String
    }

    private func transportType(for deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var type: UInt32 = kAudioDeviceTransportTypeUnknown
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &type)
        return type
    }

    private func setDefaultOutputDevice(_ deviceID: AudioDeviceID) {
        var target = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &target)
        if status == noErr {
            DispatchQueue.main.async { [weak self] in
                self?.activeDeviceID = deviceID
            }
            refreshDevices()
        }
    }
}
