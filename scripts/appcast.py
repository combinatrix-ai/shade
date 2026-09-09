import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from email.utils import formatdate
version, build, repo, signature_path = sys.argv[1:]
attrs = dict(re.findall(r'(\w+(?::\w+)?)="([^"]+)"', Path(signature_path).read_text()))
assert "sparkle:edSignature" in attrs and "length" in attrs
assert int(attrs["length"]) == Path("dist/Shade.zip").stat().st_size
ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", ns)
rss = ET.Element("rss", version="2.0")
channel = ET.SubElement(rss, "channel")
ET.SubElement(channel, "title").text = "Shade"
ET.SubElement(channel, "link").text = f"https://github.com/{repo}"
item = ET.SubElement(channel, "item")
ET.SubElement(item, "title").text = f"Shade {version}"
ET.SubElement(item, "pubDate").text = formatdate(usegmt=True)
for key, value in [("version", build), ("shortVersionString", version), ("minimumSystemVersion", "14.0")]:
    ET.SubElement(item, f"{{{ns}}}{key}").text = value
ET.SubElement(item, "enclosure", {"url": f"https://github.com/{repo}/releases/download/v{version}/Shade.zip", "length": attrs["length"], f"{{{ns}}}edSignature": attrs["sparkle:edSignature"], "type": "application/octet-stream"})
ET.indent(rss)
ET.ElementTree(rss).write("dist/appcast.xml", encoding="utf-8", xml_declaration=True)
