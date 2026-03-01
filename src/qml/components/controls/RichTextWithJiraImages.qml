/**
 * RichTextWithJiraImages.qml
 *
 * Exibe Markdown renderizado em HTML com suporte a imagens de attachment Jira.
 * URLs de attachment exigem auth; faz fetch assíncrono via jiraService.fetchAttachmentDataUrl
 * e substitui placeholders por <img src="data:..."> quando attachmentDataUrlReady for emitido.
 */
pragma ComponentBehavior: Bound
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: root

    implicitHeight: contentText.implicitHeight
    height: Math.max(contentText.implicitHeight, 1)

    property string sourceText: ""
    property var jiraService: null

    property string _processedHtml: ""
    property var _pendingUrls: ({})

    function _escapeForAttr(s) {
        if (!s)
            return "";
        return String(s).replace(/&/g, "&amp;").replace(/"/g, "&quot;");
    }

    function _extractJiraUrls(html) {
        var urls = [];
        var re = /data-jira-img="([^"]+)"/g;
        var m;
        while ((m = re.exec(html)) !== null) {
            var url = m[1].replace(/&quot;/g, '"').replace(/&amp;/g, "&");
            if (urls.indexOf(url) < 0)
                urls.push(url);
        }
        return urls;
    }

    function _replacePlaceholderWithImg(html, url, dataUrl) {
        var escaped = _escapeForAttr(url);
        var needle = 'data-jira-img="' + escaped + '"';
        var idx = html.indexOf(needle);
        while (idx >= 0) {
            var spanStart = html.lastIndexOf("<span", idx);
            var spanEnd = html.indexOf("</span>", idx);
            if (spanStart >= 0 && spanEnd >= 0) {
                spanEnd += 7;
                var spanContent = html.substring(spanStart, spanEnd);
                var fnStart = spanContent.indexOf('data-filename="');
                var fnEnd = spanContent.indexOf('"', fnStart + 15);
                var alt = (fnStart >= 0 && fnEnd >= 0) ? spanContent.substring(fnStart + 15, fnEnd).replace(/&quot;/g, '"').replace(/&amp;/g, "&") : "imagem";
                var widthMatch = spanContent.match(/data-width="(\d+)"/);
                var widthPx = widthMatch ? widthMatch[1] : "";
                // Qt RichText ignora style em img; usar atributos width/height diretamente
                var widthAttr = widthPx ? (' width="' + widthPx + '"') : "";
                var imgTag = '<img src="' + dataUrl + '" alt="' + alt.replace(/"/g, "&quot;") + '"' + widthAttr + '/>';
                html = html.substring(0, spanStart) + imgTag + html.substring(spanEnd);
                idx = html.indexOf(needle, spanStart);
            } else {
                break;
            }
        }
        return html;
    }

    function _renderAndProcess() {
        // qmllint disable unqualified
        if (typeof markdownPreviewRenderer === "undefined" || !markdownPreviewRenderer) {
            root._processedHtml = root.sourceText || "";
            return;
        }
        var raw = markdownPreviewRenderer.render(root.sourceText || "");
        // qmllint enable unqualified
        root._processedHtml = raw;
        var urls = _extractJiraUrls(raw);
        if (urls.length > 0 && root.jiraService && typeof root.jiraService.fetchAttachmentDataUrl === "function") {
            for (var i = 0; i < urls.length; i++) {
                root.jiraService.fetchAttachmentDataUrl(urls[i]);
            }
        }
    }

    onSourceTextChanged: _renderAndProcess()
    onJiraServiceChanged: _renderAndProcess()

    Component.onCompleted: _renderAndProcess()

    Connections {
        target: root.jiraService || null
        function onAttachmentDataUrlReady(url, dataUrl) {
            root._processedHtml = root._replacePlaceholderWithImg(root._processedHtml, url, dataUrl);
        }
    }

    Text {
        id: contentText
        width: root.width - Kirigami.Units.largeSpacing * 2
        x: Kirigami.Units.largeSpacing
        topPadding: Kirigami.Units.smallSpacing
        bottomPadding: Kirigami.Units.smallSpacing
        textFormat: Text.RichText
        color: "#ffffff"
        text: root._processedHtml || (root.sourceText || "")
        wrapMode: Text.Wrap
        onLinkActivated: function (link) {
            Qt.openUrlExternally(link);
        }
    }
}
