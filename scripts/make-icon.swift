import AppKit

let project = URL(fileURLWithPath: CommandLine.arguments[1])
let folder = project.appendingPathComponent("Resources/AppIcon.iconset")
let source = project.appendingPathComponent("Resources/IconSource/app-icon.png")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
guard let image = NSImage(contentsOf: source) else {
    fatalError("Unable to load icon source: \(source.path)")
}
let sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
for (size, scale) in sizes {
    let pixels = size * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
}
func bigEndian(_ value: Int) -> Data {
    var value = UInt32(value).bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
var elements = Data()
for (type, file) in [("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"), ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")] {
    let png = try Data(contentsOf: folder.appendingPathComponent(file))
    elements.append(Data(type.utf8)); elements.append(bigEndian(png.count + 8)); elements.append(png)
}
var icns = Data("icns".utf8); icns.append(bigEndian(elements.count + 8)); icns.append(elements)
try icns.write(to: project.appendingPathComponent("Resources/AppIcon.icns"))
