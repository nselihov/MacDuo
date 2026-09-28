import AppKit
import CoreGraphics
import Foundation
import Metal

private struct FoldUniforms {
    var progress: Float
    var imageAnchor: Float
    var eyeDistance: Float
    var maxBlurLOD: Float
    var transitionWidth: Float
}

private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
    min(max(value, lower), upper)
}

private func sourceImage(width: Int, height: Int) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        let v = Double(y) / Double(height)
        for x in 0..<width {
            let u = Double(x) / Double(width)
            let ridge = 0.54 + 0.05 * sin(u * 10) + 0.025 * sin(u * 29)
            let dune = 0.76 + 0.08 * sin(u * 5 + 0.8)
            var red: Double
            var green: Double
            var blue: Double
            if v < ridge {
                red = 75 + 105 * v
                green = 125 + 65 * v
                blue = 190 + 35 * v
            } else if v < dune {
                red = 68 + 30 * u
                green = 65 + 24 * u
                blue = 65 + 17 * u
            } else {
                red = 185 + 25 * u
                green = 163 + 15 * u
                blue = 127 + 7 * u
            }
            // Fine grid lines and circular markers expose projection and blur.
            let gridX = x % 120 < 2
            let gridY = y % 120 < 2
            if gridX || gridY {
                red = red * 0.72 + 60
                green = green * 0.72 + 60
                blue = blue * 0.72 + 60
            }
            for (cx, cy, colour) in [
                (0.24, 0.34, (245.0, 83.0, 68.0)),
                (0.76, 0.34, (43.0, 210.0, 112.0)),
                (0.24, 0.77, (69.0, 121.0, 248.0)),
                (0.76, 0.77, (244.0, 89.0, 221.0)),
            ] {
                let dx = (u - cx) * Double(width) / 55
                let dy = (v - cy) * Double(height) / 55
                if dx * dx + dy * dy < 1 {
                    (red, green, blue) = colour
                }
            }
            let offset = (y * width + x) * 4
            pixels[offset] = UInt8(clamp(red, 0, 255))
            pixels[offset + 1] = UInt8(clamp(green, 0, 255))
            pixels[offset + 2] = UInt8(clamp(blue, 0, 255))
            pixels[offset + 3] = 255
        }
    }
    return pixels
}

private func writePNG(_ bytes: [UInt8], width: Int, height: Int, to url: URL) throws {
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        .union(.byteOrder32Big)
    let image = CGImage(width: width, height: height, bitsPerComponent: 8,
                        bitsPerPixel: 32, bytesPerRow: width * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo,
                        provider: provider, decode: nil, shouldInterpolate: true,
                        intent: .defaultIntent)!
    guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw NSError(domain: "DuoFoldPrototype", code: 1)
    }
    try png.write(to: url)
}

private func run() throws {
    guard CommandLine.arguments.count == 3 else {
        print("Usage: duo-fold-prototype DuoFold.metal output-directory")
        return
    }
    let shaderURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
    let width = 1200, height = 780
    let sourceBytes = sourceImage(width: width, height: height)
    try writePNG(sourceBytes, width: width, height: height,
                 to: outputURL.appendingPathComponent("source.png"))

    guard let device = MTLCreateSystemDefaultDevice(),
          let queue = device.makeCommandQueue() else {
        throw NSError(domain: "DuoFoldPrototype: Metal unavailable", code: 2)
    }
    let shader = try String(contentsOf: shaderURL, encoding: .utf8)
    let library = try device.makeLibrary(source: shader, options: nil)
    let function = library.makeFunction(name: "renderDuoFold")!
    let pipeline = try device.makeComputePipelineState(function: function)
    let sourceDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: true)
    sourceDescriptor.usage = [.shaderRead]
    sourceDescriptor.storageMode = .shared
    let source = device.makeTexture(descriptor: sourceDescriptor)!
    sourceBytes.withUnsafeBytes { pointer in
        source.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                       withBytes: pointer.baseAddress!, bytesPerRow: width * 4)
    }
    let mipCommand = queue.makeCommandBuffer()!
    let blit = mipCommand.makeBlitCommandEncoder()!
    blit.generateMipmaps(for: source)
    blit.endEncoding()
    mipCommand.commit()
    mipCommand.waitUntilCompleted()
    if let error = mipCommand.error { throw error }

    let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
    outputDescriptor.usage = [.shaderWrite]
    outputDescriptor.storageMode = .shared
    let output = device.makeTexture(descriptor: outputDescriptor)!

    for angle in [115.0, 80.0, 60.0, 40.0] {
        var uniforms = FoldUniforms(progress: Float(clamp((115 - angle) / 90, 0, 1)),
                                    imageAnchor: 0.55, eyeDistance: 3.1,
                                    maxBlurLOD: 8.0, transitionWidth: 1.0)
        let command = queue.makeCommandBuffer()!
        let encoder = command.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(output, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<FoldUniforms>.stride, index: 0)
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        var result = [UInt8](repeating: 0, count: width * height * 4)
        result.withUnsafeMutableBytes { pointer in
            output.getBytes(pointer.baseAddress!, bytesPerRow: width * 4,
                            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        let name = "fold-\(Int(angle)).png"
        try writePNG(result, width: width, height: height,
                     to: outputURL.appendingPathComponent(name))
        print(outputURL.appendingPathComponent(name).path)
    }
}

do { try run() }
catch {
    fputs("Duo fold prototype failed: \(error)\n", stderr)
    exit(1)
}
