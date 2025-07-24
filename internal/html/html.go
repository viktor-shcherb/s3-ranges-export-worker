package html

import (
	"io"
	"strings"

	"github.com/PuerkitoBio/goquery"
)

// ExtractLandingText pulls headlines, paragraphs, bullets, and meta description.
func ExtractLandingText(r io.Reader) (string, error) {
	doc, err := goquery.NewDocumentFromReader(r)
	if err != nil {
		return "", err
	}

	// 1) Remove obvious noise
	doc.Find("script, style, nav, footer, .cookie-banner, .ads, .newsletter").Remove()

	// 2) Grab meta description if present
	var parts []string
	if desc, exists := doc.Find(`meta[name="description"]`).Attr("content"); exists {
		parts = append(parts, desc)
	}

	// 3) Pull main headings and paragraphs
	doc.Find("h1, h2, h3, p, li").Each(func(i int, s *goquery.Selection) {
		text := strings.TrimSpace(s.Text())
		if text != "" {
			parts = append(parts, text)
		}
	})

	return strings.Join(parts, "\n\n"), nil
}
