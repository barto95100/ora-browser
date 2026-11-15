import AppKit

/// An Apple Event of `Ombre.sdef`: its command runs through `AgentControl`
/// (settings, the user's answer), the event waiting meanwhile.
class AgentScriptCommand: NSScriptCommand {
    /// The command this event asks for, none when its parameter is missing.
    var agentCommand: AgentCommand? {
        nil
    }

    var text: String? {
        directParameter as? String
    }

    override func performDefaultImplementation() -> Any? {
        guard let command = agentCommand else {
            scriptErrorNumber = Int(errAEParamMissed)
            scriptErrorString = "A tab id or an address is needed." // not shown
            return nil
        }
        let pid = appleEvent?.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value ?? 0
        let reply = ScriptReply(self)
        suspendExecution()
        Task { @MainActor in
            let sender = AgentSenderLookup.sender(pid: pid)
            await reply.send(AgentControl.shared.run(command, from: sender))
        }
        return nil
    }
}

/// Resumes a suspended command with its answer. Cocoa Scripting runs on the
/// main thread, where the answer is sent too.
private final class ScriptReply: @unchecked Sendable {
    private let command: NSScriptCommand

    init(_ command: NSScriptCommand) {
        self.command = command
    }

    @MainActor
    func send(_ result: Result<String, AgentError>) {
        switch result {
        case let .success(json):
            command.resumeExecution(withResult: json)
        case let .failure(error):
            command.scriptErrorNumber = errOSAGeneralError
            command.scriptErrorString = error.message
            command.resumeExecution(withResult: nil)
        }
    }
}

@objc(OmbreListTabsCommand)
final class ListTabsScriptCommand: AgentScriptCommand {
    override var agentCommand: AgentCommand? {
        .listTabs
    }
}

@objc(OmbreOpenAddressCommand)
final class OpenAddressScriptCommand: AgentScriptCommand {
    override var agentCommand: AgentCommand? {
        text.map { .open($0) }
    }
}

@objc(OmbreActivateTabCommand)
final class ActivateTabScriptCommand: AgentScriptCommand {
    override var agentCommand: AgentCommand? {
        text.map { .activate($0) }
    }
}

@objc(OmbreCloseTabCommand)
final class CloseTabScriptCommand: AgentScriptCommand {
    override var agentCommand: AgentCommand? {
        text.map { .close($0) }
    }
}

@objc(OmbreReadTabCommand)
final class ReadTabScriptCommand: AgentScriptCommand {
    override var agentCommand: AgentCommand? {
        .read(text)
    }
}
