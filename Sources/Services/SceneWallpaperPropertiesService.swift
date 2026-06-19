import Foundation

enum ScenePropertyPresentation: String, Codable {
    case control
    case group
    case decoration
}

struct SceneWallpaperProperty: Codable, Equatable, Identifiable {
    var id: String { key }

    let key: String
    let type: String
    let text: String?
    let originalValue: ScenePropertyValue
    var currentValue: ScenePropertyValue
    let options: [String: String]?
    let min: Double?
    let max: Double?
    let step: Double?
    let order: Int?
    let group: String?
    let condition: String?
    let presentation: ScenePropertyPresentation

    var isModified: Bool {
        originalValue != currentValue
    }
}

enum ScenePropertyValue: Codable, Equatable {
    case bool(Bool)
    case number(Double)
    case string(String)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String {
        switch self {
        case .bool(let value):
            return value ? "true" : "false"
        case .number(let value):
            return value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
        case .string(let value):
            return value
        case .null:
            return ""
        }
    }

    var truthy: Bool {
        switch self {
        case .bool(let value):
            return value
        case .number(let value):
            return value != 0
        case .string(let value):
            let lower = value.lowercased()
            return !value.isEmpty && value != "0" && lower != "false"
        case .null:
            return false
        }
    }
}

struct SceneWallpaperPropertiesDocument: Codable, Equatable {
    let wallpaperPath: String
    var overrides: [String: ScenePropertyValue]
    let backupDate: Date

    init(wallpaperPath: String, overrides: [String: ScenePropertyValue] = [:]) {
        self.wallpaperPath = wallpaperPath
        self.overrides = overrides
        self.backupDate = Date()
    }
}

enum SceneWallpaperPropertiesService {
    private static let folderName = "SceneProperties"

