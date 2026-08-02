import AppKit

@main
@MainActor
struct MacErnetApp {
    static func main() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        application.delegate = appDelegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
