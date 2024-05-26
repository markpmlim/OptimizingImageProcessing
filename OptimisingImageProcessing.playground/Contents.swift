/*
 Article - Optimizing Image Processing Performance
 Improve your app's performance by converting image buffer formats
 from interleaved to planar.
 
 Requires macOS 10.15 or later.
 */

#if os(iOS)
import UIKit
#else
import AppKit
#endif
import ImageIO
import Accelerate.vImage

let url = Bundle.main.url(forResource: "Flowers_1",
                          withExtension: "png")
let options = [kCGImageSourceShouldCache : true] as CFDictionary

let cgImageSource = CGImageSourceCreateWithURL(url! as CFURL,
                                               options)

guard let cgImage = CGImageSourceCreateImageAtIndex(cgImageSource!, 0, options)
else {
    fatalError("Can't create the CGImage object")
}

// Check if the following properties of this instance of CGImage
print(String(format:"0x%04X", cgImage.bitmapInfo.rawValue))
print(String(format:"0x%04X", cgImage.alphaInfo.rawValue))
print(String(format:"0x%04X", cgImage.byteOrderInfo.rawValue))

// Initialize an Image Format and vImage Buffers
// bitmapInfo: order32Little+last --> non-premultiplied ARGB
let bitmapInfo = CGBitmapInfo(rawValue:
        CGImageAlphaInfo.last.rawValue |
        CGImageByteOrderInfo.order32Little.rawValue)

var cgImageFormat = vImage_CGImageFormat(
    bitsPerComponent: 8,
    bitsPerPixel: 32,
    colorSpace: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: bitmapInfo,
    renderingIntent: .defaultIntent)!

// 0x2003 (8195) byteOrder32Little+last --> non-premultiplied ARGB
print(String(format:"0x%04X", cgImageFormat.bitmapInfo.rawValue))

guard var sourceBuffer = try? vImage_Buffer(cgImage: cgImage,
                                            format: cgImageFormat)
else {
    fatalError("Can't create the source buffer")
}

// Check
let cgImage2 = try sourceBuffer.createCGImage(format: cgImageFormat)
print("cgImage2")
print(String(format:"0x%04X", cgImage2.bitmapInfo.rawValue))
print(String(format:"0x%04X", cgImage2.alphaInfo.rawValue))
print(String(format:"0x%04X", cgImage2.byteOrderInfo.rawValue))

// Debugging
var bytePtr = sourceBuffer.data.assumingMemoryBound(to: UInt8.self)
for i in 0 ..< 2 * cgImageFormat.componentCount {
    print(bytePtr[i], terminator: " ")
}
print()

/*
 The lookup table is used to map the range 0…255 to the values [0, 75, 150, 225, 255]
    quantizationLevel = 75
 */
var lookUpTable = (0...255).map {
    return Pixel_8(($0 / 75) * 75)
}

let componentCount = cgImageFormat.componentCount

var argbSourcePlanarBuffers: [vImage_Buffer] = (0 ..< componentCount).map {
    _ in
    guard let buffer = try? vImage_Buffer(
        width: Int(sourceBuffer.width),
        height: Int(sourceBuffer.height),
        bitsPerPixel: cgImageFormat.bitsPerComponent)  // 8
    else {
        fatalError("Error creating source buffers.")
    }

    return buffer
}

var error = vImage_Error(kvImageNoError)

error = vImageConvert_ARGB8888toPlanar8(
    &sourceBuffer,
    &argbSourcePlanarBuffers[0],
    &argbSourcePlanarBuffers[1],
    &argbSourcePlanarBuffers[2],
    &argbSourcePlanarBuffers[3],
    vImage_Flags(kvImageNoFlags))

// Create the destination buffers
var argbDestinationPlanarBuffers: [vImage_Buffer] = (0 ..< componentCount).map {
    _ in
    guard let buffer = try? vImage_Buffer(
        width: Int(sourceBuffer.width),
        height: Int(sourceBuffer.height),
        bitsPerPixel: cgImageFormat.bitsPerComponent)
    else {
        fatalError("Error creating destination buffers.")
    }

    return buffer
}

var alphaIndex: Int?

/* Always false!!!!
let littleEndian  = cgImage2.byteOrderInfo == .order16Little ||
                    cgImage2.byteOrderInfo == .order32Little
*/

// The CGImageByteOrderInfo of cgImage and cgImage2 is always .orderDefault (which is 0)
// Instead of using the CGImages' byteOrderInfo, we use the vImage_CGImageFormat object's
// bitmapInfo property.
let byteOrderInfo = CGImageByteOrderInfo(rawValue:
    (cgImageFormat.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue))

let littleEndian = byteOrderInfo == .order16Little || byteOrderInfo == .order32Little

let alphaInfo = CGImageAlphaInfo(rawValue:
    (cgImageFormat.bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue))

switch alphaInfo {
case .first, .noneSkipFirst, .premultipliedFirst:
    alphaIndex = littleEndian ? componentCount - 1 : 0
case .last, .noneSkipLast, .premultipliedLast:
    alphaIndex = littleEndian ? 0 : componentCount - 1
default:
    alphaIndex = nil
}

// Bug: pixelSize must be 1 not Int(format.bitsPerPixel) / 8 which is 4
// vImage_Buffer(data: Optional(0x00007f80e9849000), height: 768, width: 1024, rowBytes: 1024)
if let alphaIndex = alphaIndex {
    do {
        try argbSourcePlanarBuffers[alphaIndex].copy(
            destinationBuffer: &argbDestinationPlanarBuffers[alphaIndex],
            pixelSize: 1)
    }
    catch {
        fatalError("Error copying alpha buffer: \(error.localizedDescription).")
    }
}

// Apply the Lookup Table to the Planar Buffers
for index in 0 ..< componentCount where index != alphaIndex {
    print(index, alphaIndex!)       // Debugging statement
    vImageTableLookUp_Planar8(&argbSourcePlanarBuffers[index],
                              &argbDestinationPlanarBuffers[index],
                              &lookUpTable,
                              vImage_Flags(kvImageNoFlags))
}

// Convert the Planar Buffers Back to an Interleaved Buffer
guard var destinationBuffer = try? vImage_Buffer(
    width: Int(sourceBuffer.width),
    height: Int(sourceBuffer.height),
    bitsPerPixel: cgImageFormat.bitsPerPixel)      // 32
else {
    fatalError("Error creating destination buffers.")
}

// The function below interleaves the four planar buffers, writing the results
// to the destination buffer.
error = vImageConvert_Planar8toARGB8888(
    &argbDestinationPlanarBuffers[0],
    &argbDestinationPlanarBuffers[1],
    &argbDestinationPlanarBuffers[2],
    &argbDestinationPlanarBuffers[3],
    &destinationBuffer,
    vImage_Flags(kvImageNoFlags))

/* Debugging:
for i in 0 ..< argbDestinationPlanarBuffers.count {
    let buffer = argbDestinationPlanarBuffers[i]
    let bytePtr = buffer.data.assumingMemoryBound(to: UInt8.self)
    for j in 0 ..< 2 * componentCount {
        print(bytePtr[j], terminator: " ")
    }
    print()
}
*/

let cgImage3 = try destinationBuffer.createCGImage(
    format: cgImageFormat,
    flags: vImage.Options.printDiagnosticsToConsole)

sourceBuffer.free()
destinationBuffer.free()
for buffer in argbSourcePlanarBuffers {
    buffer.free()
}

for buffer in argbDestinationPlanarBuffers {
    buffer.free()
}
