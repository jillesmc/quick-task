"""
ADF (Atlassian Document Format) media utilities for Jira attachments.

Provides attachment type detection, image dimension extraction, and ADF node
creation for embedding images/videos or linking files in Jira descriptions
and comments.
"""

import mimetypes
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Literal, Optional, Tuple

# -----------------------------------------------------------------------------
# AttachmentTypeDetector
# -----------------------------------------------------------------------------

IMAGE_MIMES: frozenset[str] = frozenset(
    {
        "image/png",
        "image/jpeg",
        "image/jpg",
        "image/gif",
        "image/svg+xml",
        "image/bmp",
        "image/webp",
    }
)

VIDEO_MIMES: frozenset[str] = frozenset(
    {
        "video/mp4",
        "video/quicktime",
        "video/x-msvideo",
        "video/webm",
    }
)


def get_type(
    filename: str,
    mime_type: Optional[str] = None,
) -> Literal["image", "video", "file"]:
    """
    Determines the attachment type from filename and optional MIME type.

    Args:
        filename: Name of the file (used for extension fallback).
        mime_type: MIME type if known (e.g. from Jira API).

    Returns:
        "image", "video", or "file".
    """
    if mime_type:
        mime_lower = mime_type.strip().lower()
        if mime_lower in IMAGE_MIMES:
            return "image"
        if mime_lower in VIDEO_MIMES:
            return "video"

    guessed, _ = mimetypes.guess_type(filename)
    if guessed:
        guessed_lower = guessed.strip().lower()
        if guessed_lower in IMAGE_MIMES:
            return "image"
        if guessed_lower in VIDEO_MIMES:
            return "video"

    return "file"


def should_embed(attachment_type: str, filename: Optional[str] = None) -> bool:
    """
    Returns True if the attachment type should be embedded (image/video).

    Args:
        attachment_type: One of "image", "video", or "file".
        filename: Optional filename/alt; when "file" and filename is generic
                  (e.g. "attachment"), treat as image for embed (user added via
                  embed dialog; preserves width instead of converting to link).

    Returns:
        True for image and video, False for file (unless generic filename).
    """
    if attachment_type in ("image", "video"):
        return True
    if attachment_type == "file" and filename:
        # Generic "attachment" alt from markdown → assume image (embed dialog flow)
        fn_lower = filename.strip().lower()
        if fn_lower in ("attachment", "imagem", "image"):
            return True
    return False


# -----------------------------------------------------------------------------
# ImageDimensionExtractor
# -----------------------------------------------------------------------------

_PillowImage = None


def _get_pillow_image():
    """Lazy import of PIL.Image; returns None if Pillow is unavailable."""
    global _PillowImage
    if _PillowImage is not None:
        return _PillowImage
    try:
        from PIL import Image

        _PillowImage = Image
        return _PillowImage
    except ImportError:
        _PillowImage = False
        return None


def get_dimensions(file_path: str) -> Optional[Tuple[int, int]]:
    """
    Returns image dimensions (width, height) using Pillow.

    Args:
        file_path: Path to the image file.

    Returns:
        (width, height) tuple or None if Pillow is unavailable or file is invalid.
    """
    img_cls = _get_pillow_image()
    if not img_cls:
        return None
    try:
        path = Path(file_path)
        if not path.exists() or not path.is_file():
            return None
        with img_cls.open(path) as im:
            return (im.width, im.height)
    except Exception:
        return None


def get_display_size(
    width: int,
    height: int,
    max_width: int = 760,
) -> Tuple[int, int]:
    """
    Computes display dimensions preserving aspect ratio, capping width.

    Args:
        width: Original width in pixels.
        height: Original height in pixels.
        max_width: Maximum display width (default 760, common for Jira).

    Returns:
        (display_width, display_height) tuple.
    """
    if width <= 0 or height <= 0:
        return (max_width, max_width)
    if width <= max_width:
        return (width, height)
    ratio = max_width / width
    new_height = int(height * ratio)
    return (max_width, max(1, new_height))


