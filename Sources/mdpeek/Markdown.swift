import Foundation
import cmark_gfm
import cmark_gfm_extensions

enum Markdown {
    static let fileExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]

    /// Renders GitHub Flavored Markdown with cmark-gfm, the parser GitHub itself uses.
    /// Raw HTML is passed through and sanitized by the web view before display.
    static func html(from data: Data) -> String {
        cmark_gfm_core_extensions_ensure_registered()
        // Source positions (data-sourcepos) let the preview follow the editor's scrolling.
        let options = CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES | CMARK_OPT_SOURCEPOS
        let parser = cmark_parser_new(options)
        defer { cmark_parser_free(parser) }
        for name in ["table", "strikethrough", "autolink", "tagfilter", "tasklist"] {
            cmark_parser_attach_syntax_extension(parser, cmark_find_syntax_extension(name))
        }
        data.withUnsafeBytes { bytes in
            cmark_parser_feed(parser, bytes.bindMemory(to: CChar.self).baseAddress, bytes.count)
        }
        let document = cmark_parser_finish(parser)
        defer { cmark_node_free(document) }
        let html = cmark_render_html(document, options, cmark_parser_get_syntax_extensions(parser))!
        defer { free(html) }
        return String(cString: html)
    }
}
