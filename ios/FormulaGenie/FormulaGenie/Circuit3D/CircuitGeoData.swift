//
//  CircuitGeoData.swift
//  FormulaGenie
//
//  Loads `es-1991.geojson` - the real, surveyed 2D centerline of Circuit de
//  Barcelona-Catalunya - and holds it exactly as supplied. This is the
//  authoritative source geometry for the whole 3D circuit environment
//  (see `CircuitCenterline`); nothing in this file alters it in any way,
//  it only parses the GeoJSON's `LineString` into plain coordinate pairs.
//

import Foundation

struct CircuitGeoData {
    /// Raw (longitude, latitude) pairs, in the exact order the GeoJSON's
    /// `LineString` lists them - still degrees, not yet a flat coordinate
    /// system (see `LocalCoordinateSystem`).
    let coordinates: [(longitude: Double, latitude: Double)]

    private struct FeatureCollection: Decodable {
        let features: [Feature]
    }
    private struct Feature: Decodable {
        let geometry: Geometry
    }
    private struct Geometry: Decodable {
        let coordinates: [[Double]]
    }

    static func loadBundled(resource: String = "es-1991") -> CircuitGeoData {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "geojson") else {
            fatalError("\(resource).geojson not found in bundle - check Target Membership")
        }
        do {
            let data = try Data(contentsOf: url)
            let collection = try JSONDecoder().decode(FeatureCollection.self, from: data)
            guard let raw = collection.features.first?.geometry.coordinates else {
                fatalError("\(resource).geojson has no LineString coordinates")
            }
            let coordinates = raw.map { (longitude: $0[0], latitude: $0[1]) }
            return CircuitGeoData(coordinates: coordinates)
        } catch {
            fatalError("\(resource).geojson failed to decode: \(error)")
        }
    }
}
