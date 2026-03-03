import Foundation
import Capacitor
import MediaPlayer
import AVFoundation
import UIKit

@objc(MusicScannerPlugin)
public class MusicScannerPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "MusicScannerPlugin"
    public let jsName = "MusicScanner"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "requestAudioPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "checkPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "scanMusic", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getAudioFileUrl", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clearAudioCache", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getAlbumArt", returnType: CAPPluginReturnPromise)
    ]

    private lazy var audioCacheURL: URL = {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = cacheDir.appendingPathComponent("audio_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    @objc func requestAudioPermissions(_ call: CAPPluginCall) {
        MPMediaLibrary.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                call.resolve(["granted": self?.isAuthorized(status) ?? false])
            }
        }
    }

    @objc override public func checkPermissions(_ call: CAPPluginCall) {
        let status = MPMediaLibrary.authorizationStatus()
        call.resolve(["granted": isAuthorized(status)])
    }

    @objc func scanMusic(_ call: CAPPluginCall) {
        guard isAuthorized(MPMediaLibrary.authorizationStatus()) else {
            call.reject("Permission not granted")
            return
        }

        let query = MPMediaQuery.songs()
        let songs = query.items ?? []
        var files: [[String: Any]] = []

        for song in songs {
            guard let url = song.assetURL else { continue }

            let mimeType = guessMimeType(from: song)
            if mimeType == "application/octet-stream" { continue }

            let identifier = song.persistentID
            let albumArtUri = "ios-artwork://\(identifier)"
            let isHiRes = mimeType.contains("flac") || mimeType.contains("wav") || mimeType.contains("aiff") || mimeType.contains("alac") || mimeType.contains("dsd")

            files.append([
                "id": "\(identifier)",
                "name": song.title ?? url.lastPathComponent,
                "title": song.title ?? url.deletingPathExtension().lastPathComponent,
                "artist": song.artist ?? "Unknown Artist",
                "album": song.albumTitle ?? "Unknown Album",
                "duration": Int(song.playbackDuration.rounded()),
                "size": estimateFileSize(song: song),
                "mimeType": mimeType,
                "contentUri": url.absoluteString,
                "albumArtUri": albumArtUri,
                "isHiRes": isHiRes
            ])
        }

        call.resolve([
            "files": files,
            "count": files.count
        ])
    }

    @objc func getAudioFileUrl(_ call: CAPPluginCall) {
        guard let contentUri = call.getString("contentUri"),
              let sourceURL = URL(string: contentUri) else {
            call.reject("contentUri is required")
            return
        }

        let trackId = call.getString("trackId") ?? UUID().uuidString
        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let destinationURL = audioCacheURL.appendingPathComponent("track_\(trackId).\(ext)")

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            call.resolve([
                "filePath": destinationURL.path,
                "mimeType": mimeTypeFromExtension(ext),
                "cached": true
            ])
            return
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            let attrs = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
            let size = attrs[.size] as? NSNumber
            call.resolve([
                "filePath": destinationURL.path,
                "mimeType": mimeTypeFromExtension(ext),
                "size": size?.int64Value ?? 0,
                "cached": false
            ])
        } catch {
            call.reject("Error getting audio: \(error.localizedDescription)")
        }
    }

    @objc func clearAudioCache(_ call: CAPPluginCall) {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: audioCacheURL, includingPropertiesForKeys: nil)
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
            call.resolve(["success": true])
        } catch {
            call.reject("Error clearing cache: \(error.localizedDescription)")
        }
    }

    @objc func getAlbumArt(_ call: CAPPluginCall) {
        guard let albumArtUri = call.getString("albumArtUri") else {
            call.resolve(["dataUrl": NSNull()])
            return
        }

        let idString = albumArtUri.replacingOccurrences(of: "ios-artwork://", with: "")
        guard let persistentId = UInt64(idString) else {
            call.resolve(["dataUrl": NSNull()])
            return
        }

        let predicate = MPMediaPropertyPredicate(value: NSNumber(value: persistentId), forProperty: MPMediaItemPropertyPersistentID)
        let query = MPMediaQuery.songs()
        query.addFilterPredicate(predicate)

        guard let item = query.items?.first,
              let artwork = item.artwork,
              let image = artwork.image(at: CGSize(width: 600, height: 600)),
              let jpegData = image.jpegData(compressionQuality: 0.85) else {
            call.resolve(["dataUrl": NSNull()])
            return
        }

        let base64 = jpegData.base64EncodedString()
        call.resolve(["dataUrl": "data:image/jpeg;base64,\(base64)"])
    }

    private func isAuthorized(_ status: MPMediaLibraryAuthorizationStatus) -> Bool {
        status == .authorized
    }

    private func estimateFileSize(song: MPMediaItem) -> Int64 {
        if let value = song.value(forProperty: "fileSize") as? NSNumber {
            return value.int64Value
        }
        return 0
    }

    private func guessMimeType(from song: MPMediaItem) -> String {
        guard let url = song.assetURL else { return "application/octet-stream" }
        return mimeTypeFromExtension(url.pathExtension)
    }

    private func mimeTypeFromExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "mp3": return "audio/mpeg"
        case "m4a", "mp4": return "audio/mp4"
        case "wav": return "audio/wav"
        case "aif", "aiff": return "audio/aiff"
        case "flac": return "audio/flac"
        case "caf": return "audio/x-caf"
        default: return "application/octet-stream"
        }
    }
}
