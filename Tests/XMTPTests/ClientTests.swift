//
//  ClientTests.swift
//
//
//  Created by Pat Nakajima on 11/22/22.
//

import Foundation

import XCTest
@testable import XMTP
import XMTPRust
import XMTPTestHelpers

@available(iOS 15, *)
class ClientTests: XCTestCase {
	func testTakesAWallet() async {
		do {
			let fakeWallet = try PrivateKey.generate()
			_ = try await Client.create(account: fakeWallet)
		} catch let error where error is RustString {
			print("Hello \(error.localizedDescription) type: \(type(of: error))")
		} catch {
			print("\(error) \(type(of: error))")
		}
	}

	func testTakesAKeyAsWallet() async throws {
		let fakeWallet = try PrivateKey.generate()
		_ = try await Client.create(account: fakeWallet)
	}

	func testXMTPgRPC() async throws {
		let numEnvelopes = try await GRPCApiClient.runGrpcTest()
		XCTAssertEqual(numEnvelopes, 0)
	}

	func testCanMessage() async throws {
		let fixtures = await fixtures()
		let notOnNetwork = try PrivateKey.generate()

		let canMessage = try await fixtures.aliceClient.canMessage(fixtures.bobClient.address)
		let cannotMessage = try await fixtures.aliceClient.canMessage(notOnNetwork.address)
		XCTAssertTrue(canMessage)
		XCTAssertFalse(cannotMessage)
	}

	func testHasPrivateKeyBundleV1() async throws {
		let fakeWallet = try PrivateKey.generate()
		let client = try await Client.create(account: fakeWallet, apiClient: FakeApiClient())

		XCTAssertEqual(1, client.privateKeyBundleV1.preKeys.count)

		let preKey = client.privateKeyBundleV1.preKeys[0]

		XCTAssert(preKey.publicKey.hasSignature, "prekey not signed")
	}

	func testCanBeCreatedWithBundle() async throws {
		let fakeWallet = try PrivateKey.generate()
		let client = try await Client.create(account: fakeWallet)

		let bundle = client.privateKeyBundle
		let clientFromV1Bundle = try await Client.from(bundle: bundle)

		XCTAssertEqual(client.address, clientFromV1Bundle.address)
		XCTAssertEqual(client.privateKeyBundleV1.identityKey, clientFromV1Bundle.privateKeyBundleV1.identityKey)
		XCTAssertEqual(client.privateKeyBundleV1.preKeys, clientFromV1Bundle.privateKeyBundleV1.preKeys)
	}

	func testCanBeCreatedWithV1Bundle() async throws {
		let fakeWallet = try PrivateKey.generate()
		let client = try await Client.create(account: fakeWallet)

		let bundleV1 = client.v1keys
		let clientFromV1Bundle = try await Client.from(v1Bundle: bundleV1)

		XCTAssertEqual(client.address, clientFromV1Bundle.address)
		XCTAssertEqual(client.privateKeyBundleV1.identityKey, clientFromV1Bundle.privateKeyBundleV1.identityKey)
		XCTAssertEqual(client.privateKeyBundleV1.preKeys, clientFromV1Bundle.privateKeyBundleV1.preKeys)
	}
}