# -----------------------------------------------------------------------------
# AttachmentInfo
# -----------------------------------------------------------------------------


@dataclass
class AttachmentInfo:
    """Metadata for a Jira attachment used in ADF nodes."""

    id: str
    filename: str
    mime_type: str
    size: int
    width: Optional[int] = None
    height: Optional[int] = None
    collection_id: Optional[str] = None
    layout: Optional[str] = (
        None  # mediaSingle layout: center, wrap-left, wrap-right, etc.
    )
    display_width: Optional[int] = None  # Largura máxima de exibição (px)


# -----------------------------------------------------------------------------
# ADF node builders
# -----------------------------------------------------------------------------


def create_media_single_node(
    attachment_info: AttachmentInfo,
    layout: Optional[str] = None,
    display_width: Optional[int] = None,
    base_url: Optional[str] = None,
) -> dict:
    """
    Creates an ADF mediaSingle node for embedding an image or video.

    Uses type "external" with attachment content URL when base_url is provided.
    Jira Cloud's Media API UUID is not publicly available (CLOUD-12467), so
    attachment IDs from the REST API cannot be used with type "file". The
    external URL approach works: embed the image via the attachment content URL.
    See: https://community.atlassian.com/t5/Jira-questions/How-can-I-add-an-image-in-a-comment/qaq-p/952016

    Args:
        attachment_info: Attachment metadata (id, filename, mime_type, etc.).
        layout: Layout for mediaSingle ("center", "wrap-left", "wrap-right",
                "wide", "full-width", "align-start", "align-end").
                If None, uses attachment_info.layout or "center".
        display_width: Override display width; if None, uses attachment_info
                      width/height or defaults.
        base_url: Jira server base URL. When provided, uses type "external" with
                  attachment content URL (works with REST attachment IDs).
                  When None, uses type "file" with id/collection (requires Media
                  API UUID, not publicly available).

    Returns:
        ADF mediaSingle node dict.
    """
    resolved_layout = layout or attachment_info.layout or "center"
    width = attachment_info.width
    height = attachment_info.height

    if width is None or height is None:
        width = 400
        height = 300

    if display_width is not None and width > 0 and height > 0:
        width, height = get_display_size(width, height, max_width=display_width)

    server = (base_url or "").rstrip("/")

    if server and attachment_info.id:
        # Use type "external" with attachment content URL - works with REST API
        # attachment IDs. Media API UUID is not publicly available.
        content_url = f"{server}/rest/api/3/attachment/content/{attachment_info.id}"
        media_attrs: dict = {
            "type": "external",
            "url": content_url,
            "width": width,
            "height": height,
        }
    else:
        # Legacy type "file" - requires Media API UUID (not obtainable via public API)
        cid = attachment_info.collection_id or ""
        if cid and not cid.startswith("contentId-"):
            cid = f"contentId-{cid}"
        collection = cid or "contentId-unknown"
        media_attrs = {
            "id": attachment_info.id,
            "type": "file",
            "collection": collection,
            "alt": attachment_info.filename,
            "width": width,
            "height": height,
        }

    media_node = {"type": "media", "attrs": media_attrs}

    attrs: dict = {"layout": resolved_layout}
    # ADF mediaSingle: width/widthType control display size (pixel or percentage)
    if (
        display_width is not None
        and display_width > 0
        and resolved_layout
        not in (
            "wide",
            "full-width",
        )
    ):
        attrs["width"] = display_width
        attrs["widthType"] = "pixel"
    return {
        "type": "mediaSingle",
        "attrs": attrs,
        "content": [media_node],
    }


