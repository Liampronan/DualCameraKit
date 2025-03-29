import XCTest

@discardableResult
public func XCTAssertThrowsError<T: Error>(ofType expectedType: T.Type, _ expression: @autoclosure () async throws -> Void, file: StaticString = #file, line: UInt = #line) async -> T? {
    do {
        try await expression()
        XCTFail("Expected error of type \(expectedType)", file: file, line: line)
        return nil
    } catch let error as T {
        return error
    } catch {
        XCTFail("Unexpected error type: \(error)", file: file, line: line)
        return nil
    }
}
