//
//  web3.swift
//  Copyright © 2022 Argent Labs Limited. All rights reserved.
//
import Foundation
import Logging
import secp256k1
import web3
import XMTPRust

enum KeyUtilError: Error {
	case invalidContext
	case privateKeyInvalid
	case unknownError
	case signatureFailure
	case signatureParseFailure
	case badArguments
	case parseError
}

// Copied from web3.swift since its version is `internal`
enum KeyUtilx {
	static func generatePublicKey(from data: Data) throws -> Data {
		let vec = try XMTPRust.public_key_from_private_key_k256(RustVec<UInt8>(data))
		return Data(vec)
	}

	static func recoverPublicKeySHA256(from data: Data, message: Data) throws -> Data {
		let vec = try XMTPRust.recover_public_key_k256_sha256(RustVec<UInt8>(message), RustVec<UInt8>(data))
		return Data(vec)
	}

	static func recoverPublicKeyKeccak256(from data: Data, message: Data) throws -> Data {
		let vec = try XMTPRust.recover_public_key_k256_keccak256(RustVec<UInt8>(message), RustVec<UInt8>(data))
		return Data(vec)
	}

	static func sign(message: Data, with privateKey: Data, hashing: Bool) throws -> Data {
		guard let ctx = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY)) else {
			throw KeyUtilError.invalidContext
		}

		defer {
			secp256k1_context_destroy(ctx)
		}

		let msgData = hashing ? Util.keccak256(message) : message
		let msg = (msgData as NSData).bytes.assumingMemoryBound(to: UInt8.self)
		let privateKeyPtr = (privateKey as NSData).bytes.assumingMemoryBound(to: UInt8.self)
		let signaturePtr = UnsafeMutablePointer<secp256k1_ecdsa_recoverable_signature>.allocate(capacity: 1)
		defer {
			signaturePtr.deallocate()
		}
		guard secp256k1_ecdsa_sign_recoverable(ctx, signaturePtr, msg, privateKeyPtr, nil, nil) == 1 else {
			throw KeyUtilError.signatureFailure
		}

		let outputPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
		defer {
			outputPtr.deallocate()
		}
		var recid: Int32 = 0
		secp256k1_ecdsa_recoverable_signature_serialize_compact(ctx, outputPtr, &recid, signaturePtr)

		let outputWithRecidPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: 65)
		defer {
			outputWithRecidPtr.deallocate()
		}
		outputWithRecidPtr.assign(from: outputPtr, count: 64)
		outputWithRecidPtr.advanced(by: 64).pointee = UInt8(recid)

		let signature = Data(bytes: outputWithRecidPtr, count: 65)

		return signature
	}

	static func generateAddress(from publicKey: Data) -> EthereumAddress {
		let publicKeyData = publicKey.count == 64 ? publicKey : publicKey[1 ..< publicKey.count]

		let hash = Util.keccak256(publicKeyData)
		let address = hash.subdata(in: 12 ..< hash.count)
		return EthereumAddress("0x" + address.toHex)
	}

	static func recoverPublicKey(message: Data, signature: Data) throws -> Data {
		guard let ctx = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY)) else {
			throw KeyUtilError.invalidContext
		}
		defer { secp256k1_context_destroy(ctx) }

		// get recoverable signature
		let signaturePtr = UnsafeMutablePointer<secp256k1_ecdsa_recoverable_signature>.allocate(capacity: 1)
		defer { signaturePtr.deallocate() }

		let serializedSignature = Data(signature[0 ..< 64])
		var v = Int32(signature[64])
		if v >= 27, v <= 30 {
			v -= 27
		} else if v >= 31, v <= 34 {
			v -= 31
		} else if v >= 35, v <= 38 {
			v -= 35
		}

		// swiftlint:disable force_unwrapping
		try serializedSignature.withUnsafeBytes {
			guard secp256k1_ecdsa_recoverable_signature_parse_compact(ctx, signaturePtr, $0.bindMemory(to: UInt8.self).baseAddress!, v) == 1 else {
				throw KeyUtilError.signatureParseFailure
			}
		}
		let pubkey = UnsafeMutablePointer<secp256k1_pubkey>.allocate(capacity: 1)
		defer { pubkey.deallocate() }

		try message.withUnsafeBytes {
			guard secp256k1_ecdsa_recover(ctx, pubkey, signaturePtr, $0.bindMemory(to: UInt8.self).baseAddress!) == 1 else {
				throw KeyUtilError.signatureFailure
			}
		}

		var size = 65
		var rv = Data(count: size)
		_ = rv.withUnsafeMutableBytes {
			secp256k1_ec_pubkey_serialize(ctx, $0.bindMemory(to: UInt8.self).baseAddress!, &size, pubkey, UInt32(SECP256K1_EC_UNCOMPRESSED))
		}

		// swiftlint:enable force_unwrapping
		return rv
	}
}
