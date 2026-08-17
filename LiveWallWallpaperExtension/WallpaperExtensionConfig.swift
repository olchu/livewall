import ExtensionFoundation
import Foundation

/// Accepts XPC connections from WallpaperAgent and wires them to
/// `WallpaperXPCHandler`. The handler is a Phase 2 stub — every method
/// replies with an honest "nothing yet" instead of rendering — so this only
/// proves the full protocol surface can be served without WallpaperAgent
/// treating the extension as broken. See SPEC.md §3.5.
struct WallpaperExtensionConfig: AppExtensionConfiguration {
    func accept(connection: NSXPCConnection) -> Bool {
        log("XPC from PID=\(connection.processIdentifier)")

        // Validate the caller before building interfaces, exporting the handler,
        // or resuming — an unexpected (non-Apple) process never reaches our
        // exported methods.
        guard CallerValidation.isAcceptable(connection) else {
            log("XPC rejected: untrusted caller")
            return false
        }

        let exported = NSXPCInterface(with: (any WallpaperExtensionXPCProtocol).self)

        // Build class whitelist from runtime-loaded WallpaperExtensionKit classes.
        let typeNames = [
            "WallpaperIDXPC",
            "WallpaperCreationRequestXPC",
            "WallpaperUpdateRequestXPC",
            "WallpaperRemoteContextXPC",
            "WallpaperSnapshotXPC",
            "WallpaperContentTypeSetXPC",
            "WallpaperChoiceIDXPC",
            "WallpaperChoiceIDsXPC",
            "WallpaperExtensionChoiceRequestXPC",
            "WallpaperChoiceRequestAdditionResultXPC",
            "WallpaperDebugRequestXPC",
            "WallpaperDebugResponseXPC",
            "WallpaperMigrationVersionXPC",
            "WallpaperSettingsViewModelsXPC",
            "AuditTokenXPC",
        ]

        let allTypes = NSMutableSet()
        var missing: [String] = []
        for name in typeNames {
            if let cls = objc_getClass(name) {
                allTypes.add(cls)
            } else {
                missing.append(name)
            }
        }
        if !missing.isEmpty {
            log("  MISSING types: \(missing.joined(separator: ", "))")
        }
        allTypes.add(NSString.self)
        allTypes.add(NSNumber.self)
        allTypes.add(NSData.self)
        allTypes.add(NSArray.self)
        allTypes.add(NSDictionary.self)
        allTypes.add(NSURL.self)
        allTypes.add(NSError.self)

        let classes = allTypes as! Set<AnyHashable>

        let selectors: [(Selector, Int, Bool)] = [
            (#selector(WallpaperXPCHandler.acquire(withId:request:reply:)), 0, false),
            (#selector(WallpaperXPCHandler.acquire(withId:request:reply:)), 1, false),
            (#selector(WallpaperXPCHandler.acquire(withId:request:reply:)), 0, true),
            (#selector(WallpaperXPCHandler.update(withId:request:reply:)), 0, false),
            (#selector(WallpaperXPCHandler.update(withId:request:reply:)), 1, false),
            (#selector(WallpaperXPCHandler.invalidate(withId:reply:)), 0, false),
            (#selector(WallpaperXPCHandler.snapshot(withId:reply:)), 0, false),
            (#selector(WallpaperXPCHandler.snapshot(withId:reply:)), 0, true),
            (#selector(WallpaperXPCHandler.provideSettingsViewModels(withContentTypes:reply:)), 0, false),
            (#selector(WallpaperXPCHandler.provideSettingsViewModels(withContentTypes:reply:)), 0, true),
            (#selector(WallpaperXPCHandler.addChoiceRequest(withChoiceRequest:onBehalfOfProcess:reply:)), 0, false),
            (#selector(WallpaperXPCHandler.addChoiceRequest(withChoiceRequest:onBehalfOfProcess:reply:)), 1, false),
            (#selector(WallpaperXPCHandler.addChoiceRequest(withChoiceRequest:onBehalfOfProcess:reply:)), 0, true),
            (#selector(WallpaperXPCHandler.removeChoiceRequest(withChoiceRequest:reply:)), 0, false),
            (#selector(WallpaperXPCHandler.selectedChoicesDidChange(for:reply:)), 0, false),
            (#selector(WallpaperXPCHandler.invokeContextMenuAction(withMenuItemID:groupItemID:reply:)), 0, false),
            (#selector(WallpaperXPCHandler.invokeContextMenuAction(withMenuItemID:groupItemID:reply:)), 1, false),
            (#selector(WallpaperXPCHandler.isChoiceDownloaded(with:reply:)), 0, false),
            (#selector(WallpaperXPCHandler.download(withChoiceID:reply:)), 0, false),
            (#selector(WallpaperXPCHandler.pauseDownload(for:reply:)), 0, false),
            (#selector(WallpaperXPCHandler.cancelDownload(for:reply:)), 0, false),
            (#selector(WallpaperXPCHandler.resumeDownload(for:reply:)), 0, false),
            (#selector(WallpaperXPCHandler.removeDownload(for:reply:)), 0, false),
            (#selector(WallpaperXPCHandler.migrateSelectedChoice(for:reply:)), 0, false),
            (#selector(WallpaperXPCHandler.migrateSelectedChoice(for:reply:)), 0, true),
            (#selector(WallpaperXPCHandler.migrate(from:to:reply:)), 0, false),
            (#selector(WallpaperXPCHandler.migrate(from:to:reply:)), 1, false),
            (#selector(WallpaperXPCHandler.skipShuffledContent(withId:reply:)), 0, false),
            (#selector(WallpaperXPCHandler.canSkipShuffledContent(withId:reply:)), 0, false),
            (#selector(WallpaperXPCHandler.handleDebugRequest(for:reply:)), 0, false),
            (#selector(WallpaperXPCHandler.handleDebugRequest(for:reply:)), 0, true),
            (#selector(WallpaperXPCHandler.handleNotification(withNamed:reply:)), 0, false),
        ]

        for (sel, idx, isReply) in selectors {
            exported.setClasses(classes, for: sel, argumentIndex: idx, ofReply: isReply)
        }

        connection.exportedInterface = exported
        connection.remoteObjectInterface = NSXPCInterface(with: (any WallpaperExtensionProxyXPCProtocol).self)

        let handler = WallpaperXPCHandler()
        handler.connectionPID = connection.processIdentifier
        connection.exportedObject = handler

        connection.interruptionHandler = { log("XPC interrupted") }
        connection.invalidationHandler = { [weak handler] in
            guard let handler else { return }
            log("XPC invalidated (pid: \(handler.connectionPID), served a method: \(handler.didServeMethod))")
        }

        handler.agentProxy = connection.remoteObjectProxy as? (any WallpaperExtensionProxyXPCProtocol)

        connection.resume()

        log("XPC accepted with full protocol")
        return true
    }
}
