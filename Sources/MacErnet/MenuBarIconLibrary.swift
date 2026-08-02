import AppKit

enum MenuBarIconLibrary {
    static func image(for style: MenuBarIconStyle, size: CGFloat = 18) -> NSImage? {
        guard let url = Bundle.main.url(
            forResource: style.resourceName,
            withExtension: "png",
            subdirectory: "MenuIcons"
        ), let source = NSImage(contentsOf: url), let image = source.copy() as? NSImage else {
            return nil
        }

        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        return image
    }
}
