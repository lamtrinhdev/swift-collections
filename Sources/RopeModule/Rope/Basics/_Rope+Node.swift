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

extension _Rope {
  struct Node: _RopeItem {
    typealias Element = _Rope.Element
    typealias Summary = _Rope.Summary
    typealias Index = _Rope.Index
    typealias Item = _Rope.Item
    typealias Storage = _Rope.Storage
    typealias UnsafeHandle = _Rope.UnsafeHandle
    
    var object: AnyObject
    var summary: Summary
    
    init(leaf: Storage<Item>, summary: Summary? = nil) {
      self.object = leaf
      self.summary = .zero
      self.summary = readLeaf { handle in
        handle.children.reduce(into: .zero) { $0.add($1.summary) }
      }
    }
    
    init(inner: Storage<Node>, summary: Summary? = nil) {
      assert(inner.header.height > 0)
      self.object = inner
      self.summary = .zero
      self.summary = readInner { handle in
        handle.children.reduce(into: .zero) { $0.add($1.summary) }
      }
    }
  }
}

extension _Rope.Node {
  var _headerPtr: UnsafePointer<_RopeStorageHeader> {
    let p = _getUnsafePointerToStoredProperties(object)
      .assumingMemoryBound(to: _RopeStorageHeader.self)
    return .init(p)
  }
  
  var header: _RopeStorageHeader {
    _headerPtr.pointee
  }
  
  @inline(__always)
  var height: UInt8 { header.height }
  
  @inline(__always)
  var isLeaf: Bool { height == 0 }
  
  @inline(__always)
  var asLeaf: Storage<Item> {
    assert(height == 0)
    return unsafeDowncast(object, to: Storage<Item>.self)
  }
  
  @inline(__always)
  var asInner: Storage<Self> {
    assert(height > 0)
    return unsafeDowncast(object, to: Storage<Self>.self)
  }
  
  @inline(__always)
  var childCount: Int { header.childCount }
  
  var isEmpty: Bool { childCount == 0 }
  var isSingleton: Bool { isLeaf && childCount == 1 }
  var isUndersized: Bool { childCount < Summary.minNodeSize }
  var isFull: Bool { childCount == Summary.maxNodeSize }
}

extension _Rope.Node {
  static func createLeaf() -> Self {
    Self(leaf: .create(height: 0), summary: Summary.zero)
  }
  
  static func createLeaf(_ item: __owned Item) -> Self {
    var leaf = createLeaf()
    leaf._appendItem(item)
    return leaf
  }
  
  static func createInner(height: UInt8) -> Self {
    Self(inner: .create(height: height), summary: .zero)
  }
  
  static func createInner(children left: __owned Self, _ right: __owned Self) -> Self {
    assert(left.height == right.height)
    var new = createInner(height: left.height + 1)
    new.summary = left.summary
    new.summary.add(right.summary)
    new.updateInner { h in
      h._appendChild(left)
      h._appendChild(right)
    }
    return new
  }
}

extension _Rope.Node {
  @inline(__always)
  mutating func isUnique() -> Bool {
    isKnownUniquelyReferenced(&object)
  }
  
  mutating func ensureUnique() {
    guard !isKnownUniquelyReferenced(&object) else { return }
    self = copy()
  }

  @inline(never)
  func copy() -> Self {
    if isLeaf {
      return Self(leaf: readLeaf { $0.copy() }, summary: self.summary)
    }
    return Self(inner: readInner { $0.copy() }, summary: self.summary)
  }

  @inline(never)
  func copy(slots: Range<Int>) -> Self {
    if isLeaf {
      let (object, summary) = readLeaf { $0.copy(slots: slots) }
      return Self(leaf: object, summary: summary)
    }
    let (object, summary) = readInner { $0.copy(slots: slots) }
    return Self(inner: object, summary: summary)
  }

  @inline(__always)
  func readLeaf<R>(
    _ body: (UnsafeHandle<Item>) -> R
  ) -> R {
    asLeaf.withUnsafeMutablePointers { h, p in
      let handle = UnsafeHandle(isMutable: false, header: h, start: p)
      return body(handle)
    }
  }
  
  @inline(__always)
  mutating func updateLeaf<R>(
    _ body: (UnsafeHandle<Item>) -> R
  ) -> R {
    asLeaf.withUnsafeMutablePointers { h, p in
      let handle = UnsafeHandle(isMutable: true, header: h, start: p)
      return body(handle)
    }
  }
  
  @inline(__always)
  func readInner<R>(
    _ body: (UnsafeHandle<Self>) -> R
  ) -> R {
    asInner.withUnsafeMutablePointers { h, p in
      let handle = UnsafeHandle(isMutable: false, header: h, start: p)
      return body(handle)
    }
  }
  
