"""Tests for core.adf_media module."""

import tempfile
from pathlib import Path

import pytest

from core.adf_media import (
    IMAGE_MIMES,
    VIDEO_MIMES,
    AttachmentInfo,
    build_description_adf_with_media,
    create_link_fallback_node,
    create_media_single_node,
    get_dimensions,
    get_display_size,
    get_type,
    parse_attachment_content_url,
    should_embed,
)


class TestAttachmentTypeDetector:
    def test_get_type_image_by_mime(self):
        assert get_type("x.png", "image/png") == "image"
        assert get_type("x.jpg", "image/jpeg") == "image"
        assert get_type("x.gif", "image/gif") == "image"
        assert get_type("x.webp", "image/webp") == "image"
        assert get_type("x.svg", "image/svg+xml") == "image"

    def test_get_type_video_by_mime(self):
        assert get_type("x.mp4", "video/mp4") == "video"
        assert get_type("x.mov", "video/quicktime") == "video"
        assert get_type("x.webm", "video/webm") == "video"

    def test_get_type_file_by_mime(self):
        assert get_type("x.pdf", "application/pdf") == "file"
        assert get_type("x.txt", "text/plain") == "file"

    def test_get_type_by_extension_when_no_mime(self):
        assert get_type("photo.png") == "image"
        assert get_type("photo.jpg") == "image"
        assert get_type("video.mp4") == "video"
        assert get_type("doc.pdf") == "file"

    def test_should_embed(self):
        assert should_embed("image") is True
        assert should_embed("video") is True
        assert should_embed("file") is False
        # Generic "attachment" alt from markdown → embed as image (preserves width)
        assert should_embed("file", "attachment") is True
        assert should_embed("file", "imagem") is True
        assert should_embed("file", "image") is True
        assert should_embed("file", "doc.pdf") is False


class TestImageDimensionExtractor:
    def test_get_display_size_smaller_than_max(self):
        assert get_display_size(400, 300, max_width=760) == (400, 300)

    def test_get_display_size_larger_than_max(self):
        w, h = get_display_size(1520, 1140, max_width=760)
        assert w == 760
        assert h == 570

    def test_get_display_size_zero_dimensions(self):
        w, h = get_display_size(0, 0, max_width=760)
        assert w == 760
        assert h == 760

    def test_get_dimensions_nonexistent_file(self):
        assert get_dimensions("/nonexistent/path/image.png") is None

    def test_get_dimensions_real_image(self):
        # Create a minimal valid PNG (1x1 pixel)
        png_data = (
            b"\x89PNG\r\n\x1a\n"
            b"\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
            b"\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDAT"
            b"\x08\xd7c\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N"
            b"\x00\x00\x00\x00IEND\xaeB`\x82"
        )
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
            f.write(png_data)
            path = f.name
        try:
            result = get_dimensions(path)
            # May be None if Pillow not installed
            if result is not None:
                assert result == (1, 1)
        finally:
            Path(path).unlink(missing_ok=True)


class TestAttachmentInfo:
    def test_dataclass_fields(self):
        info = AttachmentInfo(
            id="12345",
            filename="test.png",
            mime_type="image/png",
            size=1024,
            width=800,
            height=600,
            collection_id="contentId-123",
        )
        assert info.id == "12345"
        assert info.filename == "test.png"
        assert info.width == 800
        assert info.height == 600
        assert info.collection_id == "contentId-123"


class TestCreateMediaSingleNode:
    def test_creates_external_media_when_base_url_provided(self):
        """With base_url, uses type 'external' and attachment content URL (works with REST API)."""
        info = AttachmentInfo(
            id="12345",
            filename="test.png",
            mime_type="image/png",
            size=1024,
            width=400,
            height=300,
        )
        node = create_media_single_node(
            info, layout="center", base_url="https://example.atlassian.net"
        )
        assert node["type"] == "mediaSingle"
        assert node["attrs"]["layout"] == "center"
        assert len(node["content"]) == 1
        media = node["content"][0]
        assert media["type"] == "media"
        assert media["attrs"]["type"] == "external"
        assert media["attrs"]["url"] == (
            "https://example.atlassian.net/rest/api/3/attachment/content/12345"
        )
        assert media["attrs"]["width"] == 400
        assert media["attrs"]["height"] == 300

    def test_creates_file_media_when_no_base_url(self):
        """Without base_url, uses type 'file' (legacy, requires Media API UUID)."""
        info = AttachmentInfo(
            id="12345",
            filename="test.png",
            mime_type="image/png",
            size=1024,
            width=400,
            height=300,
        )
        node = create_media_single_node(info, layout="center")
        assert node["type"] == "mediaSingle"
        media = node["content"][0]
        assert media["attrs"]["type"] == "file"
        assert media["attrs"]["id"] == "12345"
        assert media["attrs"]["alt"] == "test.png"

    def test_collection_format_content_id(self):
        """collection_id numeric is formatted as contentId-{id} for Jira Cloud."""
        info = AttachmentInfo(
            id="1977013",
            filename="img.png",
            mime_type="image/png",
            size=0,
            width=100,
            height=100,
            collection_id="1750142",
        )
        node = create_media_single_node(info)
        media = node["content"][0]
        assert media["attrs"]["collection"] == "contentId-1750142"

    def test_collection_format_preserves_content_id_prefix(self):
        """collection_id already with contentId- prefix is preserved."""
        info = AttachmentInfo(
            id="1",
            filename="x.png",
            mime_type="image/png",
            size=0,
            collection_id="contentId-589847937",
        )
        node = create_media_single_node(info)
        media = node["content"][0]
        assert media["attrs"]["collection"] == "contentId-589847937"

    def test_display_width_override(self):
        info = AttachmentInfo(
            id="1",
            filename="x.png",
            mime_type="image/png",
            size=0,
            width=1520,
            height=1140,
        )
        node = create_media_single_node(info, display_width=380)
        media = node["content"][0]
        assert media["attrs"]["width"] == 380
        assert media["attrs"]["height"] == 285
        # ADF mediaSingle attrs: width/widthType control display size
        assert node["attrs"]["width"] == 380
        assert node["attrs"]["widthType"] == "pixel"

    def test_display_width_not_added_for_wide_layout(self):
        """width/widthType not added when layout is wide or full-width (ADF spec)."""
        info = AttachmentInfo(
            id="1",
            filename="x.png",
            mime_type="image/png",
            size=0,
            width=400,
            height=300,
        )
        for layout in ("wide", "full-width"):
            node = create_media_single_node(info, layout=layout, display_width=260)
            assert "width" not in node["attrs"]
            assert "widthType" not in node["attrs"]


