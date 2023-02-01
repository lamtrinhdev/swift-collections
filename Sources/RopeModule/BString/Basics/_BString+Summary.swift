//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Collections open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

extension _BString {
  struct Summary {
    // FIXME: We only need 48 * 3 = 192 bits to represent a nonnegative value; pack these better
    // (Unfortunately we also need to represent negative values right now.)
    private(set) var characters: Int
    private(set) var unicodeScalars: Int
    private(set) var utf16: Int
    private(set) var utf8: Int

    init() {
      characters = 0
      unicodeScalars = 0
      utf16 = 0
      utf8 = 0
    }

    init(_ chunk: _BString.Chunk) {
      self.utf8 = chunk.utf8Count
      self.utf16 = Int(chunk.counts.utf16)
      self.unicodeScalars = Int(chunk.counts.unicodeScalars)
      self.characters = Int(chunk.counts.characters)
    }
  }
}

extension _BString.Summary: CustomStringConvertible {
  var description: String {
    "❨\(utf8)⋅\(utf16)⋅\(unicodeScalars)⋅\(characters)❩"
  }
}

extension _BString.Summary: _RopeSummary {
  @inline(__always)
  static var maxNodeSize: Int { 10 }

  @inline(__always)
  static var nodeSizeBitWidth: Int { 4 }

  @inline(__always)
  static var zero: Self { Self() }

  @inline(__always)
  var isZero: Bool { utf8 == 0 }

  mutating func add(_ other: _BString.Summary) {
    characters += other.characters
    unicodeScalars += other.unicodeScalars
    utf16 += other.utf16
    utf8 += other.utf8
  }

  mutating func subtract(_ other: _BString.Summary) {
    characters -= other.characters
    unicodeScalars -= other.unicodeScalars
    utf16 -= other.utf16
    utf8 -= other.utf8
  }
}