  @inline(__always)
  mutating func updateInner<R>(
    _ body: (UnsafeHandle<Self>) -> R
  ) -> R {
    asInner.withUnsafeMutablePointers { h, p in
      let handle = UnsafeHandle(isMutable: true, header: h, start: p)
      return body(handle)
    }
  }
}

extension _Rope.Node {
  mutating func _insertItem(_ item: __owned Item, at slot: Int) {
    assert(isLeaf)
    ensureUnique()
    self.summary.add(item.summary)
    updateLeaf { $0._insertChild(item, at: slot) }
  }
  
  mutating func _insertNode(_ node: __owned Self, at slot: Int) {
    assert(!isLeaf)
    assert(self.height == node.height + 1)
    ensureUnique()
    self.summary.add(node.summary)
    updateInner { $0._insertChild(node, at: slot) }
  }
}

extension _Rope.Node {
  mutating func _appendItem(_ item: __owned Item) {
    assert(isLeaf)
    ensureUnique()
    self.summary.add(item.summary)
    updateLeaf { $0._appendChild(item) }
  }
  
  mutating func _appendNode(_ node: __owned Self) {
    assert(!isLeaf)
    ensureUnique()
    self.summary.add(node.summary)
    updateInner { $0._appendChild(node) }
  }
}

extension _Rope.Node {
  mutating func _removeItem(at slot: Int) -> (removed: Item, delta: Summary) {
    assert(isLeaf)
    ensureUnique()
    let item = updateLeaf { $0._removeChild(at: slot) }
    let delta = item.summary
    self.summary.subtract(delta)
    return (item, delta)
  }
  
  mutating func _removeNode(at slot: Int) -> Self {
    assert(!isLeaf)
    ensureUnique()
    let result = updateInner { $0._removeChild(at: slot) }
    self.summary.subtract(result.summary)
    return result
  }
}

extension _Rope.Node {
  mutating func split(keeping desiredCount: Int) -> Self {
    assert(desiredCount >= 0 && desiredCount <= childCount)
    var new = isLeaf ? Self.createLeaf() : Self.createInner(height: height)
    guard desiredCount < childCount else { return new }
    guard desiredCount > 0 else {
      swap(&self, &new)
      return new
    }
    ensureUnique()
    new.prependChildren(movingFromSuffixOf: &self, count: childCount - desiredCount)
    assert(childCount == desiredCount)
    return new
  }
}

extension _Rope.Node {
  mutating func rebalance(nextNeighbor right: inout _Rope<Element>.Node) -> Bool {
    assert(self.height == right.height)
    if self.isEmpty {
      swap(&self, &right)
      return true
    }
    guard self.isUndersized || right.isUndersized else { return false }
    let c = self.childCount + right.childCount
    let desired = (
      c <= Summary.maxNodeSize ? c
      : c / 2 >= Summary.minNodeSize ? c / 2
      : Summary.minNodeSize
    )
    Self.redistributeChildren(&self, &right, to: desired)
    return right.isEmpty
  }
  
  mutating func rebalance(prevNeighbor left: inout Self) -> Bool {
    guard left.rebalance(nextNeighbor: &self) else { return false }
    swap(&self, &left)
    return true
  }
  
  /// Shift children between `left` and `right` such that the number of children in `left`
  /// becomes `target`.
  internal static func redistributeChildren(
    _ left: inout Self,
    _ right: inout Self,
    to target: Int
  ) {
    assert(left.height == right.height)
    assert(target >= 0 && target <= Summary.maxNodeSize)
    left.ensureUnique()
    right.ensureUnique()
    
    let lc = left.childCount
    let rc = right.childCount
    let target = Swift.min(target, lc + rc)
    let d = target - lc
    if d == 0 { return }
    
    if d > 0 {
      left.appendChildren(movingFromPrefixOf: &right, count: d)
    } else {
      right.prependChildren(movingFromSuffixOf: &left, count: -d)
    }
  }
  
  mutating func appendChildren(movingFromPrefixOf other: inout Self, count: Int) {
    assert(self.height == other.height)
    let delta: Summary
    if isLeaf {
      delta = self.updateLeaf { dst in
        other.updateLeaf { src in
          dst._appendChildren(movingFromPrefixOf: src, count: count)
        }
      }
    } else {
      delta = self.updateInner { dst in
        other.updateInner { src in
          dst._appendChildren(movingFromPrefixOf: src, count: count)
        }
      }
    }
    self.summary.add(delta)
    other.summary.subtract(delta)
  }
  
