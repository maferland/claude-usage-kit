import XCTest
@testable import ClaudeUsageKit

final class PricingServiceTests: XCTestCase {

    func testFallbackPricingContainsExpectedModels() {
        let pricing = PricingService.fallbackPricing
        XCTAssertNotNil(pricing["claude-opus-4-6"])
        XCTAssertNotNil(pricing["claude-sonnet-4-6"])
        XCTAssertNotNil(pricing["claude-haiku-4-5"])
    }

    func testResolvePricingExactMatch() {
        let table = PricingService.fallbackPricing
        let result = PricingService.resolvePricing(for: "claude-opus-4-6", from: table)
        XCTAssertEqual(result.inputCostPerToken, 5e-06)
    }

    func testResolvePricingFuzzyMatch() {
        let table = PricingService.fallbackPricing
        // Unknown opus variant should fuzzy-match to an opus entry
        let result = PricingService.resolvePricing(for: "claude-opus-4-99-20260101", from: table)
        XCTAssertEqual(result.inputCostPerToken, 5e-06)
    }

    func testResolvePricingSonnetFamily() {
        let table = PricingService.fallbackPricing
        let result = PricingService.resolvePricing(for: "claude-sonnet-4-20250514", from: table)
        XCTAssertEqual(result.inputCostPerToken, 3e-06)
    }

    func testResolvePricingUnknownDefaultsToOpus() {
        let table = PricingService.fallbackPricing
        let result = PricingService.resolvePricing(for: "claude-unknown-model", from: table)
        // Unknown family defaults to opus (safe overestimate)
        XCTAssertEqual(result.inputCostPerToken, 5e-06)
    }
}
