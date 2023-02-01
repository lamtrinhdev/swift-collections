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

extension _BString.Chunk {
  /// UTF-16 index lookup.
  func index(at utf8Offset: Int, utf16Delta: Int) -> String.Index {
    var index = string._utf8Index(at: utf8Offset)
    if
      utf16Delta != 0,
      index < string.endIndex,
      string.utf8[index]._isUTF8NonBMPLeadingCodeUnit
    {
      assert(utf16Delta == 1)
      index = string.utf16.index(after: index)
    }
    return index
  }
}
