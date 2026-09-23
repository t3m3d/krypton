import Foundation

struct Animal: Codable, Identifiable {
    let id: String
    let name: String
    let scientificName: String
    let symbol: String
    let introduction: String
    let sounds: [AnimalSound]
}

struct AnimalSound: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let filename: String
    let credit: String
    let sourceURL: URL
    let license: String
    let licenseURL: URL

    var localURL: URL? {
        Bundle.main.url(forResource: filename, withExtension: nil)
    }
}

enum Catalog {
    static func load(bundle: Bundle = .main) throws -> [Animal] {
        guard let url = bundle.url(forResource: "animals", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([Animal].self, from: Data(contentsOf: url))
    }
}