def create_link_fallback_node(
    attachment_info: AttachmentInfo,
    base_url: str,
) -> dict:
    """
    Creates an ADF paragraph node with a link to the attachment.

    Args:
        attachment_info: Attachment metadata.
        base_url: Base URL (e.g. Jira server URL) to construct the full link.
                  The attachment content URL is typically
                  {base_url}/rest/api/3/attachment/content/{id}.

    Returns:
        ADF paragraph node with link.
    """
    server = base_url.rstrip("/")
    href = f"{server}/rest/api/3/attachment/content/{attachment_info.id}"
    link_node = {
        "type": "text",
        "text": attachment_info.filename,
        "marks": [{"type": "link", "attrs": {"href": href}}],
    }
    return {
        "type": "paragraph",
        "content": [link_node],
    }


def parse_attachment_content_url(url: Optional[str]) -> Optional[str]:
    """
    Extracts the attachment ID from a Jira attachment content URL.

    Args:
        url: URL such as
             "https://example.atlassian.net/rest/api/3/attachment/content/12345"
             or "/rest/api/3/attachment/content/12345".

    Returns:
        Attachment ID string (e.g. "12345") or None if not found.
    """
    if not url or not isinstance(url, str):
        return None
    pattern = r"/rest/api/3/attachment/content/([^/?#]+)"
    match = re.search(pattern, url)
    return match.group(1) if match else None


# Pattern to match markdown images: ![alt](pending:xyz) or ![alt](.../attachment/content/123...)
_MD_IMAGE_PENDING = re.compile(r"!\[(.*?)\]\(pending:(\w+)\)")
_MD_IMAGE_ATTACHMENT = re.compile(
    r"!\[(.*?)\]\(([^)]*?/attachment/content/(\d+)[^)]*)\)"
)
# Pattern for links [alt](url) to attachments - missing ! causes link instead of image
_MD_LINK_ATTACHMENT = re.compile(r"\[(.*?)\]\(([^)]*?/attachment/content/(\d+)[^)]*)\)")
# Pattern for pending link (non-image file): [filename](pending:id)
_MD_LINK_PENDING = re.compile(r"\[(.*?)\]\(pending:(\w+)\)")
# Regex para attr_list {: width="N" } após imagem
_RE_ATTR_WIDTH = re.compile(r'\s*\{:\s*width=["\']?(\d+)["\']?\s*\}')