class TestCreateLinkFallbackNode:
    def test_creates_valid_paragraph_with_link(self):
        info = AttachmentInfo(
            id="12345",
            filename="doc.pdf",
            mime_type="application/pdf",
            size=2048,
        )
        node = create_link_fallback_node(info, "https://example.atlassian.net")
        assert node["type"] == "paragraph"
        assert len(node["content"]) == 1
        text_node = node["content"][0]
        assert text_node["type"] == "text"
        assert text_node["text"] == "doc.pdf"
        assert text_node["marks"][0]["type"] == "link"
        assert (
            text_node["marks"][0]["attrs"]["href"]
            == "https://example.atlassian.net/rest/api/3/attachment/content/12345"
        )


class TestParseAttachmentContentUrl:
    def test_extracts_id_from_full_url(self):
        url = "https://example.atlassian.net/rest/api/3/attachment/content/12345"
        assert parse_attachment_content_url(url) == "12345"

    def test_extracts_id_from_relative_url(self):
        url = "/rest/api/3/attachment/content/98765"
        assert parse_attachment_content_url(url) == "98765"

    def test_returns_none_for_invalid_url(self):
        assert parse_attachment_content_url("https://example.com/other/path") is None
        assert parse_attachment_content_url("") is None
        assert parse_attachment_content_url(None) is None


class TestBuildDescriptionAdfWithMedia:
    def _text_to_adf(self, text):
        """Minimal ADF for text (paragraph with text node)."""
        return {
            "version": 1,
            "type": "doc",
            "content": [
                {
                    "type": "paragraph",
                    "content": [{"type": "text", "text": text}],
                }
            ],
        }

    def test_empty_description_returns_minimal_adf(self):
        result = build_description_adf_with_media(
            "", {}, "issue-1", "https://example.atlassian.net", self._text_to_adf
        )
        assert result["type"] == "doc"
        assert result["content"] == [{"type": "paragraph", "content": []}]

    def test_attachment_url_embeds_as_media_single_for_image(self):
        attachments_map = {
            "12345": AttachmentInfo(
                id="12345",
                filename="screenshot.png",
                mime_type="image/png",
                size=1024,
                collection_id="issue-1",
            ),
        }
        md = "Some text ![screenshot](https://x.atlassian.net/rest/api/3/attachment/content/12345) more"
        result = build_description_adf_with_media(
            md,
            attachments_map,
            "issue-1",
            "https://example.atlassian.net",
            self._text_to_adf,
        )
        assert result["type"] == "doc"
        content = result["content"]
        assert len(content) >= 2
        media_single = next(
            (c for c in content if c.get("type") == "mediaSingle"), None
        )
        assert media_single is not None
        attrs = media_single["content"][0]["attrs"]
        assert attrs["type"] == "external"
        assert "12345" in attrs["url"]

    def test_attachment_url_non_embeddable_creates_link(self):
        attachments_map = {
            "999": AttachmentInfo(
                id="999",
                filename="doc.pdf",
                mime_type="application/pdf",
                size=2048,
                collection_id="issue-1",
            ),
        }
        md = "See ![doc](https://x/rest/api/3/attachment/content/999)"
        result = build_description_adf_with_media(
            md,
            attachments_map,
            "issue-1",
            "https://example.atlassian.net",
            self._text_to_adf,
        )
        assert result["type"] == "doc"
        # Find paragraph with link (create_link_fallback_node produces paragraph with text+link)
        paras_with_link = [
            c
            for c in result["content"]
            if c.get("type") == "paragraph"
            and c.get("content")
            and c["content"][0].get("marks")
        ]
        assert len(paras_with_link) >= 1
        link_para = paras_with_link[0]
        assert link_para["content"][0]["type"] == "text"
        assert link_para["content"][0]["marks"][0]["type"] == "link"

    def test_pending_placeholder_embeds_when_in_map(self):
        attachments_map = {
            "img1": AttachmentInfo(
                id="1977806",
                filename="paste.png",
                mime_type="image/png",
                size=0,
                collection_id="issue-1",
            ),
        }
        md = "Before ![paste](pending:img1) after"
        result = build_description_adf_with_media(
            md,
            attachments_map,
            "issue-1",
            "https://example.atlassian.net",
            self._text_to_adf,
        )
        media_single = next(
            (c for c in result["content"] if c.get("type") == "mediaSingle"), None
        )
        assert media_single is not None
        attrs = media_single["content"][0]["attrs"]
        assert attrs["type"] == "external"
        assert "1977806" in attrs["url"]
