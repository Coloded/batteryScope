#!/usr/bin/env swift
// macOS: swift scripts/prepare-screenshot.swift INPUT OUTPUT.png [--crop X Y WIDTH HEIGHT]
// Coordinates are pixels from the top-left of the correctly oriented image.
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8)); exit(1)
}
let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2 || (args.count == 7 && args[2] == "--crop") else {
    fail("Usage: swift scripts/prepare-screenshot.swift INPUT OUTPUT.png [--crop X Y WIDTH HEIGHT]")
}
let input = URL(fileURLWithPath: args[0]).standardizedFileURL
let output = URL(fileURLWithPath: args[1]).standardizedFileURL
guard input != output, output.pathExtension.lowercased() == "png" else { fail("Use a separate .png output file; originals are never replaced.") }
guard !FileManager.default.fileExists(atPath: output.path) else { fail("Output already exists: \(output.path). Choose another name.") }
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int else { fail("Cannot read input image.") }
let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(width, height)]
guard var image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { fail("Cannot decode input image.") }
if args.count == 7 {
    let numbers = args[3...6].compactMap(Int.init)
    guard numbers.count == 4 else { fail("Crop coordinates must be integers.") }
    let (x,y,w,h) = (numbers[0],numbers[1],numbers[2],numbers[3])
    guard x >= 0, y >= 0, w > 0, h > 0, x <= image.width, y <= image.height,
          w <= image.width-x, h <= image.height-y else { fail("Crop exceeds oriented image bounds: \(image.width)×\(image.height).") }
    guard let cropped = image.cropping(to: CGRect(x:x,y:y,width:w,height:h)) else { fail("Cannot crop image.") }
    image = cropped
}
// Normalize HDR/10-bit HEIC pixels to 8-bit sRGB supported by PNG encoders.
guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: image.width, height: image.height,
          bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("Cannot create RGB conversion buffer.") }
context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
guard let normalized = context.makeImage() else { fail("Cannot normalize image.") }
image = normalized
do { try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true) }
catch { fail(error.localizedDescription) }
guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else { fail("Cannot create output.") }
// Encode decoded pixels only; do not copy EXIF/GPS or camera metadata.
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fail("PNG encoding failed.") }
print("Saved \(output.lastPathComponent): \(image.width)×\(image.height)")
