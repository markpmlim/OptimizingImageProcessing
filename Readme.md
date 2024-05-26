## Optimizing Image Processing Performance

This Swift playground is adapted from Apple's article "Optimizing Image Processing Performance". The  .rtfd is a copy of the program's documentation distributed with XCode 11.6.

There are 2 problems encountered. The following statement always returns **false** irrespective of whether the interleaved pixels is ARGB or RGBA.

<br />

**First Problem:**

```swift
    let littleEndian  = cgImage.byteOrderInfo == .order16Little ||
                        cgImage.byteOrderInfo == .order32Little
```

To ensure that the flag *littleEndian* returns true when the playground is executed on a LE device, two steps are taken.

a) The vImage_CGImageFormat, *cgImageFormat* is created with the following bitmapInfo:

```swift
    let bitmapInfo = CGBitmapInfo(rawValue:
        CGImageAlphaInfo.last.rawValue |
        CGImageByteOrderInfo.order32Little.rawValue)
```

This ensures the colour components of the pixels of the source vImage_Buffer, *sourceBuffer* are in ARGB order. 

b) It seems the system tags the *byteOrderInfo* of CGImage objects with a raw value of 0 (which is *.orderDefault*).

```swift
    let cgImage2 = try sourceBuffer.createCGImage(format: cgImageFormat)
    // non-premultiplied ARGB
    print(cgImage2.bitmapInfo.rawValue)     // 3 and not 0x2003
    print(cgImage2.alphaInfo.rawValue)      // 3 --> last
    print(cgImage2.byteOrderInfo.rawValue)  // 0 not 0x2000
```

As noted above, the statement below will always return *false* since the *byteOrderInfo* of CGImage objects have a raw value of 0.
```swift
    let littleEndian  = cgImage.byteOrderInfo == .order16Little ||
                        cgImage.byteOrderInfo == .order32Little
```
Using the 3 statements below, solved the problem:

```swift
    let byteOrderInfo = CGImageByteOrderInfo(rawValue:
        (cgImageFormat.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue))

    let littleEndian = byteOrderInfo == .order16Little || byteOrderInfo == .order32Little

    let alphaInfo = CGImageAlphaInfo(rawValue:
        (cgImageFormat.bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue))
```

BTW, the other 3 combinations  to create *cgImageFormat* viz. first+order32Little, last+order32Big and first+order32Big, should work the rest of the code.

<br />

**Second Problem:**

```swift
    if let alphaIndex = alphaIndex {
    do {
        try argbSourcePlanarBuffers[alphaIndex].copy(
            destinationBuffer: &argbDestinationPlanarBuffers[alphaIndex],
            pixelSize:  Int(format.bitsPerPixel) / 8)
    }
    catch {
        fatalError("Error copying alpha buffer: \(error.localizedDescription).")
    }
}
```
The playground will crash when the code is executed. The *pixelSize* paramter should be 1.

Printing one of the planar buffers (source or destination) will display a line similar to the one below:

    vImage_Buffer(data: Optional(0x00007f80e9849000), height: 768, width: 1024, rowBytes: 1024)

The *width* and *rowBytes* properties are both equal. If the *pixelSize* is 4, then the *rowBytes* property should be 4096.
<br />

## Development Plaftorm
<br />

XCode 11.6, Swift 5.0
<br />
<br />
**System Requirements:**

macOS 10.15.x or later
