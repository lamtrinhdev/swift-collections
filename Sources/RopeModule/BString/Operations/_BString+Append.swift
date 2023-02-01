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
  mutating func append(contentsOf other: __owned some StringProtocol) {
    append(contentsOf: Substring(other))
  }
  
  mutating func append(contentsOf other: __owned String) {
    append(contentsOf: other[...])
  }
  
  mutating func append(contentsOf other: __owned Substring) {
    if other.isEmpty { return }
    if isEmpty {
      self = Self(other)
      return
    }
    var ingester = ingester(forInserting: other, at: endIndex, allowForwardPeek: true).ingester
    
    let last = rope.index(before: rope.endIndex)
    if let final = rope[last].append(from: &ingester) {
      precondition(!final.isUndersized)
      rope.append(final)
      return
    }
    
    // Make a temp rope out of the rest of the chunks and then join the two trees together.
    if !ingester.isAtEnd {
      var builder = Rope.Builder()
      while let chunk = ingester.nextWellSizedChunk() {
        precondition(!chunk.isUndersized)
        builder.append(chunk)
      }
      precondition(ingester.isAtEnd)
      rope = Rope.join(rope, builder.finalize())
    }
  }
}

extension _BString {
  var _firstUnicodeScalar: Unicode.Scalar {
    assert(!isEmpty)
    return rope.root.firstItem.value.string.unicodeScalars.first!
  }

  mutating func append(contentsOf other: __owned _BString) {
    guard !other.isEmpty else { return }
    guard !self.isEmpty else {
      self = other
      return
    }

    let hint = other._firstUnicodeScalar
    var other = other.rope    
    var old = _CharacterRecognizer()
    var new = self._breakState(upTo: endIndex, nextScalarHint: hint).state
    _ = other.resyncBreaks(old: &old, new: &new)
    _append(other)
  }
  
  mutating func prepend(contentsOf other: __owned _BString) {
    guard !other.isEmpty else { return }
    guard !self.isEmpty else {
      self = other
      return
    }
    
    let hint = self._firstUnicodeScalar
    var old = _CharacterRecognizer()
    var new = other._breakState(upTo: other.endIndex, nextScalarHint: hint).state
    _ = self.rope.resyncBreaks(old: &old, new: &new)
    
    _prepend(other.rope)
  }
}

extension _BString {
  var isUndersized: Bool {
    utf8Count < Chunk.minUTF8Count
  }
}

extension _BString {
  /// Note: This assumes `other` already has the correct break positions.
  mutating func _append(_ other: __owned Chunk) {
    assert(!other.isEmpty)
    guard !self.isEmpty else {
      self.rope.append(other)
      return
    }
    guard self.isUndersized || other.isUndersized else {
      self.rope.append(other)
      return
    }
    var other = other
    let last = self.rope.index(before: self.rope.endIndex)
    if !self.rope[last].rebalance(nextNeighbor: &other) {
      assert(!other.isUndersized)
      self.rope.append(other)
    }
  }
  
  /// Note: This assumes `self` and `other` already have the correct break positions.
  mutating func _prepend(_ other: __owned Chunk) {
    assert(!other.isEmpty)
    guard !self.isEmpty else {
      self.rope.prepend(other)
      return
    }
    guard self.isUndersized || other.isUndersized else {
      self.rope.prepend(other)
      return
    }
    var other = other
    let first = self.rope.startIndex
    if !self.rope[first].rebalance(prevNeighbor: &other) {
      self.rope.prepend(other)
    }
  }
  
  /// Note: This assumes `other` already has the correct break positions.
  mutating func _append(_ other: __owned Rope) {
    guard !other.isEmpty else { return }
    guard !self.rope.isEmpty else {
      self.rope = other
      return
    }
    if other.isSingleton {
      self._append(other.first!)
      return
    }
    if self.isUndersized {
      assert(self.rope.isSingleton)
      let chunk = self.rope.first!
      self.rope = other
      self._prepend(chunk)
      return
    }
    self.rope = Rope.join(self.rope, other)
  }
  
  /// Note: This assumes `self` and `other` already have the correct break positions.
  mutating func _prepend(_ other: __owned Rope) {
    guard !other.isEmpty else { return }
    guard !self.isEmpty else {
      self.rope = other
      return
    }
    if other.isSingleton {
      self._prepend(other.first!)
      return
    }
    if self.isUndersized {
      assert(self.rope.isSingleton)
      let chunk = self.rope.first!
      self.rope = other
      self._append(chunk)
      return
    }
    self.rope = Rope.join(other, self.rope)
  }
}
