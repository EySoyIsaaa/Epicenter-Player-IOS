#import <Capacitor/Capacitor.h>

CAP_PLUGIN(MusicScannerPlugin, "MusicScanner",
           CAP_PLUGIN_METHOD(requestAudioPermissions, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(checkPermissions, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(scanMusic, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(getAudioFileUrl, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(clearAudioCache, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(getAlbumArt, CAPPluginReturnPromise);
)