def build_description_adf_with_media(
    description_markdown: str,
    attachments_map: Dict[str, AttachmentInfo],
    issue_id: str,
    base_url: str,
    text_to_adf_fn,
) -> Dict[str, Any]:
    """
    Builds an ADF document from markdown description, replacing image/video
    placeholders and attachment URLs with mediaSingle or link nodes.

    Args:
        description_markdown: Markdown description (may contain ![alt](pending:id)
            or ![alt](.../attachment/content/123...).
        attachments_map: Dict mapping placeholder_id or attachment_id or content_url
            -> AttachmentInfo.
        issue_id: Issue ID (used as collection_id for media nodes).
        base_url: Jira server base URL for link fallbacks.
        text_to_adf_fn: Callable(str) -> dict to convert plain text to ADF.

    Returns:
        Full ADF doc dict.
    """
    if not description_markdown or not description_markdown.strip():
        return {
            "version": 1,
            "type": "doc",
            "content": [{"type": "paragraph", "content": []}],
        }

    content: List[Dict[str, Any]] = []
    last_end = 0

    def _find_next_match(
        txt: str, start: int
    ) -> Optional[Tuple[int, int, str, str, str]]:
        """Returns (start, end, alt, key, match_type) or None. Picks earliest match."""
        candidates: List[Tuple[int, int, str, str, str]] = []

        m = _MD_IMAGE_PENDING.search(txt, start)
        if m:
            candidates.append(
                (m.start(), m.end(), m.group(1) or "", m.group(2), "pending")
            )
        m = _MD_LINK_PENDING.search(txt, start)
        if m:
            candidates.append(
                (m.start(), m.end(), m.group(1) or "", m.group(2), "pending")
            )
        m = _MD_IMAGE_ATTACHMENT.search(txt, start)
        if m:
            end = m.end()
            rest = txt[end : end + 80]
            attr_match = _RE_ATTR_WIDTH.match(rest)
            if attr_match:
                end += attr_match.end()
            candidates.append(
                (m.start(), end, m.group(1) or "", m.group(3), "attachment")
            )
        m = _MD_LINK_ATTACHMENT.search(txt, start)
        if m:
            end = m.end()
            rest = txt[end : end + 80]
            attr_match = _RE_ATTR_WIDTH.match(rest)
            if attr_match:
                end += attr_match.end()
            candidates.append(
                (m.start(), end, m.group(1) or "", m.group(3), "attachment")
            )

        if not candidates:
            return None
        return min(candidates, key=lambda x: x[0])

    def _lookup_attachment(
        key: str, url_part: Optional[str]
    ) -> Optional[AttachmentInfo]:
        if key in attachments_map:
            return attachments_map[key]
        if url_part and url_part in attachments_map:
            return attachments_map[url_part]
        return None

    pos = 0
    text = description_markdown
    while True:
        m = _find_next_match(text, pos)
        if not m:
            break
        start, end, alt, key, match_type = m
        url_part = None
        if match_type == "attachment":
            url_match = re.search(r"\]\(([^)]+)\)", text[start:end])
            url_part = url_match.group(1) if url_match else None

        # Text before this match
        if start > last_end:
            segment = text[last_end:start].strip()
            if segment:
                adf = text_to_adf_fn(segment)
                seg_content = adf.get("content", [])
                content.extend(seg_content)

        # Lookup attachment
        info = _lookup_attachment(key, url_part)
        if not info and match_type == "attachment":
            display_width = None
            rest = text[end : end + 80]
            w_match = _RE_ATTR_WIDTH.match(rest)
            if w_match:
                try:
                    display_width = int(w_match.group(1))
                except (TypeError, ValueError):
                    pass
            info = AttachmentInfo(
                id=key,
                filename=alt or f"attachment-{key}",
                mime_type="",
                size=0,
                collection_id=issue_id,
                display_width=display_width,
            )

        if info:
            atype = get_type(info.filename, info.mime_type)
            if should_embed(atype, info.filename):
                node = create_media_single_node(
                    AttachmentInfo(
                        id=info.id,
                        filename=info.filename or alt or f"attachment-{info.id}",
                        mime_type=info.mime_type,
                        size=info.size,
                        width=info.width,
                        height=info.height,
                        collection_id=info.collection_id or issue_id,
                        layout=info.layout,
                        display_width=getattr(info, "display_width", None),
                    ),
                    base_url=base_url,
                    display_width=getattr(info, "display_width", None),
                )
                content.append(node)
            else:
                link_info = AttachmentInfo(
                    id=info.id,
                    filename=info.filename or alt or f"attachment-{info.id}",
                    mime_type=info.mime_type,
                    size=info.size,
                    collection_id=info.collection_id or issue_id,
                )
                content.append(create_link_fallback_node(link_info, base_url))
        else:
            if match_type == "attachment" and url_part:
                info = AttachmentInfo(
                    id=key,
                    filename=alt or f"attachment-{key}",
                    mime_type="",
                    size=0,
                    collection_id=issue_id,
                )
                content.append(create_link_fallback_node(info, base_url))
            else:
                content.append(
                    {
                        "type": "paragraph",
                        "content": [{"type": "text", "text": f"[Image: {alt or key}]"}],
                    }
                )

        last_end = end
        pos = end

    if last_end < len(text):
        segment = text[last_end:].strip()
        if segment:
            adf = text_to_adf_fn(segment)
            seg_content = adf.get("content", [])
            content.extend(seg_content)

    if not content:
        content = [{"type": "paragraph", "content": []}]

    return {"version": 1, "type": "doc", "content": content}
