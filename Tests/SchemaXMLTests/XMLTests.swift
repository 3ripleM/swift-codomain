import Foundation
import Schema
import Testing
import XMLCoder

extension XMLDecoder: DataDecoder {}

enum XF: Error, Equatable { case blank, odd }

@Codec
struct Name: Equatable {
    static let codec: Codec<String, String, XF> = Codec(
        decode: .identity.trimmed().nonEmpty(.blank), encode: { $0 })
}

@Codec
struct Count: Equatable {
    static let codec: Codec<Int, Int, XF> = Codec(
        decode: .identity.refine(.odd) { $0 % 2 == 0 }, encode: { $0 })
}

@JSONSchema(failure: XF.self)
struct Item: Equatable {
    let name: Name
    let count: Count
}

@JSONSchema(failure: XF.self)
struct Order: Equatable {
    let id: Name
    let first: Item
    let item: [Item]
}

@JSONSchema(failure: XF.self, strict: true)
struct StrictItem: Equatable {
    let name: Name
    let count: Count
}

@JSONSchema(failure: XF.self, strict: true)
struct Tagged: Equatable {
    let id: Name
    let name: Name
}

private func decode<T: JSONParsable>(_: T.Type, _ text: String) -> Result<T, DecodeFailure<XF>>
where T.Failure == XF {
    T.decode(Data(text.utf8), using: XMLDecoder())
}

private func problems<T: JSONParsable>(_: T.Type, _ text: String) -> String where T.Failure == XF {
    guard case .failure(.invalid(let issues)) = decode(T.self, text) else { return "no problems" }
    return issues.description
}

// 1. Nested elements and arrays

@Test func nestedElementsAndRepeatedElementsDecode() throws {
    let order = try decode(
        Order.self,
        """
        <order><id>A</id><first><name>x</name><count>2</count></first>
        <item><name>a</name><count>2</count></item><item><name>b</name><count>4</count></item></order>
        """
    ).get()
    #expect(order.first == Item(name: .unsafeMk("x"), count: .unsafeMk(2)))
    #expect(order.item.map(\.name.value) == ["a", "b"])
}

@Test func problemsInNestedAndRepeatedElementsKeepTheirPaths() {
    #expect(
        problems(
            Order.self,
            """
            <order><id> </id><first><name>x</name><count>3</count></first>
            <item><name>a</name><count>2</count></item><item><name> </name><count>5</count></item></order>
            """) == "id: blank, first.count: odd, item[1].name: blank, item[1].count: odd")
}

// 2. Missing elements

@Test func anAbsentElementIsMissing() {
    #expect(
        problems(
            Order.self,
            "<order><first><name>x</name></first><item><name>a</name><count>2</count></item></order>"
        )
            == "id: missing, first.count: missing")
}

@Test func anAbsentRepeatedElementIsAnEmptyArray() throws {
    let order = try decode(
        Order.self, "<order><id>A</id><first><name>x</name><count>2</count></first></order>"
    ).get()
    #expect(order.item == [])
}

@Test func aSelfClosingRepeatedElementIsOneItemWithMissingFields() {
    #expect(
        problems(Order.self, "<order><id>A</id><first><name>x</name><count>2</count></first><item/></order>")
            == "item[0].name: missing, item[0].count: missing")
}

@Test func anEmptyElementIsAnEmptyString() {
    #expect(
        problems(
            Order.self,
            "<order><id></id><first><name>x</name><count>2</count></first><item><name>a</name><count>2</count></item></order>"
        )
            == "id: blank")
}

// 3. One repeated element

@Test func aSingleRepeatedElementIsAOneItemArray() throws {
    let order = try decode(
        Order.self,
        "<order><id>A</id><first><name>x</name><count>2</count></first><item><name>a</name><count>2</count></item></order>"
    ).get()
    #expect(order.item == [Item(name: .unsafeMk("a"), count: .unsafeMk(2))])
}

// 4. Strict mode and attributes

@Test func strictTreatsAnUndeclaredAttributeAsUnexpected() {
    #expect(
        problems(StrictItem.self, #"<item id="7"><name>a</name><count>2</count></item>"#)
            == "id: unexpected")
    #expect(
        problems(StrictItem.self, "<item><name>a</name><count>2</count><extra>1</extra></item>")
            == "extra: unexpected")
}

@Test func aDeclaredPropertyReadsAnAttribute() throws {
    let tagged = try decode(Tagged.self, #"<tagged id="7"><name>a</name></tagged>"#).get()
    #expect(tagged.id.value == "7" && tagged.name.value == "a")
}

@Test func anEmptyArraySurvivesAnXMLRoundTrip() throws {
    let order = Order(id: .unsafeMk("A"), first: Item(name: .unsafeMk("x"), count: .unsafeMk(2)), item: [])
    let xml = try XMLEncoder().encode(order.encoded, withRootKey: "order")
    #expect(try Order.decode(xml, using: XMLDecoder()).get() == order)
}

@JSONSchema(failure: XF.self)
struct OptionalItems: Equatable {
    let item: [Item]?
}

@Test func anOptionalEmptyArrayComesBackAsNil() throws {
    let xml = try XMLEncoder().encode(OptionalItems(item: []).encoded, withRootKey: "items")
    #expect(try OptionalItems.decode(xml, using: XMLDecoder()).get() == OptionalItems(item: nil))
}
