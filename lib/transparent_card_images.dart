import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// "Removes" white background by adding as much transparency as possible while
// keeping the same result when drawing the image on top of solid white.
// Solid white becomes fully transparent, solid black is unchanged.
// This is a port of scripts/make_transparent_cards.py.
// Examples (rgba components in [0,1]):
//   red=1, green=0.5, blue=0.5 => red=1, green=0, blue=0, alpha=0.5
//   red=1, green=0.5, blue=0.25 => red=1, green=1/3, blue=0, alpha=0.75
//   red=1, green=1, blue=1 => alpha=0, rgb=<anything>
img.Image makeTransparentCardImage(img.Image src) {
  final srcBytes = src
      .convert(format: img.Format.uint8, numChannels: 4)
      .getBytes(order: img.ChannelOrder.rgba);
  final dstBytes = Uint8List(src.width * src.height * 4);
  for (int i = 0; i < dstBytes.length; i += 4) {
    final red = srcBytes[i];
    final green = srcBytes[i + 1];
    final blue = srcBytes[i + 2];
    final alpha = srcBytes[i + 3];
    // If the pixel is already fully transparent, don't modify.
    if (alpha == 0) {
      dstBytes.setRange(i, i + 4, srcBytes, i);
      continue;
    }
    // Take RGB inverses and normalize to [0, 1]
    final rneg = 1 - red / 255;
    final gneg = 1 - green / 255;
    final bneg = 1 - blue / 255;
    // Alpha is the maximum inverse value.
    final af = max(rneg, max(gneg, bneg));
    if (af == 0) {
      dstBytes[i + 3] = 1;
      continue;
    }
    // The component with maximum inverse will have an output inverse
    // component of 1, so that when it's blended with white
    // (whose inverse is 0), the result will be the original input.
    dstBytes[i] = (255 * (1 - rneg / af)).round();
    dstBytes[i + 1] = (255 * (1 - gneg / af)).round();
    dstBytes[i + 2] = (255 * (1 - bneg / af)).round();
    dstBytes[i + 3] = (255 * af).round();
  }
  return img.Image.fromBytes(
      width: src.width, height: src.height, bytes: dstBytes.buffer,
      numChannels: 4, order: img.ChannelOrder.rgba);
}
