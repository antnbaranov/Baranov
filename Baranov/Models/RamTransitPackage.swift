//
//  RamTransitPackage.swift
//  Baranov
//
//  A self-contained, serializable snapshot of a `Ram` in transit, handed off
//  peer-to-peer via native AirDrop at borders and ocean crossings using
//  ShareLink + the Transferable protocol.
//
//  NOTE: `com.baranov.transit` must also be declared as an exported UTType
//  in the app target's Info.plist (`UTExportedTypeDeclarations`) with
//  conforming type `public.data`, and a `.ram` filename extension, for
//  AirDrop to advertise and recognize this package on both ends.
//

import Foundation
import UniformTypeIdentifiers
import CoreTransferable

extension UTType {
    /// The custom Uniform Type Identifier for a Baranov ram transit package.
    static let baranovPackage = UTType(exportedAs: "com.baranov.transit")
}

struct RamTransitPackage: Codable, Sendable, Transferable {
    let ram: Ram
    let exportedAt: Date

    init(ram: Ram, exportedAt: Date = Date()) {
        self.ram = ram
        self.exportedAt = exportedAt
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .baranovPackage)
    }
}
