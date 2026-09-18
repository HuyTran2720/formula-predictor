//
//  LocalCoordinateSystem.swift
//  FormulaGenie
//
//  GeoJSON coordinates are longitude/latitude - degrees on a sphere, not
//  flat distances - so treating them as X/Z world units directly would both
//  distort the circuit's true shape (a degree of longitude covers less real
//  ground than a degree of latitude away from the equator) and give every
//  downstream distance/offset calculation the wrong scale entirely. This
//  projects each point onto a local, flat tangent plane centered on the
//  circuit, in real meters - what track-width offsets, elevation sampling,
//  and mesh generation all actually need to operate on.
//

import Foundation

enum LocalCoordinateSystem {
    /// Meters per degree of latitude - effectively constant everywhere on
    /// Earth, unlike longitude.
    private static let metersPerDegreeLatitude = 111_320.0

    /// Projects `coordinates` onto a local (x, z) plane in meters, centered
    /// on their own centroid: (0, 0) is the middle of the circuit, +x is
    /// east, +z is south.
    static func project(_ coordinates: [(longitude: Double, latitude: Double)]) -> [SIMD2<Double>] {
        let centerLongitude = coordinates.map(\.longitude).reduce(0, +) / Double(coordinates.count)
        let centerLatitude = coordinates.map(\.latitude).reduce(0, +) / Double(coordinates.count)
        // Longitude degrees shrink toward the poles by cos(latitude) - the
        // same correction this project's 2D track already needed.
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(centerLatitude * .pi / 180)

        return coordinates.map { coordinate in
            SIMD2(
                (coordinate.longitude - centerLongitude) * metersPerDegreeLongitude,
                (coordinate.latitude - centerLatitude) * metersPerDegreeLatitude
            )
        }
    }
}
