import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: round-app-icon.swift input.png output.png")
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil),
      artwork.width == artwork.height else {
    fatalError("App icon source must be a square image")
}

let canvas = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue |
    CGImageAlphaInfo.premultipliedLast.rawValue
guard let context = CGContext(
    data: nil,
    width: canvas,
    height: canvas,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: bitmapInfo
) else {
    fatalError("Could not create app icon canvas")
}

// The source artwork stays untouched. The transparent margin makes this manual
// .icns match the apparent size of other rounded app icons in the Dock.
let iconBounds = CGRect(x: 96, y: 96, width: 832, height: 832)
let outline = CGPath(
    roundedRect: iconBounds,
    cornerWidth: 190,
    cornerHeight: 190,
    transform: nil
)
context.setShouldAntialias(true)
context.interpolationQuality = .high
context.addPath(outline)
context.clip()
context.draw(artwork, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))

guard let roundedIcon = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        output as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      ) else {
    fatalError("Could not create rounded app icon")
}
CGImageDestinationAddImage(destination, roundedIcon, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("Could not save rounded app icon")
}
