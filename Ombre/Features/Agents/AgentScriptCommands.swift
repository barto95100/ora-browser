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

    /// The `in tab` parameter: none for the active tab.
    var tab: String? {
        evaluatedArguments?["tab"] as? String
    }

    override func performDefaultImplementation() -> Any? {
        guard let command = agentCommand else {
            scriptErrorNumber = Int(errAEParamMissed)
            scriptErrorString = "A parameter is missing." // not shown
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
            command.scriptErrorString = error.reply
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

@objc(OmbreCaptureTabCommand)
final class CaptureTabScriptCommand: AgentScriptCommand {
    override var agentCommand: AgentCommand? {
        .capture(text)
    }
}

@objc(OmbreClickElementCommand)
final class ClickElementScriptCommand: AgentScriptCommand {
    override var agentCommand: AgentCommand? {
        text.map { .click(tab: tab, selector: $0) }
    }
}

@objc(OmbreFillFieldCommand)
final class FillFieldScriptCommand: AgentScriptCommand {
    override var agentCommand: AgentCommand? {
        guard let selector = text, let value = evaluatedArguments?["value"] as? String else { return nil }
        return .fill(tab: tab, selector: selector, value: value)
    }
}

@objc(OmbreRunJavaScriptCommand)
final class RunJavaScriptScriptCommand: AgentScriptCommand {
    override var agentCommand: AgentCommand? {
        text.map { .runScript(tab: tab, code: $0) }
    }
}
