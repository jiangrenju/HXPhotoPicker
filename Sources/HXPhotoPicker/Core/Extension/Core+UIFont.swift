//
//  Core+UIFont.swift
//  HXPhotoPicker
//
//  Created by Silence on 2020/11/13.
//  Copyright © 2020 Silence. All rights reserved.
//

import UIKit

extension UIFont {
    
    static func regularPingFang(ofSize size: CGFloat) -> UIFont {
        if let font = UIFont.init(name: "PingFangSC-Regular", size: size) {
            return font
        }
        return .systemFont(ofSize: size, weight: .regular)
    }
    
    static func mediumPingFang(ofSize size: CGFloat) -> UIFont {
        if let font = UIFont.init(name: "PingFangSC-Medium", size: size) {
            return font
        }
        return .systemFont(ofSize: size, weight: .medium)
    }
    
    static func semiboldPingFang(ofSize size: CGFloat) -> UIFont {
        if let font = UIFont.init(name: "PingFangSC-Semibold", size: size) {
            return font
        }
        return .systemFont(ofSize: size, weight: .semibold)
    }
}
