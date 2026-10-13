//
//  File.swift
//  
//
//  Created by Miguel de Icaza on 4/16/23.
//

import Foundation
import CoreText

extension CaretView {
    func drawCursor (in context: CGContext, hasFocus: Bool) {
        guard let ctline else {
            return
        }
        guard let terminal else {
            return
        }
        context.saveGState()
        context.clip(to: [bounds])
        context.setFillColor(TTColor.clear.cgColor)
        context.fill ([bounds])
        
        if !hasFocus {
            context.setStrokeColor(bgColor)
            context.setLineWidth(3)
            context.stroke(bounds)
            return
        }
        context.setFillColor(bgColor)
        let region: CGRect
        switch style {
        case .blinkBar, .steadyBar:
            region = CGRect (x: 0, y: 0, width: 2, height: bounds.height)
        case .blinkBlock, .steadyBlock:
            region = bounds
        case .blinkUnderline, .steadyUnderline:
            region = CGRect (x: 0, y: 0, width: bounds.width, height: 2)
        }
        context.fill([region])

        let lineDescent = CTFontGetDescent(terminal.fontSet.normal)
        let lineLeading = CTFontGetLeading(terminal.fontSet.normal)
        let yOffset = ceil(lineDescent+lineLeading)
        
        guard style == .steadyBlock || style  == .blinkBlock else {
            return
        }
        let caretFG = caretTextColor ?? terminal.nativeForegroundColor
        context.setFillColor(caretFG.cgColor)
        for run in CTLineGetGlyphRuns(ctline) as? [CTRun] ?? [] {
            let runGlyphsCount = CTRunGetGlyphCount(run)
            let runAttributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any] ?? [:]
            let runFont = runAttributes[.font] as! TTFont
            let ctRunFont = runFont as CTFont

            let runGlyphs = [CGGlyph](unsafeUninitializedCapacity: runGlyphsCount) { (bufferPointer, count) in
                CTRunGetGlyphs(run, CFRange(), bufferPointer.baseAddress!)
                count = runGlyphsCount
            }

            let fits = runGlyphs.map { terminal.glyphSlotFit(font: ctRunFont, glyph: $0, columnWidth: glyphColumnWidth) }
            var positions = fits.map { CGPoint(x: $0.dx, y: yOffset + $0.dy) }
            if fits.contains(where: { $0.scale != 1 }) {
                for i in 0..<runGlyphsCount {
                    let scale = fits[i].scale
                    let drawFont: CTFont = scale == 1 ? ctRunFont
                        : CTFontCreateCopyWithAttributes(ctRunFont, CTFontGetSize(ctRunFont) * scale, nil, nil)
                    var glyph = runGlyphs[i]
                    var position = positions[i]
                    CTFontDrawGlyphs(drawFont, &glyph, &position, 1, context)
                }
            } else {
                CTFontDrawGlyphs(runFont, runGlyphs, &positions, positions.count, context)
            }
        }
        context.restoreGState()
    }
}