  mutating func prependChildren(movingFromSuffixOf other: inout Self, count: Int) {
    assert(self.height == other.height)
    let delta: Summary
    if isLeaf {
      delta = self.updateLeaf { dst in
        other.updateLeaf { src in
          dst._prependChildren(movingFromSuffixOf: src, count: count)
        }
      }
    } else {
      delta = self.updateInner { dst in
        other.updateInner { src in
          dst._prependChildren(movingFromSuffixOf: src, count: count)
        }
      }
    }
    self.summary.add(delta)
    other.summary.subtract(delta)
  }
}

extension _Rope.Node {
  var startIndex: Index {
    var i = Index(height: self.height)
    descendToFirstItem(under: &i)
    return i
  }
  
  var lastIndex: Index {
    var i = Index(height: self.height)
    descendToLastItem(under: &i)
    return i
  }
  
  func isAtEnd(_ i: Index) -> Bool {
    i[height: self.height] == childCount
  }
  
  func descendToFirstItem(under i: inout Index) {
    i.clear(below: self.height + 1)
  }
  
  func descendToLastItem(under i: inout Index) {
    let h = self.height
    let slot = self.childCount - 1
    i[height: h] = slot
    if h > 0 {
      readInner { $0.children[slot].descendToLastItem(under: &i) }
    }
  }
  
  func formSuccessor(of i: inout Index) -> Bool {
    let h = self.height
    var slot = i[height: h]
    if h == 0 {
      slot += 1
      guard slot < childCount else { return false }
      i[height: h] = slot
      return true
    }
    let success = readInner { $0.children[slot].formSuccessor(of: &i) }
    if success { return true }
    slot += 1
    guard slot < childCount else { return false }
    i[height: h] = slot
    i.clear(below: h)
    return true
  }
  
  func formPredecessor(of i: inout Index) -> Bool {
    let h = self.height
    var slot = i[height: h]
    if h == 0 {
      guard slot > 0 else { return false }
      i[height: h] = slot - 1
      return true
    }
    return readInner {
      let c = $0.children
      if slot < c.count, c[slot].formPredecessor(of: &i) {
        return true
      }
      guard slot > 0 else { return false }
      slot -= 1
      i[height: h] = slot
      c[slot].descendToLastItem(under: &i)
      return true
    }
  }
  
  var lastItem: Item {
    get {
      self[lastIndex]
    }
    _modify {
      assert(childCount > 0)
      var state = _prepareModifyLast()
      defer {
        _ = _finalizeModify(&state)
      }
      yield &state.value
    }
  }
  
  var firstItem: Item {
    get {
      self[startIndex]
    }
    _modify {
      yield &self[startIndex]
    }
  }
  
  subscript(i: Index) -> Item {
    get {
      let h = height
      let slot = i[height: h]
      precondition(slot < childCount, "Index out of bounds")
      guard h == 0 else {
        return readInner { $0.children[slot][i] }
      }
      return readLeaf { $0.children[slot] }
    }
    @inline(__always)
    _modify {
      var state = _prepareModify(at: i)
      defer {
        _ = _finalizeModify(&state)
      }
      yield &state.value
    }
  }
  
  struct ModifyState {
    var index: Index
    var value: Item
    var summary: Summary
  }
  
  mutating func _prepareModify(at i: Index) -> ModifyState {
    ensureUnique()
    let h = height
    let slot = i[height: h]
    precondition(slot < childCount, "Index out of bounds")
    guard h == 0 else {
      return updateInner { $0.mutableChildren[slot]._prepareModify(at: i) }
    }
    let value = updateLeaf { $0.mutableChildren.moveElement(from: slot) }
    return ModifyState(index: i, value: value, summary: value.summary)
  }
  
  mutating func _prepareModifyLast() -> ModifyState {
    var i = Index(height: height)
    return _prepareModifyLast(&i)
  }
  
  mutating func _prepareModifyLast(_ i: inout Index) -> ModifyState {
    ensureUnique()
    let h = height
    let slot = self.childCount - 1
    i[height: h] = slot
    guard h == 0 else {
      return updateInner { $0.mutableChildren[slot]._prepareModifyLast(&i) }
    }
    let value = updateLeaf { $0.mutableChildren.moveElement(from: slot) }
    return ModifyState(index: i, value: value, summary: value.summary)
  }
  
  mutating func _finalizeModify(_ state: inout ModifyState) -> Summary {
    assert(isUnique())
    let h = height
    let slot = state.index[height: h]
    assert(slot < childCount, "Index out of bounds")
    guard h == 0 else {
      let delta = updateInner { $0.mutableChildren[slot]._finalizeModify(&state) }
      summary.add(delta)
      return delta
    }
    let delta = state.value.summary.subtracting(state.summary)
    updateLeaf { $0.mutableChildren.initializeElement(at: slot, to: state.value) }
    summary.add(delta)
    return delta
  }
}
