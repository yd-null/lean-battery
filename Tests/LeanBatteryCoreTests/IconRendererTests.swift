import CoreGraphics
import CoreText
import Testing
@testable import LeanBatteryCore

/// RGBA reader for rendered icons, addressed in icon points (top-left origin).
private struct Pixels {
	let scale: Double
	let width: Int
	private let bytes: [UInt8]

	init(_ image: CGImage, scale: Double) {
		self.scale = scale
		width = image.width
		var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
		buffer.withUnsafeMutableBytes { raw in
			let context = CGContext(
				data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
				bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
				bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
			)!
			context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
		}
		bytes = buffer
	}

	/// Pixel covering the point (x, y).
	func at(_ x: Double, _ y: Double) -> [UInt8] {
		let index = (Int(y * scale) * width + Int(x * scale)) * 4
		return Array(bytes[index..<index + 4])
	}

	/// Pixels in a point-space rectangle.
	func region(x: ClosedRange<Double>, y: ClosedRange<Double>) -> [[UInt8]] {
		stride(from: y.lowerBound, through: y.upperBound, by: 1 / scale).flatMap { row in
			stride(from: x.lowerBound, through: x.upperBound, by: 1 / scale).map { at($0, row) }
		}
	}
}

/// Renders a state at 4× for pixel sampling.
private func render(_ state: BatteryState) throws -> Pixels {
	let image = try #require(IconRenderer.render(IconSpec(state: state), foregroundIsWhite: true, scale: 4))
	return Pixels(image, scale: 4)
}

@Suite struct IconRendererTests {
	@Test func rendersAtRequestedScale() throws {
		let image = try #require(IconRenderer.render(IconSpec(state: BatteryState(percent: 57)), foregroundIsWhite: true, scale: 2))
		#expect(image.width == 36)
		#expect(image.height == 36)
	}

	@Test func bodyStrokeIsForeground() throws {
		#expect(try render(BatteryState(percent: 57)).at(0.45, 12) == [255, 255, 255, 255])
	}

	@Test func emptyPartOfBodyIsTransparent() throws {
		#expect(try render(BatteryState(percent: 50)).at(2, 4.5)[3] == 0)
	}

	@Test func foregroundFillIsTranslucent() throws {
		// (3, 15) is inside the fill, below the number; 28% alpha ≈ 71.
		let pixel = try render(BatteryState(percent: 50)).at(3, 15)
		#expect((60...85).contains(pixel[3]))
	}

	@Test func chargingFillIsTranslucentGreen() throws {
		// 60% alpha ≈ 153; premultiplied green channel dominates.
		let pixel = try render(BatteryState(percent: 50, isCharging: true, isPluggedIn: true)).at(3, 15)
		#expect((140...165).contains(pixel[3]))
		#expect(pixel[1] > pixel[0] && pixel[1] > pixel[2])
	}

	@Test func numberIsSolidOverFillWithoutGaps() throws {
		// At 88% the whole glyph area is inside the fill: digits solid white, nothing cut out.
		let glyphArea = try render(BatteryState(percent: 88)).region(x: 3.5...14.5, y: 6...14)
		#expect(glyphArea.contains { $0 == [255, 255, 255, 255] })
		#expect(!glyphArea.contains { $0[3] == 0 })
	}

	@Test func plugIsSolidInsideFill() throws {
		// (9, 13.25) is on the plug's cord, below where a "100" would sit.
		#expect(try render(BatteryState(percent: 100, isPluggedIn: true)).at(9, 13.25) == [255, 255, 255, 255])
		#expect(try render(BatteryState(percent: 100)).at(9, 13.25)[3] < 255)
	}

	@Test func hotBadgeIsRedWithTransparentRing() throws {
		let hot = try render(BatteryState(percent: 57, isHot: true))
		let badge = hot.at(15.9, 2.5)
		#expect(badge[0] > 220 && badge[1] < 100 && badge[3] == 255)
		// (17.3, 4.5) is on the body's rounded corner stroke, inside the cleared ring.
		#expect(hot.at(17.3, 4.5)[3] == 0)
		#expect(try render(BatteryState(percent: 57)).at(17.3, 4.5)[3] == 255)
	}

	@Test func twoTopTerminalsHaveATransparentGap() throws {
		let pixels = try render(BatteryState(percent: 57))
		#expect(pixels.at(5, 1) == [255, 255, 255, 255])
		#expect(pixels.at(13, 1) == [255, 255, 255, 255])
		#expect(pixels.at(9, 1)[3] == 0)
	}

	@Test(arguments: 0...100)
	func everyPercentageFitsTheWiderInterior(percent: Int) {
		let spec = IconSpec(state: BatteryState(percent: percent))
		let font = IconRenderer.numberFont(size: spec.numberFontSize)
		let line = IconRenderer.numberLine(value: percent, font: font)
		let width = CTLineGetTypographicBounds(line, nil, nil, nil)
		#expect(width <= IconRenderer.inner.width)
		#expect(CTFontGetCapHeight(font) <= IconRenderer.inner.height)
	}

	@Test(arguments: [1.0, 2.0])
	func rendersNewDimensionsAtEachScale(scale: Double) throws {
		let image = try #require(IconRenderer.render(IconSpec(state: BatteryState(percent: 100)), foregroundIsWhite: true, scale: scale))
		#expect(image.width == Int(18 * scale))
		#expect(image.height == Int(18 * scale))
	}
}
