//
//  InfoPlistStrings.swift
//  VideoPicker
//
//  Created by 山本敬之 on 2026/01/20.
//

import Foundation

enum InfoPlistStrings {
    static func string(_ key: String) -> String {
        if let value = Bundle.main.localizedInfoDictionary?[key] as? String {
            return value
        }
        if let value = Bundle.main.infoDictionary?[key] as? String {
            return value
        }
        return key
    }

    static func formatted(_ key: String, _ arguments: CVarArg...) -> String {
        let format = string(key)
        return String(format: format, arguments: arguments)
    }
}
