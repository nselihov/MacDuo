import AppKit
import ObjectiveC
import QuartzCore

/// Runtime adapter for the private CAMeshTransform ABI. It operates only on
/// a layer owned by this process; no screen pixels or foreign layers are read.
public enum BackdropMesh {
    public struct Point {
        public let source: CGPoint
        public let destination: CGPoint
        public init(source: CGPoint, destination: CGPoint) {
            self.source = source; self.destination = destination
        }
    }
    private struct Vertex {
        var source: CGPoint
        var x: CGFloat
        var y: CGFloat
        var z: CGFloat = 0
    }
    private struct Face {
        var a: UInt32; var b: UInt32; var c: UInt32; var d: UInt32
        var wa: Float = 0; var wb: Float = 0; var wc: Float = 0; var wd: Float = 0
    }

    public static func make(columns: Int, rows: Int, points: [Point]) -> NSObject? {
        guard columns > 0, rows > 0, points.count == (columns + 1) * (rows + 1),
              let type = NSClassFromString("CAMutableMeshTransform") else { return nil }
        let selector = NSSelectorFromString("meshTransformWithVertexCount:vertices:faceCount:faces:depthNormalization:")
        guard let method = class_getClassMethod(type, selector) else { return nil }
        typealias Make = @convention(c) (AnyClass, Selector, UInt, UnsafeRawPointer, UInt, UnsafeRawPointer, NSString) -> Unmanaged<NSObject>?
        let make = unsafeBitCast(method_getImplementation(method), to: Make.self)
        let vertices = points.map { Vertex(source: $0.source, x: $0.destination.x, y: $0.destination.y) }
        var faces: [Face] = []
        for row in 0..<rows {
            for col in 0..<columns {
                let a = UInt32(row * (columns + 1) + col), b = a + 1
                let d = a + UInt32(columns + 1), c = d + 1
                faces.append(Face(a: a, b: b, c: c, d: d))
            }
        }
        let mesh = vertices.withUnsafeBytes { v in
            faces.withUnsafeBytes { f in
                make(type, selector, UInt(vertices.count), v.baseAddress!, UInt(faces.count), f.baseAddress!, "none")?.takeUnretainedValue()
            }
        }
        mesh?.setValue(0, forKey: "subdivisionSteps")
        return mesh
    }
}
