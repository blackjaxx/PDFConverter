import Foundation

enum ToolsBootstrap {
    /// `PDFConverter.app/Contents/Resources/tools`
    static func toolsRootURL() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let tools = resourceURL.appendingPathComponent("tools", isDirectory: true)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: tools.path, isDirectory: &isDir), isDir.boolValue {
            return tools
        }
        return nil
    }
}