    static func loadProperties(for wallpaperURL: URL) -> [SceneWallpaperProperty] {
        let contentDir = resolveContentDir(for: wallpaperURL)
        let projectURL = contentDir.appendingPathComponent("project.json")
        guard let data = try? Data(contentsOf: projectURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return parseProperties(from: json)
    }

    static func loadPropertiesWithOverrides(for wallpaperURL: URL) -> [SceneWallpaperProperty] {
        let originalProperties = loadProperties(for: wallpaperURL)
        let document = loadDocument(for: wallpaperURL)
        guard !document.overrides.isEmpty else { return originalProperties }

        return originalProperties.map { property in
            var updated = property
            if let override = document.overrides[property.key] {
                updated.currentValue = override
            }
            return updated
        }
    }

    static func loadVisibleProperties(for wallpaperURL: URL) -> [SceneWallpaperProperty] {
        let properties = loadPropertiesWithOverrides(for: wallpaperURL)
        let values = Dictionary(uniqueKeysWithValues: properties.map { ($0.key, $0.currentValue) })
        return properties.filter { property in
            guard property.presentation != .decoration else { return false }
            return evaluateCondition(property.condition, values: values)
        }
    }

    static func setProperty(key: String, value: ScenePropertyValue, for wallpaperURL: URL) throws {
        var document = loadDocument(for: wallpaperURL)
        document.overrides[key] = value
        try saveDocument(document, for: wallpaperURL)
    }

    static func resetProperty(key: String, for wallpaperURL: URL) throws {
        var document = loadDocument(for: wallpaperURL)
        document.overrides.removeValue(forKey: key)
        try saveDocument(document, for: wallpaperURL)
    }

    static func resetAllProperties(for wallpaperURL: URL) throws {
        let document = SceneWallpaperPropertiesDocument(wallpaperPath: wallpaperURL.path)
        try saveDocument(document, for: wallpaperURL)
    }

    static func propertiesOverrideJSON(for wallpaperURL: URL) -> String? {
        let document = loadDocument(for: wallpaperURL)
        guard !document.overrides.isEmpty else { return nil }

        let dict = document.overrides.mapValues { $0.stringValue }
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    static func hasEditableProperties(for wallpaperURL: URL) -> Bool {
        loadVisibleProperties(for: wallpaperURL).contains { $0.presentation == .control }
    }

    static func loadDocument(for wallpaperURL: URL) -> SceneWallpaperPropertiesDocument {
        let fileURL = documentFileURL(for: wallpaperURL)
        guard let data = try? Data(contentsOf: fileURL),
              let document = try? JSONDecoder().decode(SceneWallpaperPropertiesDocument.self, from: data) else {
            return SceneWallpaperPropertiesDocument(wallpaperPath: wallpaperURL.path)
        }
        return document
    }

    private static func saveDocument(_ document: SceneWallpaperPropertiesDocument, for wallpaperURL: URL) throws {
        let fileURL = documentFileURL(for: wallpaperURL)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func documentFileURL(for wallpaperURL: URL) -> URL {
        let safeName = wallpaperURL.path
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        let baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(AppConstants.appBundleIdentifier, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        return baseDir.appendingPathComponent("\(safeName).json")
    }

    private static func resolveContentDir(for wallpaperURL: URL) -> URL {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: wallpaperURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return wallpaperURL
        }

        if wallpaperURL.pathExtension.lowercased() == "pkg",
           let extractedURL = extractPackageIfNeeded(at: wallpaperURL) {
            return extractedURL
        }

        return wallpaperURL.deletingLastPathComponent()
    }

    private static func extractPackageIfNeeded(at url: URL) -> URL? {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wallpaper_toolbox_props_\(url.deletingPathExtension().lastPathComponent)_\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", url.path, "-d", tempDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? tempDir : nil
        } catch {
            return nil
        }
    }

    private static func parseProperties(from json: [String: Any]) -> [SceneWallpaperProperty] {
        guard let general = json["general"] as? [String: Any],
              let properties = general["properties"] as? [String: Any] else {
            return []
        }

        var result: [SceneWallpaperProperty] = []
        for (key, rawProperty) in properties {
            guard let property = rawProperty as? [String: Any] else { continue }
            let rawType = property["type"] as? String ?? "text"
            let text = property["text"] as? String
            let presentation = determinePresentation(rawType: rawType, key: key, text: text)
            let value = parseValue(property["value"])

            result.append(SceneWallpaperProperty(
                key: key,
                type: normalizePropertyType(rawType),
                text: text,
                originalValue: value,
                currentValue: value,
                options: parseOptions(property["options"]),
                min: numberValue(property["min"]),
                max: numberValue(property["max"]),
                step: numberValue(property["step"]),
                order: intValue(property["order"]),
                group: property["group"] as? String,
                condition: property["condition"] as? String,
                presentation: presentation
            ))
        }

        return result.sorted {
            let lhsOrder = $0.order ?? Int.max
            let rhsOrder = $1.order ?? Int.max
            if lhsOrder == rhsOrder { return $0.key < $1.key }
            return lhsOrder < rhsOrder
        }
    }

    private static func parseOptions(_ raw: Any?) -> [String: String]? {
        if let dict = raw as? [String: String] {
            return dict
        }
        if let dict = raw as? [String: Any] {
            let mapped = dict.reduce(into: [String: String]()) { result, item in
                result[item.key] = String(describing: item.value)
            }
            return mapped.isEmpty ? nil : mapped
        }
        if let array = raw as? [[String: Any]] {
            let mapped = array.reduce(into: [String: String]()) { result, item in
                if let value = item["value"], let label = item["label"] {
                    result[String(describing: value)] = String(describing: label)
                }
            }
            return mapped.isEmpty ? nil : mapped
        }
        return nil
    }

    private static func determinePresentation(rawType: String, key: String, text: String?) -> ScenePropertyPresentation {
        let lower = rawType.lowercased()
        if lower == "group" || lower == "description" {
            return .group
        }

        let keyLower = key.lowercased()
        let textLower = (text ?? "").lowercased()
        if keyLower.hasPrefix("imgsrc")
            || keyLower.hasPrefix("brimgsrc")
            || keyLower.contains("imgsrchttp")
            || keyLower.contains("hrefhttps")
            || textLower.contains("<img")
            || textLower.contains("<a ")
            || textLower.contains("<hr")
            || textLower.contains("rf=viewer")
            || (key.count > 96 && !key.contains("_")) {
            return .decoration
        }
        return .control
    }

    private static func normalizePropertyType(_ raw: String) -> String {
        switch raw.lowercased() {
        case "bool", "toggle", "checkbox":
            return "bool"
        case "slider", "float", "percentage", "integer", "int":
            return "slider"
        case "color", "schemecolor":
            return "color"
        case "combo", "dropdown", "select":
            return "combo"
        case "textinput", "string":
            return "textinput"
        case "text", "label":
            return "label"
        case "file", "directory", "scenetexture", "replacetexture":
            return "file"
        case "group":
            return "group"
        case "description":
            return "description"
        default:
            return raw.lowercased()
        }
    }

    private static func numberValue(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        if let value = raw as? String { return Double(value) }
        return nil
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String { return Int(value) }
        return nil
    }

    private static func parseValue(_ raw: Any?) -> ScenePropertyValue {
        guard let raw else { return .null }
        if let value = raw as? Bool {
            return .bool(value)
        }
        if let value = raw as? NSNumber {
            return .number(value.doubleValue)
        }
        if let value = raw as? String {
            return .string(value)
        }
        return .null
    }

    static func evaluateCondition(_ expression: String?, values: [String: ScenePropertyValue]) -> Bool {
        guard let expression, !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        return evaluateExpression(expression, values: values) != false
    }

    private enum ConditionToken {
        case identifier(String)
        case number(Double)
        case string(String)
        case bool(Bool)
        case op(String)
        case paren(Character)
    }

    private static func evaluateExpression(_ expression: String, values: [String: ScenePropertyValue]) -> Bool? {
        let tokens = tokenize(expression)
        guard !tokens.isEmpty else { return nil }
        var index = 0
        return parseOr(tokens: tokens, index: &index, values: values).map { $0.truthy }
    }

    private static func tokenize(_ input: String) -> [ConditionToken] {
        var tokens: [ConditionToken] = []
        var index = input.startIndex
        while index < input.endIndex {
            let character = input[index]
            if character.isWhitespace {
                index = input.index(after: index)
                continue
            }

            let twoEnd = input.index(index, offsetBy: 2, limitedBy: input.endIndex) ?? input.endIndex
            let two = String(input[index..<twoEnd])
            if ["&&", "||", "==", "!=", ">=", "<="].contains(two) {
                tokens.append(.op(two))
                index = input.index(index, offsetBy: 2)
                continue
            }
            if "><!".contains(character) {
                tokens.append(.op(String(character)))
                index = input.index(after: index)
                continue
            }
            if character == "(" || character == ")" {
                tokens.append(.paren(character))
                index = input.index(after: index)
                continue
            }
            if character == "'" || character == "\"" {
                var end = input.index(after: index)
                var string = ""
                while end < input.endIndex && input[end] != character {
                    string.append(input[end])
                    end = input.index(after: end)
                }
                if end < input.endIndex {
                    end = input.index(after: end)
                }
                tokens.append(.string(string))
                index = end
                continue
            }
            if character.isNumber || (character == "-" && input.index(after: index) < input.endIndex && input[input.index(after: index)].isNumber) {
                var end = index
                if character == "-" {
                    end = input.index(after: end)
                }
                while end < input.endIndex && (input[end].isNumber || input[end] == ".") {
                    end = input.index(after: end)
                }
                if let number = Double(input[index..<end]) {
                    tokens.append(.number(number))
                }
                index = end
                continue
            }
            if character.isLetter || character == "_" {
                var end = index
                while end < input.endIndex && (input[end].isLetter || input[end].isNumber || input[end] == "_" || input[end] == ".") {
                    end = input.index(after: end)
                }
                let word = String(input[index..<end])
                if word == "true" {
                    tokens.append(.bool(true))
                } else if word == "false" {
                    tokens.append(.bool(false))
                } else {
                    tokens.append(.identifier(word))
                }
                index = end
                continue
            }
            index = input.index(after: index)
        }
        return tokens
    }

    private static func parsePrimary(tokens: [ConditionToken], index: inout Int, values: [String: ScenePropertyValue]) -> ScenePropertyValue? {
        guard index < tokens.count else { return nil }
        let token = tokens[index]
        switch token {
        case .op("!"):
            index += 1
            guard let value = parsePrimary(tokens: tokens, index: &index, values: values) else { return nil }
            return .bool(!value.truthy)
        case .paren("("):
            index += 1
            let value = parseOr(tokens: tokens, index: &index, values: values)
            if index < tokens.count, case .paren(")") = tokens[index] {
                index += 1
            }
            return value
        case .bool(let value):
            index += 1
            return .bool(value)
        case .number(let value):
            index += 1
            return .number(value)
        case .string(let value):
            index += 1
            return .string(value)
        case .identifier(let identifier):
            index += 1
            let key = identifier.hasSuffix(".value") ? String(identifier.dropLast(6)) : identifier
            return values[key]
        default:
            return nil
        }
    }

    private static func parseComparison(tokens: [ConditionToken], index: inout Int, values: [String: ScenePropertyValue]) -> ScenePropertyValue? {
        guard var left = parsePrimary(tokens: tokens, index: &index, values: values) else { return nil }
        while index < tokens.count {
            guard case .op(let op) = tokens[index], ["==", "!=", ">", ">=", "<", "<="].contains(op) else { break }
            index += 1
            guard let right = parsePrimary(tokens: tokens, index: &index, values: values) else { break }
            switch op {
            case "==":
                left = .bool(valuesEqual(left, right))
            case "!=":
                left = .bool(!valuesEqual(left, right))
            case ">":
                left = .bool(compareNumeric(left, right, op: >))
            case ">=":
                left = .bool(compareNumeric(left, right, op: >=))
            case "<":
                left = .bool(compareNumeric(left, right, op: <))
            case "<=":
                left = .bool(compareNumeric(left, right, op: <=))
            default:
                break
            }
        }
        return left
    }

    private static func parseAnd(tokens: [ConditionToken], index: inout Int, values: [String: ScenePropertyValue]) -> ScenePropertyValue? {
        guard var left = parseComparison(tokens: tokens, index: &index, values: values) else { return nil }
        while index < tokens.count, case .op("&&") = tokens[index] {
            index += 1
            guard let right = parseComparison(tokens: tokens, index: &index, values: values) else { break }
            left = .bool(left.truthy && right.truthy)
        }
        return left
    }

    private static func parseOr(tokens: [ConditionToken], index: inout Int, values: [String: ScenePropertyValue]) -> ScenePropertyValue? {
        guard var left = parseAnd(tokens: tokens, index: &index, values: values) else { return nil }
        while index < tokens.count, case .op("||") = tokens[index] {
            index += 1
            guard let right = parseAnd(tokens: tokens, index: &index, values: values) else { break }
            left = .bool(left.truthy || right.truthy)
        }
        return left
    }

    private static func valuesEqual(_ lhs: ScenePropertyValue, _ rhs: ScenePropertyValue) -> Bool {
        switch (lhs, rhs) {
        case (.bool(let lhsValue), .bool(let rhsValue)):
            return lhsValue == rhsValue
        case (.number(let lhsValue), .number(let rhsValue)):
            return lhsValue == rhsValue
        case (.string(let lhsValue), .string(let rhsValue)):
            return lhsValue == rhsValue
        case (.bool(let lhsValue), .number(let rhsValue)):
            return (lhsValue ? 1.0 : 0.0) == rhsValue
        case (.number(let lhsValue), .bool(let rhsValue)):
            return lhsValue == (rhsValue ? 1.0 : 0.0)
        case (.string(let lhsValue), .bool(let rhsValue)):
            return (lhsValue == "true") == rhsValue
        case (.bool(let lhsValue), .string(let rhsValue)):
            return lhsValue == (rhsValue == "true")
        default:
            return false
        }
    }

    private static func compareNumeric(_ lhs: ScenePropertyValue, _ rhs: ScenePropertyValue, op: (Double, Double) -> Bool) -> Bool {
        op(numericValue(lhs), numericValue(rhs))
    }

    private static func numericValue(_ value: ScenePropertyValue) -> Double {
        switch value {
        case .bool(let value):
            return value ? 1 : 0
        case .number(let value):
            return value
        case .string(let value):
            return Double(value) ?? 0
        case .null:
            return 0
        }
    }
}
